// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/license_fixtures.dart';

/// The airgap round trip, with the issuer unreachable at every step.
///
/// `exportOfflineRequest`, the licence-file parser and `importOfflineToken`
/// shipped separately, and nothing exercised the three of them together against
/// an issuer that never answers. The path was correct by reading; this file is
/// the part that makes it stay correct.
///
/// The property that matters, and the one nothing asserted before:
/// `activate()` does **not** check for [KeygenMachineOutcome.offline]. It falls
/// through, no machine id is ever stored, `_refreshFromIssuer` fails quietly,
/// and the status resolves from the stored credential alone. That is what
/// licenses a machine which can never reach Keygen — and it is a fall-through,
/// so a well-meaning future `if (result.outcome == offline) return failed(...)`
/// would break it silently and look like a fix.
///
/// On fixtures: these are minted from a fixed seed, not issued by the live
/// Keygen account. A portal-issued file cannot be committed — redacting any
/// byte of the payload invalidates the Ed25519 signature taken over it, so
/// "redacted but still signature-valid" is not a thing that exists. What is
/// reproduced exactly is the *wire format*: the `-----BEGIN LICENSE FILE-----`
/// envelope, the `alg`/`enc`/`sig` certificate, the `license/` signing prefix
/// and the unpadded base64url alphabet.
void main() {
  late TestIssuerKeys keys;
  late CruxLicenseValidator validator;
  final duringTerm = DateTime.utc(2026, 9);

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(7);
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[
        KeygenLicenseIssuer(
          accountId: testAccountId,
          verifyKey: keys.verifyKey,
          policies: testPolicies,
        ),
      ],
    );
  });

  /// Counts every HTTP attempt, then fails it. An airgapped machine does not
  /// get a polite 503; the socket never opens.
  late int attempts;
  setUp(() => attempts = 0);

  CruxLicenseController controllerOver(_Store store) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      client: _CountingUnreachable(() => attempts++),
    ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/pricing'),
    now: () => duringTerm,
  );

  group('the whole round trip, with no reachable issuer', () {
    test('export, import, licensed — and nothing was reached', () async {
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);
      await controller.start();

      // Leg one: the machine describes itself.
      final exported = await controller.exportOfflineRequest();
      final request =
          json.decode((exported as LicenseActionSucceeded).payload!)
              as Map<String, Object?>;
      expect(request['kind'], 'crux.offline-activation-request/v1');
      expect(request['fingerprint'], 'fingerprint-1');

      // Leg two: support turns that into a licence file. Enterprise, the whole
      // suite, a full year — the shape a permanent air gap actually gets. Like
      // every file Keygen issues, it embeds the licence key.
      final file = await keys.mintFile(
        filePayload(
          key: await keys.mintKey(
            keyPayload(policy: testSuiteEnterprisePolicyId),
          ),
          policy: testSuiteEnterprisePolicyId,
          expiry: '2027-06-01T00:00:00.000Z',
          maxMachines: 40,
          entitlements: const <String>[
            'TIER_ENTERPRISE',
            'WAVECRUX',
            'NETCRUX',
            'LINTCRUX',
            'SIMCRUX',
          ],
        ),
      );

      // Leg three: import.
      final imported = await controller.importOfflineToken(file);
      expect(imported.isOk, isTrue);

      final status = controller.status;
      expect(
        status.activation,
        CruxLicenseActivation.active,
        reason:
            'THE assertion. activate() ignores KeygenMachineOutcome.offline '
            'and falls through; if that ever becomes an early return, an '
            'airgapped machine stops being licensed and this is the only '
            'thing that would notice.',
      );
      expect(status.tier, LicenseTier.enterprise);
      expect(status.grant!.products, hasLength(4));
      expect(status.grant!.expiry, DateTime.utc(2027, 6));
      expect(status.grant!.resolvedFromEntitlements, isTrue);

      expect(
        attempts,
        greaterThan(0),
        reason: 'the app must have tried; being offline is not being passive',
      );
      expect(
        store.machineId,
        isNull,
        reason: 'no activation ever succeeded, so there is no seat to release',
      );
      expect(
        store.lastCheck,
        isNull,
        reason: 'never confirmed by the issuer, and that is a fine state',
      );
    });

    test(
      'an unconfirmed machine is active, not notActivatedOnThisMachine',
      () async {
        // The contrast that makes the fall-through legible. With no issuer
        // code at all the machine is active; the "not activated here" state
        // exists for a machine that DID reach the issuer and was told no.
        final store = _Store();
        final controller = controllerOver(store);
        addTearDown(controller.dispose);

        await controller.activate(await keys.mintFile(filePayload()));

        expect(
          controller.status.activation,
          isNot(CruxLicenseActivation.notActivatedOnThisMachine),
        );
        expect(controller.status.activation, CruxLicenseActivation.active);
      },
    );

    test('the credential is stored before the network is touched', () async {
      // A customer on a flaky connection must not have to paste 700
      // characters twice, and an airgapped one must end up licensed at all.
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.activate(await keys.mintKey(keyPayload()));

      expect(store.credential, isNotNull);
      expect(controller.status.tier, LicenseTier.pro);
    });
  });

  group('the reimage case — Pro, not only Enterprise', () {
    // A Pro customer whose airgapped workstation is rebuilt still needs the
    // export. What Enterprise buys is SELF-SERVE issuance,
    // not the code path. A test that only covered Enterprise would let a later
    // tier check brick a paying seat and nobody would see it.
    test('a Pro-licensed machine can export a fresh request', () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(store);
      addTearDown(controller.dispose);
      await controller.start();
      expect(controller.status.tier, LicenseTier.pro);

      final result = await controller.exportOfflineRequest();
      expect(result.isOk, isTrue);
      expect(controller.supportsOfflineActivation, isTrue);

      final payload = (result as LicenseActionSucceeded).payload!;
      expect(payload, contains('crux.offline-activation-request/v1'));
      expect(
        payload,
        isNot(contains(store.credential)),
        reason: 'it travels on a USB stick and may be read down a phone',
      );
      expect(payload, isNot(contains('key/')));
      expect(payload, isNot(contains('BEGIN LICENSE FILE')));
    });

    test('a support-issued licence file relicenses a Pro seat', () async {
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken(
        await keys.mintFile(filePayload()),
      );

      expect(result.isOk, isTrue);
      expect(controller.status.tier, LicenseTier.pro);
      expect(controller.status.activation, CruxLicenseActivation.active);
    });

    test('licence files resolve at every tier — there is no gate', () async {
      // A deliberate decision, asserted so it cannot be "tidied" into a tier
      // check.
      // What is Enterprise is self-serve ISSUANCE, which is a Keygen-portal
      // and commercial matter, not code. A licence file must keep parsing and
      // resolving everywhere: it is also how an old build honours a SKU it
      // predates.
      for (final (tierCode, expected) in const <(String, LicenseTier)>[
        ('TIER_PRO', LicenseTier.pro),
        ('TIER_EDU', LicenseTier.edu),
        ('TIER_ENTERPRISE', LicenseTier.enterprise),
      ]) {
        final controller = controllerOver(_Store());
        addTearDown(controller.dispose);

        final result = await controller.importOfflineToken(
          await keys.mintFile(
            filePayload(entitlements: <String>[tierCode, 'WAVECRUX']),
          ),
        );

        expect(result.isOk, isTrue, reason: '$tierCode must import');
        expect(controller.status.tier, expected);
      }
    });
  });

  group('a machine file is bound to the machine that asked', () {
    // The request document carries this install's fingerprint; support (or
    // an Enterprise administrator) registers a machine with that fingerprint
    // and checks a machine file out against it. The file then resolves here
    // and nowhere else — which is what makes it safe to issue for a machine
    // that will never reach the issuer.
    test(
      'the round trip, with the file checked out for this machine',
      () async {
        final store = _Store();
        final controller = controllerOver(store);
        addTearDown(controller.dispose);
        await controller.start();

        final exported = await controller.exportOfflineRequest();
        final request =
            json.decode((exported as LicenseActionSucceeded).payload!)
                as Map<String, Object?>;

        final file = await keys.mintMachineFile(
          machineFilePayload(
            fingerprint: request['fingerprint']! as String,
            key: await keys.mintKey(
              keyPayload(policy: testSuiteEnterprisePolicyId),
            ),
            policy: testSuiteEnterprisePolicyId,
            expiry: '2027-06-01T00:00:00.000Z',
            maxMachines: 40,
            entitlements: const <String>[
              'TIER_ENTERPRISE',
              'WAVECRUX',
              'NETCRUX',
              'LINTCRUX',
              'SIMCRUX',
            ],
          ),
        );

        final imported = await controller.importOfflineToken(file);

        expect(imported.isOk, isTrue);
        expect(controller.status.activation, CruxLicenseActivation.active);
        expect(controller.status.tier, LicenseTier.enterprise);
        expect(controller.status.grant!.products, hasLength(4));
        expect(attempts, greaterThan(0), reason: 'the app still tries');
      },
    );

    test('the same file on any other machine licenses nothing', () async {
      // THE assertion for the air gap. One file, forty workstations, was the
      // exploit: a licence file names no machine, so a copy of it activated
      // everywhere for the whole term. A machine file names one.
      final file = await keys.mintMachineFile(
        machineFilePayload(
          policy: testSuiteEnterprisePolicyId,
          entitlements: const <String>['TIER_ENTERPRISE', 'WAVECRUX'],
        ),
      );
      final elsewhere = _Store(fingerprint: 'fingerprint-2');
      final controller = controllerOver(elsewhere);
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken(file);

      expect(result.isOk, isFalse);
      expect(
        (result as LicenseActionFailed).rejection,
        LicenseRejection.wrongMachine,
      );
      expect(controller.status.tier, LicenseTier.openCore);
      expect(
        elsewhere.credential,
        isNull,
        reason: 'a refused import must not half-license anyone',
      );
    });

    test('a copied store does not carry the licence either', () async {
      // Copying the whole credential store to a second machine copies the
      // fingerprint with it, and the file then resolves there too. That is
      // not a hole in the binding: two installs with one fingerprint are one
      // seat to the issuer, and the copy is a reimage, not a second machine.
      // What the binding refuses is the file alone, which is what travels.
      final file = await keys.mintMachineFile(machineFilePayload());
      final rebuilt = _Store(fingerprint: 'fingerprint-3')..credential = file;
      final controller = controllerOver(rebuilt);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.invalid);
      expect(controller.status.rejection, LicenseRejection.wrongMachine);
      expect(controller.status.tier, LicenseTier.openCore);
    });

    test('machine files resolve at every tier — there is no gate', () async {
      for (final (tierCode, expected) in const <(String, LicenseTier)>[
        ('TIER_PRO', LicenseTier.pro),
        ('TIER_EDU', LicenseTier.edu),
        ('TIER_ENTERPRISE', LicenseTier.enterprise),
      ]) {
        final controller = controllerOver(_Store());
        addTearDown(controller.dispose);

        final result = await controller.importOfflineToken(
          await keys.mintMachineFile(
            machineFilePayload(entitlements: <String>[tierCode, 'WAVECRUX']),
          ),
        );

        expect(result.isOk, isTrue, reason: '$tierCode must import');
        expect(controller.status.tier, expected);
      }
    });

    test('a licence file still names no machine', () async {
      // The other half of the every-tier promise, stated so nobody reads the
      // binding above as applying to licence files. A licence file imports on
      // any install; its seat is counted when the machine can reach the
      // issuer, and until then it is a bearer credential. The air-gap
      // artefact is the machine file, and issuance is where that is decided.
      final file = await keys.mintFile(filePayload());
      final controller = controllerOver(_Store(fingerprint: 'fingerprint-9'));
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken(file);

      expect(result.isOk, isTrue);
      expect(controller.status.tier, LicenseTier.pro);
    });
  });

  group('the scheme gotcha', () {
    test('an aes-256-gcm file is refused by name, not generically', () async {
      // The most likely support ticket in the flow: the Keygen portal offers
      // both schemes and one of them cannot work by construction, because it
      // uses the licence key itself as the decryption secret.
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken(
        await keys.mintEncryptedFile(filePayload()),
      );

      expect(
        (result as LicenseActionFailed).rejection,
        LicenseRejection.unsupportedAlgorithm,
      );
      expect(result.detail, contains('aes-256-gcm+ed25519'));
      expect(
        controller.status.tier,
        LicenseTier.openCore,
        reason: 'a refused import must not half-license anyone',
      );
    });

    test('the message names both schemes so support can act on it', () {
      // A user who reads this has to be able to go back to whoever issued the
      // file and ask for the right thing. "It is encrypted" does not tell them
      // what to ask for.
      final message =
          const CruxLicensePanelStringsEn().licenseErrorEncryptedFile;
      expect(message, contains('aes-256-gcm+ed25519'));
      expect(message, contains('base64+ed25519'));
    });
  });
}

class _Store implements LicenseStore {
  _Store({this.credential, this.fingerprint = 'fingerprint-1'});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  final String fingerprint;

  @override
  Future<void> clear() async {
    credential = null;
    machineId = null;
    lastCheck = null;
    issuerSnapshot = null;
  }

  @override
  Future<String?> readCredential() async => credential;

  @override
  Future<DateTime?> readLastCheck() async => lastCheck;

  @override
  Future<String?> readMachineId() async => machineId;

  @override
  Future<String> readOrCreateFingerprint() async => fingerprint;

  @override
  Future<void> writeCredential(String credential) async =>
      this.credential = credential;

  @override
  Future<void> writeLastCheck(DateTime at) async => lastCheck = at;

  String? issuerSnapshot;

  @override
  Future<String?> readIssuerSnapshot() async => issuerSnapshot;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async =>
      issuerSnapshot = snapshot;

  @override
  Future<void> writeMachineId(String? machineId) async =>
      this.machineId = machineId;
}

class _CountingUnreachable extends http.BaseClient {
  _CountingUnreachable(this._onAttempt);

  final void Function() _onAttempt;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _onAttempt();
    throw const _Unreachable();
  }
}

class _Unreachable implements Exception {
  const _Unreachable();
}
