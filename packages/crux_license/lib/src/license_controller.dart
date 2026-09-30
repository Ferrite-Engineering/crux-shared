// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The collaborators below are named publicly and stored privately, which
// prefer_initializing_formals objects to. Not `required this._validator`: a
// private initializing formal is published under its private name in tooling
// that reads parameter names, including the api/*.api.txt goldens, and
// callers pass `validator:`.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:crux_license/src/crux_product.dart';
import 'package:crux_license/src/keygen_client.dart';
import 'package:crux_license/src/keygen_issuer.dart';
import 'package:crux_license/src/license_actions.dart';
import 'package:crux_license/src/license_credential.dart';
import 'package:crux_license/src/license_grace.dart';
import 'package:crux_license/src/license_grant.dart';
import 'package:crux_license/src/license_status.dart';
import 'package:crux_license/src/license_validation.dart';
import 'package:crux_license/src/license_validator.dart';
import 'package:crux_license/src/machine_release_marker.dart';
import 'package:meta/meta.dart';

/// Where a product keeps the credential and the small amount of state that
/// goes with it.
///
/// Deliberately an interface rather than an implementation. The credential is
/// something the user typed and must never reach `shared_preferences`, so the
/// binding each product supplies is `crux_secrets` over the OS credential
/// store — but this package has no business knowing that, and tests want a map.
abstract class LicenseStore {
  /// The stored credential, or `null` when there is none.
  Future<String?> readCredential();

  /// Store [credential], replacing any previous one.
  Future<void> writeCredential(String credential);

  /// Forget the credential and everything derived from it.
  Future<void> clear();

  /// This machine's opaque fingerprint, created on first use and stable
  /// thereafter.
  ///
  /// Created rather than derived: a fingerprint computed from hardware or
  /// hostname is a fingerprint that changes when a user renames their laptop
  /// and silently burns a seat. A random value minted once identifies exactly
  /// what Keygen needs it to — this machine — and nothing about the person
  /// running it.
  ///
  /// **This machine, not this install.** A suite licence's seat count counts
  /// machines, so every product on a computer must present the same
  /// fingerprint, or four products look like four machines and a three-seat
  /// licence is exhausted at the third product. A store answers this from
  /// `SharedInstallFingerprint`, which keeps the value in a file every product
  /// on the account reads; the credential store, being per application, holds
  /// only what is genuinely per product.
  Future<String> readOrCreateFingerprint();

  /// The issuer-side machine id from the last successful activation.
  Future<String?> readMachineId();

  /// Remember [machineId] so this machine can be deactivated later.
  Future<void> writeMachineId(String? machineId);

  /// When the issuer last confirmed the licence.
  Future<DateTime?> readLastCheck();

  /// Remember that the issuer confirmed the licence at [at].
  Future<void> writeLastCheck(DateTime at);

  /// What the issuer said at the last check that reached it, or `null` when
  /// nothing has been recorded.
  ///
  /// Opaque to the store: the controller owns the encoding. It has to survive
  /// a relaunch because the key cannot carry it. A renewal extends the licence
  /// without reissuing the key, so the key's own expiry goes stale on the first
  /// renewal, and a suspension exists only at the issuer. Held in memory
  /// alone, both were forgotten on every launch that fell inside the
  /// phone-home interval, which read a renewed subscriber as expired and a
  /// cancelled one as paid.
  ///
  /// The store is the user's, so what is written here is the issuer's own
  /// signed answer, verified again on every load. An entry the user wrote or
  /// edited fails that check and the key's own claims apply instead; nothing
  /// in the store can extend a licence past what the issuer signed.
  Future<String?> readIssuerSnapshot();

  /// Remember [snapshot], or forget it when `null`. [clear] forgets it too.
  Future<void> writeIssuerSnapshot(String? snapshot);
}

/// Facts about the machine that Keygen labels an activation with.
@immutable
class LicenseMachineIdentity {
  /// Create an identity.
  const LicenseMachineIdentity({required this.name, required this.platform});

  /// Human-readable name, shown in Keygen's portal and in the panel so a
  /// buyer can tell which seat is which.
  final String name;

  /// Platform label, e.g. `macos`.
  final String platform;
}

/// The licensing state machine, shared by all four products.
///
/// ### Why this is here and not four times over
///
/// `LicenseService` lives in each product's Pro overlay, and it stays there —
/// but "the same work four times" is how four implementations drift, and the
/// parts that would drift are the parts that must not: which validation code
/// means expired, when grace starts, whether a failed phone-home downgrades
/// anyone. Those live here, once. What stays per-product is genuinely
/// per-product: the storage binding, the machine name, the purchase URLs, and
/// the provider overrides.
///
/// Nothing here is a paid capability. It is the mechanism that *enforces*
/// payment, it embeds no token (the Keygen policies authenticate with the
/// customer's own key), and it can grant nothing a signed licence does not
/// already say.
///
/// ### Offline first, always
///
/// A validated credential works with no network. Every path that cannot reach
/// the issuer keeps the last known state and records nothing — `refresh` is a
/// refresh, never a precondition. The one exception is a licence whose expiry
/// has passed *and* whose grace window has run out, which is a conclusion the
/// app can reach from its own clock.
class CruxLicenseController implements CruxLicenseActions {
  /// Create a controller.
  CruxLicenseController({
    required this.product,
    required LicenseValidator validator,
    required LicenseStore store,
    required KeygenLicenseClient client,
    required LicenseMachineIdentity machine,
    required Future<void> Function(Uri url) openUrl,
    required Uri purchaseUrl,
    Uri? manageUrl,
    Uri? educationalRequestUrl,
    LicenseGracePolicy grace = LicenseGracePolicy.standard,
    Duration phoneHomeInterval = const Duration(hours: 24),
    DateTime Function() now = DateTime.now,
    MachineReleaseMarker releaseMarker = const NoMachineReleaseMarker(),
  }) : _validator = validator,
       _store = store,
       _client = client,
       _machine = machine,
       _openUrl = openUrl,
       _purchaseUrl = purchaseUrl,
       _manageUrl = manageUrl,
       _educationalRequestUrl = educationalRequestUrl,
       _grace = grace,
       _phoneHomeInterval = phoneHomeInterval,
       _now = now,
       _releaseMarker = releaseMarker;

  /// The product this build is.
  final CruxProduct product;

  final LicenseValidator _validator;
  final LicenseStore _store;
  final KeygenLicenseClient _client;
  final LicenseMachineIdentity _machine;
  final MachineReleaseMarker _releaseMarker;
  final Future<void> Function(Uri url) _openUrl;
  final Uri _purchaseUrl;
  final Uri? _manageUrl;
  final Uri? _educationalRequestUrl;
  final LicenseGracePolicy _grace;
  final Duration _phoneHomeInterval;
  final DateTime Function() _now;

  final StreamController<CruxLicenseStatus> _statuses =
      StreamController<CruxLicenseStatus>.broadcast();
  Timer? _phoneHome;

  CruxLicenseStatus _status = CruxLicenseStatus.openCore;

  /// The current status.
  CruxLicenseStatus get status => _status;

  /// Every status the controller publishes, for the provider seam to watch.
  Stream<CruxLicenseStatus> get statuses => _statuses.stream;

  /// Load the stored credential and resolve it offline.
  ///
  /// Call once at startup. Deliberately does **not** wait on the network: a
  /// paying customer opening the app on a plane sees Pro immediately, and the
  /// phone-home that follows can take as long as it likes.
  Future<void> start() async {
    await _resolveFromStore();
    _phoneHome?.cancel();
    _phoneHome = Timer.periodic(_phoneHomeInterval, (_) {
      unawaited(refresh());
    });
    if (_status.hasCredential && await _isCheckDue()) {
      unawaited(refresh());
    }
  }

  /// Stop the phone-home timer and release the client.
  Future<void> dispose() async {
    _phoneHome?.cancel();
    _phoneHome = null;
    _client.close();
    await _statuses.close();
  }

  @override
  Future<CruxLicenseActionResult> activate(String credential) async {
    _publish(_status.copyWith(busy: true));
    try {
      final String fingerprint;
      try {
        fingerprint = await _store.readOrCreateFingerprint();
      } on Object catch (error) {
        return LicenseActionFailed(
          CruxLicenseActionFailure.unknown,
          detail: 'credential store unavailable: $error',
        );
      }
      final validation = await _validator.validate(
        credential.trim(),
        fingerprint: fingerprint,
      );
      final grant = validation.grant;
      if (validation is LicenseRejected) {
        return LicenseActionFailed(
          CruxLicenseActionFailure.rejected,
          rejection: validation.reason,
          detail: validation.detail,
        );
      }
      if (grant == null) {
        return const LicenseActionFailed(
          CruxLicenseActionFailure.rejected,
          rejection: LicenseRejection.malformed,
        );
      }

      // Store before the network call: the licence is already cryptographically
      // good, and a customer who activates on a flaky connection should not
      // have to paste a 700-character key twice.
      await _store.writeCredential(credential.trim());

      final licenseId = grant.licenseId;
      // A key the user just pasted is a key the user wants, whatever a sibling
      // product noted when it released this machine earlier. Cleared before
      // anything below can consult the marker, and the resolves on this path
      // do not consult it at all, so a note that could not be cleared still
      // cannot undo the paste.
      if (licenseId != null) await _clearReleased(licenseId);

      final issuerKey = _issuerKeyFor(credential.trim());
      if (licenseId != null && issuerKey != null) {
        final result = await _client.activateMachine(
          key: issuerKey,
          licenseId: licenseId,
          fingerprint: fingerprint,
          name: _machine.name,
          platform: _machine.platform,
        );
        if (result.outcome == KeygenMachineOutcome.noSeatAvailable) {
          // The credential stays stored, so the machine can take a seat the
          // moment one is freed. Until then it runs Open Core: a licence that
          // keeps working on a machine the issuer refused is a licence a
          // whole team can share.
          await _loadIssuerOnce();
          await _recordSeatRefused(licenseId);
          await _resolveFromStore(honourRelease: false);
          return const LicenseActionFailed(
            CruxLicenseActionFailure.noSeatAvailable,
          );
        }
        if (result.outcome == KeygenMachineOutcome.refused) {
          // Ask the issuer why, so a suspended or expired licence is recorded
          // as that rather than granted until the next phone-home.
          await _refreshFromIssuer(credential.trim());
          await _resolveFromStore(honourRelease: false);
          return LicenseActionFailed(
            CruxLicenseActionFailure.refusedByIssuer,
            detail: result.detail,
          );
        }
        await _rememberMachine(
          result,
          key: issuerKey,
          fingerprint: fingerprint,
        );
      }

      if (await _refreshFromIssuer(credential.trim())) {
        await _reconcileMachine(credential.trim());
      }
      await _resolveFromStore(honourRelease: false);
      return const LicenseActionSucceeded();
    } finally {
      _publish(_status.copyWith(busy: false));
    }
  }

  /// Release this machine's seat — the machine's, suite-wide.
  ///
  /// The fingerprint is shared by every product on the machine, and the
  /// issuer accepts it in place of the machine's id, so the release is made
  /// by fingerprint: it works from whichever product the user is in, including
  /// one that never registered the machine itself and holds no id for it. The
  /// id this product may hold is the fallback for a refusal, not the primary
  /// key — it names the machine this product registered, which under a
  /// fingerprint that has since been shared may be an older, orphaned record.
  ///
  /// The other products on the machine still hold the key, and their next
  /// check-in would find the machine unregistered and register it again. So
  /// the release is noted in the shared [MachineReleaseMarker] before the
  /// store is cleared; each of them consults the note before it contacts the
  /// issuer and drops its key instead.
  @override
  Future<CruxLicenseActionResult> deactivateThisMachine() async {
    _publish(_status.copyWith(busy: true));
    try {
      final String? credential;
      final String? machineId;
      final String fingerprint;
      try {
        credential = await _store.readCredential();
        machineId = await _store.readMachineId();
        fingerprint = await _store.readOrCreateFingerprint();
      } on Object catch (error) {
        return LicenseActionFailed(
          CruxLicenseActionFailure.unknown,
          detail: 'credential store unavailable: $error',
        );
      }
      final issuerKey = credential == null ? null : _issuerKeyFor(credential);
      // A file that carries no key cannot speak for its seat; clearing locally
      // is then the only way out, and support releases the seat, as the
      // airgap runbook already has it doing for files.
      if (issuerKey != null) {
        var result = await _client.deactivateMachine(
          key: issuerKey,
          machine: fingerprint,
        );
        if (result.outcome == KeygenMachineOutcome.refused &&
            machineId != null) {
          // The issuer would not resolve the fingerprint, but this product
          // registered a machine once and remembers which. Try that.
          result = await _client.deactivateMachine(
            key: issuerKey,
            machine: machineId,
          );
        }
        if (result.outcome == KeygenMachineOutcome.offline) {
          // Refusing here is the honest answer: clearing locally while the
          // seat stays counted at the issuer is how a customer ends up unable
          // to activate their own last machine.
          return const LicenseActionFailed(CruxLicenseActionFailure.offline);
        }
        // A suspended or deleted licence refuses the seat release, and that
        // refusal must not trap the customer: every cancellation ends in a
        // suspended licence, so this is the *normal* state of anyone who ever
        // bought and stopped. Clearing is also safe for the case that worried
        // me — a dunning suspension the customer later pays off — because the
        // machine record keeps this fingerprint, so re-pasting the key on this
        // same machine validates against the seat it already holds rather than
        // asking for a new one.
        if (!result.isOk &&
            result.outcome != KeygenMachineOutcome.licenseInactive) {
          return LicenseActionFailed(
            CruxLicenseActionFailure.refusedByIssuer,
            detail: result.detail,
          );
        }
      }
      if (credential != null) {
        // The note is for this licence and this fingerprint, so a sibling
        // product holding a different licence, or this one on a machine whose
        // identity has changed, reads it as none of its business.
        final licenseId = (await _validator.validate(
          credential,
          now: _now(),
          fingerprint: fingerprint,
        )).grant?.licenseId;
        if (licenseId != null) {
          await _markReleased(licenseId: licenseId, fingerprint: fingerprint);
        }
      }
      await _store.clear();
      _forgetIssuer();
      _publish(CruxLicenseStatus.openCore);
      return const LicenseActionSucceeded();
    } finally {
      if (_status.hasCredential) _publish(_status.copyWith(busy: false));
    }
  }

  @override
  Future<CruxLicenseActionResult> refresh() async {
    final String? credential;
    try {
      credential = await _store.readCredential();
    } on Object catch (error) {
      // Same reasoning as `_resolveFromStore`: an unreadable store is a
      // reason to change nothing, not a reason to crash the settings panel.
      return LicenseActionFailed(
        CruxLicenseActionFailure.unknown,
        detail: 'credential store unavailable: $error',
      );
    }
    if (credential == null) return const LicenseActionSucceeded();
    // Before any issuer contact, not after: a sibling product released this
    // machine, and the check-in below would otherwise find it unregistered
    // and register it again, undoing what the user just did.
    if (await _honourRelease()) return const LicenseActionSucceeded();
    _publish(_status.copyWith(busy: true));
    try {
      final reached = await _refreshFromIssuer(credential);
      if (reached) await _registerIfUnregistered(credential);
      if (reached) await _reconcileMachine(credential);
      await _resolveFromStore();
      if (reached) return const LicenseActionSucceeded();
      // A file that embeds no key was not asked about, which is not the same
      // as failing to reach anyone. Reporting `offline` here would tell a
      // customer whose network is perfectly fine to "try again when you are
      // online", which is both untrue and unactionable — there is no call
      // that would ever succeed, because such a file answers the question by
      // itself.
      return _issuerKeyFor(credential) == null
          ? const LicenseActionSucceeded()
          : const LicenseActionFailed(CruxLicenseActionFailure.offline);
    } finally {
      _publish(_status.copyWith(busy: false));
    }
  }

  @override
  Future<CruxLicenseActionResult> exportOfflineRequest() async {
    // What an airgapped machine can honestly produce is its own identity: the
    // product asking, the fingerprint a seat would be counted against, and a
    // label a human can match to a desk. It carries no secret, so it can
    // travel on a USB stick, in an email, or read aloud down a phone.
    //
    // The other half of the round trip is a Keygen licence file, which
    // `importOfflineToken` accepts — those embed the whole licence object
    // including entitlements, which is exactly why they resolve on a machine
    // that can never reach the issuer.
    final String fingerprint;
    try {
      fingerprint = await _store.readOrCreateFingerprint();
    } on Object catch (error) {
      return LicenseActionFailed(
        CruxLicenseActionFailure.unknown,
        detail: 'credential store unavailable: $error',
      );
    }
    return LicenseActionSucceeded(
      payload: const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'kind': 'crux.offline-activation-request/v1',
        'product': product.entitlementCode,
        'fingerprint': fingerprint,
        'machine': _machine.name,
        'platform': _machine.platform,
      }),
    );
  }

  @override
  Future<CruxLicenseActionResult> importOfflineToken(String token) =>
      // A Keygen licence file *is* a credential the validator understands, so
      // importing one is activation by another name. The airgap-specific
      // request/response flow is the remaining half.
      activate(token);

  @override
  Future<CruxLicenseActionResult> requestEducationalLicense(
    String email,
  ) async {
    final address = email.trim();
    if (!_looksInstitutional(address)) {
      return const LicenseActionFailed(
        CruxLicenseActionFailure.invalidEmail,
        detail: 'not an institutional address',
      );
    }
    final endpoint = _educationalRequestUrl;
    if (endpoint == null) {
      return const LicenseActionFailed(CruxLicenseActionFailure.notSupported);
    }

    _publish(_status.copyWith(busy: true));
    try {
      final outcome = await _client.requestEducationalLicense(
        endpoint: endpoint,
        email: address,
      );
      return outcome;
    } finally {
      _publish(_status.copyWith(busy: false));
    }
  }

  @override
  bool get supportsEducationalRequest => _educationalRequestUrl != null;

  /// A courtesy check, not the enforcement.
  ///
  /// The issuer decides what counts as educational; this only stops the
  /// obvious mistake of submitting a personal address and then waiting for a
  /// mail that is never coming. Deliberately permissive about the suffix:
  /// `.edu` is a US convention, and `ac.uk`, `edu.au`, `uni-*.de` and the
  /// rest are just as institutional.
  static bool _looksInstitutional(String email) {
    final at = email.lastIndexOf('@');
    if (at <= 0 || at == email.length - 1) return false;
    final domain = email.substring(at + 1).toLowerCase();
    return domain.contains('.') && !domain.contains(' ');
  }

  @override
  Future<CruxLicenseActionResult> openPurchasePage() => _open(_purchaseUrl);

  @override
  Future<CruxLicenseActionResult> openManagePage() {
    final url = _manageUrl;
    if (url == null) {
      return Future<CruxLicenseActionResult>.value(
        const LicenseActionFailed(CruxLicenseActionFailure.notSupported),
      );
    }
    return _open(url);
  }

  @override
  bool get supportsManageLink => _manageUrl != null;

  @override
  bool get supportsDeactivation => true;

  @override
  bool get supportsOfflineActivation => true;

  @override
  bool get supportsPurchaseLinks => true;

  Future<CruxLicenseActionResult> _open(Uri url) async {
    try {
      await _openUrl(url);
      return const LicenseActionSucceeded();
    } on Object catch (error) {
      return LicenseActionFailed(
        CruxLicenseActionFailure.unknown,
        detail: '$error',
      );
    }
  }

  /// Ask the issuer for current expiry and seat counts.
  ///
  /// Returns whether the issuer was reached. **Never downgrades on a failure
  /// to reach it** — that is the property the whole airgap story rests on.
  ///
  /// The question is always asked about a licence **key**: the credential
  /// itself when it is one, and the key a file embeds otherwise.
  /// `validate-key` takes a key, and handing it a file gets `NOT_FOUND` —
  /// which is indistinguishable from a revoked key and once invalidated a
  /// perfectly good licence. Measured against the live account:
  ///
  /// ```text
  /// POST …/licenses/actions/validate-key
  /// {"meta":{"key":"-----BEGIN LICENSE FILE----- …"}}
  /// → HTTP 200 {"meta":{"valid":false,"code":"NOT_FOUND"}}
  /// ```
  ///
  /// **HTTP 200**, so nothing upstream treats it as an error. An Enterprise
  /// customer who imported a file because their first activation could not be
  /// made, on a machine that later found a network, dropped to Open Core on
  /// the next phone-home with no grace at all.
  ///
  /// The file's own signed expiry and entitlements are what license a machine
  /// that can never reach anyone. On a machine that *can*, the embedded key is
  /// asked about exactly as a pasted key would be, so a cancelled or refunded
  /// licence is refused, a renewal is honoured, and a seat is registered —
  /// a file is not a way around the phone-home, only a way through its
  /// absence. A file that embeds no key has nothing to ask with and is left
  /// to its own claims.
  Future<bool> _refreshFromIssuer(String credential) async {
    final key = _issuerKeyFor(credential);
    if (key == null) return false;
    final fingerprint = await _store.readOrCreateFingerprint();
    final validation = await _client.validateKey(key, fingerprint: fingerprint);
    // Unreachable, unsigned and tampered are one case: nothing that can be
    // trusted was heard, so nothing changes and nothing is recorded.
    if (!validation.attested) return false;
    await _store.writeLastCheck(_now());
    // Bound to the licence the answer was about, so it can never be applied to
    // a different credential stored later in the same session or on disk.
    final checked = await _validator.validate(
      credential,
      now: _now(),
      fingerprint: fingerprint,
    );
    final licenseId = checked.grant?.licenseId;
    if (!_issuerLoaded) await _loadIssuerOnce();
    // A refused seat belongs to the licence it was refused on, and a machine
    // the issuer now calls valid holds a seat.
    if (licenseId != _issuerLicenseId ||
        validation.code == KeygenValidationCode.valid) {
      _issuerSeatRefused = false;
    }
    _issuerLicenseId = licenseId;
    _issuerExpiry = validation.expiry;
    _issuerSeats = validation.maxMachines;
    _issuerSeatsUsed = validation.machineCount;
    _issuerCode = validation.code;
    _issuerAttestation = validation.attestation;
    _issuerLoaded = true;
    _issuerAnswerStale = false;
    await _persistIssuer();
    return true;
  }

  /// Register this machine when the issuer says it holds no seat.
  ///
  /// Covers the activation that was made offline and the machine whose seat
  /// was refused before one was freed: both are unregistered, and the first
  /// check-in that reaches the issuer is where that gets settled. A refusal
  /// for want of seats is recorded and runs Open Core. Unreachable changes
  /// nothing, because offline keeps the tier.
  ///
  /// A licence over its seat count is not re-registered from here — this
  /// machine already holds a registration — but it is not licensed either:
  /// `_resolveFromStore` runs every machine on such a licence at Open Core
  /// until its owner frees seats, because seats are what Enterprise pays
  /// per and a reduction the owner made is a reduction the owner resolves.
  ///
  /// ### The orphan a shared fingerprint leaves behind
  ///
  /// A machine this product registered before the fingerprint was shared is
  /// registered under the fingerprint it had then. Once the shared one
  /// differs — because a sibling product's value was adopted first — the
  /// issuer answers `FINGERPRINT_SCOPE_MISMATCH` while this product still
  /// holds the old machine's id: a seat counted for a machine that no longer
  /// presents itself. Registering afresh would take a second seat for the
  /// same computer, which is the defect the shared fingerprint exists to
  /// close. So the old record is released first, by the id this product
  /// holds, and only then is the machine registered under the fingerprint it
  /// has now. Best effort: whatever the release answers, the id is forgotten
  /// and the registration proceeds — an orphan that would not go is support's
  /// to remove, and not a reason to leave the machine unlicensed.
  Future<void> _registerIfUnregistered(String credential) async {
    if (_issuerCode != KeygenValidationCode.noMachine &&
        _issuerCode != KeygenValidationCode.fingerprintScopeMismatch) {
      return;
    }
    final licenseId = _issuerLicenseId;
    final key = _issuerKeyFor(credential);
    if (licenseId == null || key == null) return;
    final fingerprint = await _store.readOrCreateFingerprint();
    if (_issuerCode == KeygenValidationCode.fingerprintScopeMismatch) {
      final orphan = await _store.readMachineId();
      if (orphan != null) {
        await _client.deactivateMachine(key: key, machine: orphan);
        await _store.writeMachineId(null);
      }
    }
    final result = await _client.activateMachine(
      key: key,
      licenseId: licenseId,
      fingerprint: fingerprint,
      name: _machine.name,
      platform: _machine.platform,
    );
    switch (result.outcome) {
      case KeygenMachineOutcome.ok:
      case KeygenMachineOutcome.alreadyActivated:
        await _rememberMachine(result, key: key, fingerprint: fingerprint);
        _issuerSeatRefused = false;
        await _persistIssuer();
        await _refreshFromIssuer(credential);
      case KeygenMachineOutcome.noSeatAvailable:
        await _recordSeatRefused(licenseId);
      case KeygenMachineOutcome.offline:
      case KeygenMachineOutcome.licenseInactive:
      case KeygenMachineOutcome.refused:
        break;
    }
  }

  Future<void> _recordSeatRefused(String licenseId) async {
    if (_issuerLicenseId != licenseId) _forgetIssuer();
    _issuerLicenseId = licenseId;
    _issuerSeatRefused = true;
    _issuerLoaded = true;
    await _persistIssuer();
  }

  /// Remember the id of the machine [result] registered, or already found
  /// registered.
  ///
  /// "Already activated" arrives without an id, and under a shared
  /// fingerprint it is the common case rather than the odd one: a sibling
  /// product registered this machine first. The id is asked for so this
  /// product can fall back to it on a release the fingerprint alone could not
  /// make; not finding it changes nothing, because release works by
  /// fingerprint.
  Future<void> _rememberMachine(
    KeygenMachineResult result, {
    required String key,
    required String fingerprint,
  }) async {
    var id = result.machineId;
    if (id == null && result.outcome == KeygenMachineOutcome.alreadyActivated) {
      id = await _client.findMachine(key: key, fingerprint: fingerprint);
    }
    if (id != null) await _holdMachine(id, key: key);
  }

  /// Remember [id] as this machine's registration, releasing the one this
  /// product held before when it was a different machine.
  ///
  /// The id a product holds always came from its own registration, so a held
  /// id that is not the machine the shared fingerprint now names is a record
  /// of this same computer under a fingerprint it no longer presents — the
  /// orphan a shared fingerprint leaves behind — and it is holding a seat.
  /// Released best effort: a record that will not go is support's to remove,
  /// and never a reason to forget the one that counts.
  Future<void> _holdMachine(String id, {required String key}) async {
    final held = await _store.readMachineId();
    // When the issuer has just said the licence holds no machine at all, the
    // held id is stale, not counted: nothing to release.
    if (held != null &&
        held != id &&
        _issuerCode != KeygenValidationCode.noMachine) {
      await _client.deactivateMachine(key: key, machine: held);
    }
    await _store.writeMachineId(id);
    // An id that came from the issuer's own answer about this fingerprint is
    // the reconciled one; the launch need not ask again.
    _machineReconciled = true;
  }

  /// Once per launch, after the issuer has called this machine valid: make
  /// sure the id this product holds is the machine the shared fingerprint
  /// names, and release the one it held if not.
  ///
  /// `_registerIfUnregistered` cannot reach this case. When a sibling
  /// product's machine already stands under the shared fingerprint, the
  /// issuer answers `VALID` for this product too, and the machine this
  /// product registered under the fingerprint it had before stays behind,
  /// counted, with nothing ever asking about it again — which on the first
  /// machine a suite licence was ever used on leaves every product but one
  /// holding a seat it no longer needs. So the question is asked once, on
  /// the launch that first hears `VALID`, and the answer settles it: the
  /// held id is kept when it is the machine, replaced — and the old record
  /// released — when it is not, and looked up for a product that holds none.
  /// A lookup the issuer could not answer is asked again next launch.
  Future<void> _reconcileMachine(String credential) async {
    if (_machineReconciled || _issuerCode != KeygenValidationCode.valid) {
      return;
    }
    final key = _issuerKeyFor(credential);
    if (key == null) return;
    final String fingerprint;
    final String? held;
    try {
      fingerprint = await _store.readOrCreateFingerprint();
      held = await _store.readMachineId();
    } on Object {
      return;
    }
    final current = await _client.findMachine(
      key: key,
      fingerprint: fingerprint,
    );
    if (current == null) return;
    _machineReconciled = true;
    if (current == held) return;
    await _holdMachine(current, key: key);
  }

  /// Drop the key when a sibling product released this machine's seat on the
  /// licence it grants, and say so. `false` when nothing was released, or
  /// nothing could be determined.
  ///
  /// Called before any issuer contact in [refresh], and by
  /// `_resolveFromStore` (so [start] honours it too): the alternative — a
  /// check-in that finds the machine unregistered and registers it again — is
  /// this product silently undoing a deactivation the user performed in
  /// another one. The store is cleared rather than the status merely changed,
  /// so the next launch does not resurrect the key; the user re-activates by
  /// pasting it, which clears the note.
  Future<bool> _honourRelease() async {
    final String? credential;
    final String fingerprint;
    try {
      credential = await _store.readCredential();
      if (credential == null) return false;
      fingerprint = await _store.readOrCreateFingerprint();
    } on Object {
      return false;
    }
    final licenseId = (await _validator.validate(
      credential,
      now: _now(),
      fingerprint: fingerprint,
    )).grant?.licenseId;
    if (licenseId == null) return false;
    final bool released;
    try {
      released = await _releaseMarker.wasReleased(
        licenseId: licenseId,
        fingerprint: fingerprint,
      );
    } on Object {
      return false;
    }
    if (!released) return false;
    try {
      await _store.clear();
    } on Object {
      // Nothing changes when the store cannot be written; the next check-in
      // asks the marker again.
      return false;
    }
    _forgetIssuer();
    _publish(CruxLicenseStatus.openCore);
    return true;
  }

  /// The marker is consulted on the licence path and must never fail it: an
  /// implementation that throws is treated as one that could not write.
  Future<void> _markReleased({
    required String licenseId,
    required String fingerprint,
  }) async {
    try {
      await _releaseMarker.markReleased(
        licenseId: licenseId,
        fingerprint: fingerprint,
      );
    } on Object {
      // Best effort; see `deactivateThisMachine`.
    }
  }

  Future<void> _clearReleased(String licenseId) async {
    try {
      await _releaseMarker.clearReleased(licenseId: licenseId);
    } on Object {
      // Best effort; the activation path does not consult the marker.
    }
  }

  /// Persist what the issuer said — as the issuer said it.
  ///
  /// The expiry, the code and the seat counts are not written as fields. They
  /// are re-read from the issuer's signed response on every load, so a store
  /// entry the user wrote cannot renew a lapsed subscription or turn a
  /// recorded suspension back into `valid`. Two things travel unsigned beside
  /// the answer, and both can only take a tier away: which licence the answer
  /// was about, and whether this machine was refused a seat.
  Future<void> _persistIssuer() async {
    try {
      await _store.writeIssuerSnapshot(
        jsonEncode(<String, Object?>{
          'licenseId': _issuerLicenseId,
          'seatRefused': _issuerSeatRefused,
          'attestation': _issuerAttestation?.toJson(),
        }),
      );
    } on Object {
      // The answer still applies for this session. Failing to write it only
      // costs the next launch what every launch cost before it was persisted.
    }
  }

  /// Read the persisted answer once per controller, before the first resolve
  /// that could use it. An unreadable or malformed snapshot is no snapshot:
  /// the key's own claims are still there to fall back on.
  ///
  /// The issuer's answer inside it is believed only when its signature still
  /// verifies against the account key, it is about the licence the entry
  /// names, and it was scoped to this install's fingerprint — the issuer
  /// echoes the scope inside the signed body, which is what stops an answer
  /// copied from another machine, or kept from a licence that was renewed and
  /// pointed at one that was not. Anything else leaves the issuer fields
  /// empty, and the key alone decides.
  Future<void> _loadIssuerOnce() async {
    if (_issuerLoaded) return;
    final String? raw;
    final String fingerprint;
    try {
      raw = await _store.readIssuerSnapshot();
      fingerprint = await _store.readOrCreateFingerprint();
    } on Object {
      return;
    }
    _issuerLoaded = true;
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return;
      final licenseId = json['licenseId'];
      _issuerLicenseId = licenseId is String ? licenseId : null;
      _issuerSeatRefused = json['seatRefused'] == true;
      final attestation = KeygenAttestation.fromJson(json['attestation']);
      if (attestation == null || !_client.attestsValidation(attestation)) {
        _issuerAnswerStale = true;
        return;
      }
      final answer = KeygenValidation.fromBody(
        attestation.decodedBody ?? const <String, Object?>{},
        attestation: attestation,
      );
      if (answer.licenseId != null && answer.licenseId != _issuerLicenseId) {
        _issuerAnswerStale = true;
        return;
      }
      if (answer.scopeFingerprint != null &&
          answer.scopeFingerprint != fingerprint) {
        // The answer was about a different fingerprint: this machine's
        // identity changed since the issuer was last asked — a product that
        // just adopted the fingerprint its siblings share is the ordinary
        // case. That makes a check due now, whatever the last one's date.
        _issuerAnswerStale = true;
        return;
      }
      _issuerAttestation = attestation;
      _issuerCode = answer.code;
      _issuerExpiry = answer.expiry;
      _issuerSeats = answer.maxMachines;
      _issuerSeatsUsed = answer.machineCount;
    } on FormatException {
      _forgetIssuer();
      _issuerLoaded = true;
    }
  }

  void _forgetIssuer() {
    _issuerLicenseId = null;
    _issuerExpiry = null;
    _issuerSeats = null;
    _issuerSeatsUsed = null;
    _issuerCode = null;
    _issuerAttestation = null;
    _issuerSeatRefused = false;
    _issuerAnswerStale = false;
  }

  /// The licence key to present to the issuer for [credential].
  ///
  /// A key is presented as itself. A file cannot be: it is multi-line, and
  /// Keygen authenticates machine calls with a `License` authorization header,
  /// which refuses line breaks — and `validate-key` answers `NOT_FOUND` to
  /// anything that is not a key. A `base64+ed25519` file embeds the licence
  /// resource, key included, so that key is presented instead, which is what
  /// lets a file-activated machine register and release its seat and be
  /// asked about. `null` when the file carries no key.
  ///
  /// Asked of the parser rather than of the raw text, so the answer stays in
  /// step with what the validator accepts. Unparseable text is presented as
  /// itself and takes the ordinary path, where the validator rejects it —
  /// which is where a bad paste is supposed to be answered.
  static String? _issuerKeyFor(String credential) {
    final envelope = parseLicenseCredential(credential).envelope;
    if (envelope == null || envelope.kind == LicenseCredentialKind.licenseKey) {
      return credential;
    }
    return KeygenLicenseIssuer.embeddedLicenseKey(envelope);
  }

  String? _issuerLicenseId;
  DateTime? _issuerExpiry;
  int? _issuerSeats;
  int? _issuerSeatsUsed;
  KeygenValidationCode? _issuerCode;
  KeygenAttestation? _issuerAttestation;
  bool _issuerSeatRefused = false;
  bool _issuerLoaded = false;

  /// The persisted answer was about another licence or another fingerprint,
  /// or could not be trusted, so nothing recorded speaks for this machine.
  bool _issuerAnswerStale = false;

  /// Whether `_reconcileMachine` has settled the held machine id this launch.
  bool _machineReconciled = false;

  /// Whether the issuer should be asked now: nothing recorded, the interval
  /// elapsed, or the recorded answer was not about this licence on this
  /// fingerprint (see `_loadIssuerOnce`).
  Future<bool> _isCheckDue() async {
    await _loadIssuerOnce();
    if (_issuerAnswerStale) return true;
    final last = await _store.readLastCheck();
    return last == null || _now().difference(last) >= _phoneHomeInterval;
  }

  /// Recompute the status from the stored credential and whatever the issuer
  /// last told us.
  ///
  /// First honours a release a sibling product noted, unless [honourRelease]
  /// is off — which it is on the activation path, where the credential is the
  /// one the user just pasted and the note, cleared or not, is stale.
  Future<void> _resolveFromStore({bool honourRelease = true}) async {
    if (honourRelease && await _honourRelease()) return;
    final String? credential;
    final String fingerprint;
    try {
      credential = await _store.readCredential();
      fingerprint = await _store.readOrCreateFingerprint();
    } on Object {
      // A locked or unavailable keychain is not evidence that the user has no
      // licence, so this keeps whatever was already resolved rather than
      // downgrading. On a cold start there is nothing to keep and the app
      // stays at Open Core — which is the only honest answer when it cannot
      // read its own store.
      return;
    }
    if (credential == null) {
      _publish(CruxLicenseStatus.openCore);
      return;
    }

    final now = _now();
    final validation = await _validator.validate(
      credential,
      now: now,
      fingerprint: fingerprint,
    );
    final grant = validation.grant;
    final lastCheck = await _store.readLastCheck();
    final machineId = await _store.readMachineId();

    if (grant == null) {
      _publish(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.invalid,
          rejection: validation is LicenseRejected
              ? validation.reason
              : LicenseRejection.malformed,
          lastCheckedAt: lastCheck,
          machineLabel: _machine.name,
        ),
      );
      return;
    }

    await _loadIssuerOnce();
    // Only what the issuer said about *this* licence counts.
    final fromIssuer =
        grant.licenseId != null && grant.licenseId == _issuerLicenseId;
    final issuerCode = fromIssuer ? _issuerCode : null;

    // The issuer's expiry is newer than the key's own, because a renewal
    // extends the licence without reissuing the key. Take the later of the
    // two: the key can only ever understate how long the customer has paid
    // for, and treating a renewed customer as expired is the failure that
    // costs the most.
    final keyExpiry = grant.expiry;
    final expiry = _laterOf(keyExpiry, fromIssuer ? _issuerExpiry : null);
    final tier = grant.tier;

    final revoked =
        issuerCode == KeygenValidationCode.suspended ||
        issuerCode == KeygenValidationCode.notFound;
    if (revoked) {
      _publish(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.invalid,
          grant: grant,
          lastCheckedAt: lastCheck,
          machineLabel: _machine.name,
        ),
      );
      return;
    }

    // No seat for this machine, by the issuer's own answer: either it refused
    // this machine one because every seat was taken, or the licence holds
    // more registered machines than it has seats. The second is a seat
    // reduction after the machines registered — under NO_OVERAGE nothing
    // else produces it — and it is enforced here rather than tolerated:
    // seats are priced per machine, and a licence that kept ten machines
    // running after its owner paid for one would be giving nine away. Which
    // machines keep theirs is the owner's decision in the issuer's portal;
    // until it is made, nobody holds one, and the counts say what to free.
    final overSeats = issuerCode == KeygenValidationCode.overage;
    if (fromIssuer && (_issuerSeatRefused || overSeats)) {
      _publish(
        CruxLicenseStatus(
          activation: CruxLicenseActivation.noSeat,
          grant: grant,
          seatsUsed: _issuerSeatsUsed,
          seatsTotal: _issuerSeats ?? grant.maxMachines,
          lastCheckedAt: lastCheck,
          machineLabel: _machine.name,
        ),
      );
      return;
    }

    final expired = expiry != null && now.isAfter(expiry);
    final CruxLicenseActivation activation;
    DateTime? graceEndsAt;
    if (expired) {
      graceEndsAt = _grace.endsAfter(expiry, tier);
      activation = now.isBefore(graceEndsAt)
          ? CruxLicenseActivation.grace
          : CruxLicenseActivation.expired;
    } else if (machineId == null &&
        issuerCode != null &&
        issuerCode != KeygenValidationCode.valid) {
      activation = CruxLicenseActivation.notActivatedOnThisMachine;
    } else {
      activation = CruxLicenseActivation.active;
    }

    _publish(
      CruxLicenseStatus(
        activation: activation,
        grant: expiry == keyExpiry ? grant : _withExpiry(grant, expiry),
        graceEndsAt: graceEndsAt,
        seatsUsed: fromIssuer ? _issuerSeatsUsed : null,
        seatsTotal: (fromIssuer ? _issuerSeats : null) ?? grant.maxMachines,
        lastCheckedAt: lastCheck,
        machineLabel: _machine.name,
      ),
    );
  }

  void _publish(CruxLicenseStatus status) {
    _status = status;
    if (!_statuses.isClosed) _statuses.add(status);
  }

  static DateTime? _laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

/// A copy of [grant] carrying [expiry] instead of its own.
///
/// Used when the issuer reports a later expiry than the key does — the key was
/// signed before the renewal, so its own date is stale by design.
LicenseGrant _withExpiry(LicenseGrant grant, DateTime? expiry) => LicenseGrant(
  issuerId: grant.issuerId,
  tier: grant.tier,
  products: grant.products,
  licenseId: grant.licenseId,
  policyId: grant.policyId,
  skuLookupKey: grant.skuLookupKey,
  expiry: expiry,
  maxMachines: grant.maxMachines,
  email: grant.email,
  resolvedFromEntitlements: grant.resolvedFromEntitlements,
);
