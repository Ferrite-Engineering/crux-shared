// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:crux_license/src/install_fingerprint.dart'
    show mintInstallFingerprint;
import 'package:crux_license/src/keygen_issuer.dart';
import 'package:crux_license/src/license_actions.dart';
import 'package:crux_signing/crux_signing.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Keygen's answer to "is this licence still good, on this machine".
enum KeygenValidationCode {
  /// Valid, and this machine is registered.
  valid,

  /// Valid, but no machine is activated against it yet.
  noMachine,

  /// Valid, but *this* machine is not among the activated ones.
  fingerprintScopeMismatch,

  /// Past its expiry.
  expired,

  /// Suspended, banned, revoked — the issuer has withdrawn it.
  suspended,

  /// The issuer has never heard of this key.
  notFound,

  /// The licence holds more registered machines than it has seats. Under
  /// `NO_OVERAGE` a registration past the last seat is refused outright, so
  /// this arises when the seat count was reduced after the machines
  /// registered — a licence that paid for fewer seats than it is using. Every
  /// machine on it runs Open Core until the owner frees seats in the issuer's
  /// portal; seats are priced per machine, and which machines keep theirs is
  /// the owner's decision, not the client's.
  overage,

  /// A code this build does not recognise. Treated as "do not change local
  /// state": Keygen adds codes, and a build that downgraded a customer on an
  /// unknown one would be a build that downgrades customers on an upgrade.
  unknown,
}

/// A response the issuer signed, kept verbatim so the signature can be
/// checked again later — on a relaunch, from a store the user can edit.
///
/// Keygen signs every response with the account's Ed25519 key, the same key
/// that signs the licences themselves. The signature covers the request
/// target, the host, the `Date` header and a SHA-256 digest of the raw body,
/// in that order, newline-separated, and travels in a `Keygen-Signature`
/// header. Keeping those five things is enough to re-verify the answer with
/// nothing but the public key that ships in every build.
///
/// This is what makes the persisted issuer answer trustworthy. The answer
/// lives in the credential store beside the key, and whatever is written there
/// is only as good as its signature: a renewal extends a licence past the
/// date in the key, so an answer nobody signed must not be able to.
@immutable
class KeygenAttestation {
  /// Create an attestation from its signed parts.
  const KeygenAttestation({
    required this.requestTarget,
    required this.host,
    required this.date,
    required this.body,
    required this.signature,
  });

  /// Read an attestation off a response, or `null` when the response carries
  /// no Ed25519 `Keygen-Signature`. Nothing is verified here.
  static KeygenAttestation? fromResponse({
    required String method,
    required Uri url,
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) {
    final header = _header(headers, 'keygen-signature');
    final date = _header(headers, 'date');
    if (header == null || date == null) return null;
    if (!RegExp('algorithm="ed25519"').hasMatch(header)) return null;
    final signature = RegExp('signature="([^"]*)"').firstMatch(header);
    if (signature == null) return null;
    final String body;
    try {
      body = utf8.decode(bodyBytes);
    } on FormatException {
      return null;
    }
    return KeygenAttestation(
      requestTarget:
          '${method.toLowerCase()} ${url.path}'
          '${url.hasQuery ? '?${url.query}' : ''}',
      host: url.host,
      date: date,
      body: body,
      signature: signature.group(1)!,
    );
  }

  /// Read an attestation back from [toJson], or `null` for anything else.
  /// Total: the store is the user's, and its contents are not trusted to be
  /// well-formed.
  static KeygenAttestation? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final target = json['requestTarget'];
    final host = json['host'];
    final date = json['date'];
    final body = json['body'];
    final signature = json['signature'];
    if (target is! String ||
        host is! String ||
        date is! String ||
        body is! String ||
        signature is! String) {
      return null;
    }
    return KeygenAttestation(
      requestTarget: target,
      host: host,
      date: date,
      body: body,
      signature: signature,
    );
  }

  /// Lower-cased method and path (with query), as the signature covers it.
  final String requestTarget;

  /// The host the answer came from.
  final String host;

  /// The response's `Date` header, verbatim.
  final String date;

  /// The raw response body. The digest is recomputed from this on every
  /// verification rather than taken from a stored header, so the body is
  /// bound by the signature and not merely stored next to it.
  final String body;

  /// The base64 Ed25519 signature from the `Keygen-Signature` header.
  final String signature;

  /// `sha-256=<base64>` over the body bytes, as the signing string carries it.
  String get digest =>
      'sha-256=${base64.encode(sha256.convert(utf8.encode(body)).bytes)}';

  /// The string the issuer signed.
  String get signingString =>
      '(request-target): $requestTarget\n'
      'host: $host\n'
      'date: $date\n'
      'digest: $digest';

  /// Whether [verifyKey] signed this answer.
  bool verify(List<int> verifyKey) {
    final List<int> raw;
    try {
      raw = base64.decode(base64.normalize(signature));
    } on FormatException {
      return false;
    }
    return ed25519Verify(
      message: utf8.encode(signingString),
      signature: raw,
      publicKey: verifyKey,
    );
  }

  /// The body as a JSON object, or `null` when it is not one.
  Map<String, Object?>? get decodedBody {
    try {
      return _object(json.decode(body));
    } on FormatException {
      return null;
    }
  }

  /// The parts, for the store. [fromJson] reads them back.
  Map<String, Object?> toJson() => <String, Object?>{
    'requestTarget': requestTarget,
    'host': host,
    'date': date,
    'body': body,
    'signature': signature,
  };

  static String? _header(Map<String, String> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }
}

/// What a validate-key round trip told us.
@immutable
class KeygenValidation {
  /// Create a validation result.
  const KeygenValidation({
    required this.valid,
    required this.code,
    this.licenseId,
    this.expiry,
    this.maxMachines,
    this.machineCount,
    this.scopeFingerprint,
    this.attestation,
    this.detail = '',
  });

  /// Read the issuer's answer out of a validate-key response [body].
  ///
  /// Tolerates any shape: a field that is missing or of another type reads as
  /// unknown rather than throwing, because a validator that throws on a
  /// payload the issuer extended is a validator that locks out a paying
  /// customer.
  factory KeygenValidation.fromBody(
    Map<String, Object?> body, {
    KeygenAttestation? attestation,
  }) {
    final meta = _object(body['meta']);
    final data = _object(body['data']);
    final attributes = _object(data?['attributes']);
    // The count is a relationship's meta, not a licence attribute; the
    // attribute is read first in case the issuer ever surfaces it there.
    final machines = _object(_object(data?['relationships'])?['machines']);
    return KeygenValidation(
      valid: meta?['valid'] == true,
      code: _codeFrom(_string(meta?['code'])),
      licenseId: _string(data?['id']),
      expiry: _time(attributes?['expiry']),
      maxMachines: _int(attributes?['maxMachines']),
      machineCount:
          _int(attributes?['machinesCount']) ??
          _int(_object(machines?['meta'])?['count']),
      scopeFingerprint: _string(_object(meta?['scope'])?['fingerprint']),
      attestation: attestation,
      detail: _string(meta?['detail']) ?? '',
    );
  }

  /// The issuer could not be reached, or what came back was not its answer.
  static const KeygenValidation unreached = KeygenValidation(
    valid: false,
    code: KeygenValidationCode.unknown,
    detail: 'offline',
  );

  /// Whether Keygen considers the licence usable right now.
  final bool valid;

  /// Why, in machine-readable form.
  final KeygenValidationCode code;

  /// Issuer-side licence id.
  final String? licenseId;

  /// Expiry as the issuer currently records it — **more current than the
  /// key's own payload**, because a renewal extends the licence without
  /// reissuing the key.
  final DateTime? expiry;

  /// Seats the licence permits, as the issuer currently records it. The
  /// bridge writes the purchased seat count here, so it can differ from the
  /// policy default.
  final int? maxMachines;

  /// Seats currently in use.
  final int? machineCount;

  /// The machine fingerprint the question was scoped to, echoed back inside
  /// the signed body — which is what binds a stored answer to the install
  /// that asked.
  final String? scopeFingerprint;

  /// The issuer's signature over this answer, verified, or `null` when the
  /// answer did not come with one that holds.
  final KeygenAttestation? attestation;

  /// Whether this is the issuer's own answer: it arrived signed, and the
  /// signature verified against the account key. An answer that is not
  /// attested is treated exactly like not having reached the issuer at all,
  /// because that is the only honest reading of a body anyone on the path
  /// could have written.
  bool get attested => attestation != null;

  /// Developer-facing detail for logs.
  final String detail;

  @override
  String toString() =>
      'KeygenValidation(${code.name}, valid: $valid, expiry: $expiry)';
}

/// Outcome of a machine activation or deactivation.
enum KeygenMachineOutcome {
  /// It worked.
  ok,

  /// This machine was already registered — idempotent, and success from the
  /// user's point of view.
  alreadyActivated,

  /// Every seat is in use. `overageStrategy: NO_OVERAGE` makes this a
  /// designed refusal rather than an error.
  noSeatAvailable,

  /// The licence cannot hold a seat at all any more: it is suspended, or it
  /// no longer exists.
  ///
  /// Measured against the live account: a suspended licence answers a machine
  /// deletion with `403 LICENSE_SUSPENDED`, and a deleted one with
  /// `401 LICENSE_INVALID`, because the key it authenticated with is gone. An
  /// **expired** licence is deliberately not in this set — it releases its
  /// machines normally, with a `204`.
  ///
  /// This is a refusal the caller may act on by clearing local state, which
  /// [refused] is not: every cancellation ends in a suspended licence, and
  /// without this the customer can never get their own dead key out of the
  /// app.
  licenseInactive,

  /// The issuer refused for a reason of its own.
  refused,

  /// The issuer could not be reached.
  offline,
}

/// The result of a machine operation, with the issuer's machine id when it
/// produced one.
@immutable
class KeygenMachineResult {
  /// Create a machine result.
  const KeygenMachineResult(this.outcome, {this.machineId, this.detail = ''});

  /// What happened.
  final KeygenMachineOutcome outcome;

  /// Issuer-side machine id, needed to deactivate later.
  final String? machineId;

  /// Developer-facing detail for logs.
  final String detail;

  /// Whether the caller should treat this as a success.
  bool get isOk =>
      outcome == KeygenMachineOutcome.ok ||
      outcome == KeygenMachineOutcome.alreadyActivated;

  @override
  String toString() => 'KeygenMachineResult(${outcome.name})';
}

/// The Keygen calls a licensed app ever makes: validate a key, register this
/// machine, release it, and look it up by fingerprint.
///
/// ### No token ships in any build
///
/// The policies use `authenticationStrategy: LICENSE`, so the customer's own
/// key is the
/// credential: `Authorization: License <key>`. There is no product token, no
/// admin token, and nothing here to leak. That is a deliberate property of the
/// catalog, and it is why this client can live in the open half of the repo.
///
/// ### Online is a refresh, never a precondition
///
/// A validated key works with no network at all — that is what the signature
/// on it is for. Every method here returns an "offline" outcome rather than
/// throwing, and the caller's contract is to leave local state alone when it
/// sees one. The suite sells airgapped use; an app that needed this class
/// to succeed before it would run would be selling something else.
///
/// ### A validate answer is only an answer if the issuer signed it
///
/// The issuer signs every response with the account key. [validateKey]
/// requires that signature and reports anything without one as not reached:
/// the answer to "is this licence still good" is the one thing on the wire
/// that can extend a licence past the date in the key, and it is persisted,
/// so it has to be something the machine's own user could not have written.
/// Machine registration and release are not verified — a forged registration
/// can only refuse a seat, and a forged release only clears local state.
class KeygenLicenseClient {
  /// Create a client.
  ///
  /// [accountId] and [verifyKey] default to the suite's account and its
  /// public key. Inject [client] in tests; production defaults to a fresh
  /// [http.Client].
  KeygenLicenseClient({
    String? accountId,
    List<int>? verifyKey,
    http.Client? client,
    Uri? baseUri,
    Duration? timeout,
  }) : _accountId = accountId ?? kKeygenAccountId,
       _verifyKey = verifyKey ?? decodeHexKey(kKeygenVerifyKeyHex),
       _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://api.keygen.sh/v1/accounts'),
       _timeout = timeout ?? const Duration(seconds: 15);

  final String _accountId;
  final List<int> _verifyKey;
  final http.Client _client;
  final Uri _baseUri;
  final Duration _timeout;

  static const String _validatePath = 'licenses/actions/validate-key';

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/vnd.api+json',
    'Content-Type': 'application/vnd.api+json',
  };

  Uri _uri(String path) => Uri.parse('$_baseUri/$_accountId/$path');

  /// Ask the issuer whether [key] is still good, scoped to [fingerprint].
  ///
  /// Needs no authorization — validate-key is the one open endpoint, because
  /// possession of the key is the claim being checked.
  ///
  /// The answer is [KeygenValidation.unreached] unless it came back signed by
  /// the account key; see [attestsValidation].
  Future<KeygenValidation> validateKey(
    String key, {
    String? fingerprint,
  }) async {
    final body = <String, Object?>{
      'meta': <String, Object?>{
        'key': key,
        if (fingerprint != null)
          'scope': <String, Object?>{'fingerprint': fingerprint},
      },
    };
    final reply = await _send('POST', _validatePath, body: body);
    if (reply == null) return KeygenValidation.unreached;
    final attestation = reply.attestation;
    if (attestation == null || !attestsValidation(attestation)) {
      return KeygenValidation.unreached;
    }
    return KeygenValidation.fromBody(reply.body, attestation: attestation);
  }

  /// Whether [attestation] is a validate-key answer from this client's
  /// issuer: signed by the account key, from the issuer's host, and to the
  /// validate-key target — not some other signed response replayed as one.
  bool attestsValidation(KeygenAttestation attestation) =>
      attestation.host == _baseUri.host &&
      attestation.requestTarget == 'post ${_uri(_validatePath).path}' &&
      attestation.verify(_verifyKey);

  /// Register this machine against the licence.
  Future<KeygenMachineResult> activateMachine({
    required String key,
    required String licenseId,
    required String fingerprint,
    required String name,
    required String platform,
  }) async {
    final reply = await _send(
      'POST',
      'machines',
      key: key,
      body: <String, Object?>{
        'data': <String, Object?>{
          'type': 'machines',
          'attributes': <String, Object?>{
            'fingerprint': fingerprint,
            'name': name,
            'platform': platform,
          },
          'relationships': <String, Object?>{
            'license': <String, Object?>{
              'data': <String, Object?>{'type': 'licenses', 'id': licenseId},
            },
          },
        },
      },
    );
    if (reply == null) {
      return const KeygenMachineResult(KeygenMachineOutcome.offline);
    }
    final response = reply.body;
    final errors = response['errors'];
    if (errors is List && errors.isNotEmpty) {
      return KeygenMachineResult(
        _machineErrorOutcome(errors),
        detail: _errorDetail(errors),
      );
    }
    return KeygenMachineResult(
      KeygenMachineOutcome.ok,
      machineId: _string(_object(response['data'])?['id']),
    );
  }

  /// Release [machine]'s seat.
  ///
  /// [machine] is the machine's UUID or its URL-safe fingerprint; Keygen
  /// resolves either on its machine endpoints. The controller passes the
  /// fingerprint, because the fingerprint is shared by every product on the
  /// machine and the id is known only to the product that registered it —
  /// "deactivate this machine" has to work from whichever product the user
  /// happens to be in. Fingerprints from [mintInstallFingerprint] are
  /// base64url, so they need no escaping in the path.
  ///
  /// [machineId] is the parameter's former name and means the same thing;
  /// exactly one of the two must be given.
  Future<KeygenMachineResult> deactivateMachine({
    required String key,
    String? machine,
    // Package versions here are informational and the products pin a commit,
    // so "0.13.0 is a breaking version" is not a reason to drop the alias:
    // the deprecation policy keeps it until every product has migrated.
    // ignore: remove_deprecations_in_breaking_versions
    @Deprecated(
      'Pass `machine` instead; it takes the id or the fingerprint. '
      'Removed after 0.14.0.',
    )
    String? machineId,
  }) async {
    final target = machine ?? machineId;
    if (target == null || (machine != null && machineId != null)) {
      throw ArgumentError(
        'deactivateMachine: give `machine` (the id or the fingerprint), '
        'and nothing else',
      );
    }
    final reply = await _send('DELETE', 'machines/$target', key: key);
    if (reply == null) {
      return const KeygenMachineResult(KeygenMachineOutcome.offline);
    }
    final errors = reply.body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final codes = _errorCodes(errors);
      // A machine that is already gone is the state the caller wanted.
      final detail = _errorDetail(errors).toUpperCase();
      if (codes.contains('NOT_FOUND') || detail.contains('NOT FOUND')) {
        return const KeygenMachineResult(KeygenMachineOutcome.ok);
      }
      // Match on the issuer's code, not on its prose: the prose is English
      // shown to a human, the code is the contract.
      if (codes.contains('LICENSE_SUSPENDED') ||
          codes.contains('LICENSE_INVALID') ||
          codes.contains('LICENSE_NOT_FOUND')) {
        return KeygenMachineResult(
          KeygenMachineOutcome.licenseInactive,
          detail: _errorDetail(errors),
        );
      }
      return KeygenMachineResult(
        KeygenMachineOutcome.refused,
        detail: _errorDetail(errors),
      );
    }
    return const KeygenMachineResult(KeygenMachineOutcome.ok);
  }

  /// The id of the machine registered under [fingerprint] on the licence
  /// [key] belongs to, or `null` when there is none — or none could be
  /// asked about.
  ///
  /// Used only to remember the id after a registration that answered
  /// "already activated" without one, which is what the issuer says when a
  /// sibling product on this machine registered first. The id is a
  /// convenience — release works by fingerprint — so not found, refused and
  /// unreachable are all `null`; nothing downstream needs to tell them apart.
  Future<String?> findMachine({
    required String key,
    required String fingerprint,
  }) async {
    final reply = await _send('GET', 'machines/$fingerprint', key: key);
    if (reply == null) return null;
    final errors = reply.body['errors'];
    if (errors is List && errors.isNotEmpty) return null;
    // Only a machine, and only this one. The id is what a later release is
    // made with, so an answer that is some other resource — a proxy's page,
    // a licence object from a confused endpoint — must read as "not found"
    // rather than become the machine this product believes it holds.
    final data = _object(reply.body['data']);
    if (data == null || data['type'] != 'machines') return null;
    final found = _string(_object(data['attributes'])?['fingerprint']);
    if (found != null && found != fingerprint) return null;
    return _string(data['id']);
  }

  /// Ask the commerce backend to start the educational round trip for
  /// [email].
  ///
  /// Not a Keygen call. It is on this client because it is the same transport
  /// and the same offline discipline, and because the app has exactly one
  /// place it talks to a server. **Keygen sends no email of any kind**, so the
  /// licence creation, the pending-token store, its expiry and the mail itself
  /// all belong to the commerce backend — the app's part is this one call and
  /// the sentence "check your email".
  Future<CruxLicenseActionResult> requestEducationalLicense({
    required Uri endpoint,
    required String email,
  }) async {
    final request = http.Request('POST', endpoint)
      ..headers.addAll(const <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      })
      ..body = json.encode(<String, Object?>{'email': email});
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? const <String, Object?>{}
          : json.decode(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // `review` means the backend created nothing and mailed a person. The
        // app must say so: the automatic path's "follow the link we sent" is
        // a lie here, and a user who believes it waits instead of waiting for
        // an answer they will actually get.
        return LicenseActionSucceeded(
          underReview: _object(decoded)?['review'] == true,
        );
      }
      final error = _string(_object(decoded)?['error']) ?? '';
      return switch (response.statusCode) {
        400 || 422 => LicenseActionFailed(
          CruxLicenseActionFailure.invalidEmail,
          detail: error,
        ),
        409 => LicenseActionFailed(
          CruxLicenseActionFailure.alreadyRequested,
          detail: error,
        ),
        _ => LicenseActionFailed(
          CruxLicenseActionFailure.unknown,
          detail: 'HTTP ${response.statusCode} $error',
        ),
      };
    } on Object {
      return const LicenseActionFailed(CruxLicenseActionFailure.offline);
    }
  }

  /// Release the client's underlying connections.
  void close() => _client.close();

  /// Returns the decoded body with whatever signature came over it, or `null`
  /// for every transport-level failure.
  ///
  /// `null` means "we did not reach the issuer", which is categorically
  /// different from "the issuer said no" and is the only case in which the
  /// caller must leave local state untouched.
  Future<_IssuerReply?> _send(
    String method,
    String path, {
    String? key,
    Map<String, Object?>? body,
  }) async {
    if (key != null && (key.contains('\n') || key.contains('\r'))) {
      // Not a reachability failure: this request can never be built, because
      // an HTTP header refuses line breaks. Answered as a refusal so no caller
      // reads it as "offline", which is what let a licence file silently skip
      // registering its seat and refuse to release one.
      return const _IssuerReply(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{
            'title': 'Unsendable credential',
            'detail':
                'the credential cannot be sent as an Authorization header',
          },
        ],
      });
    }
    final request = http.Request(method, _uri(path))
      ..headers.addAll(<String, String>{
        ..._headers,
        if (key != null) 'Authorization': 'License $key',
      });
    if (body != null) request.body = json.encode(body);
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final attestation = KeygenAttestation.fromResponse(
        method: method,
        url: request.url,
        headers: response.headers,
        bodyBytes: response.bodyBytes,
      );
      if (response.statusCode == 204 || response.body.isEmpty) {
        return _IssuerReply(const <String, Object?>{}, attestation);
      }
      final decoded = json.decode(response.body);
      return _IssuerReply(
        decoded is Map<String, Object?> ? decoded : const <String, Object?>{},
        attestation,
      );
    } on Object {
      // Every reachability failure looks the same to the caller by design:
      // socket errors, DNS failures, timeouts, proxies and captive portals
      // all mean "keep running on what we already verified".
      return null;
    }
  }

  static KeygenMachineOutcome _machineErrorOutcome(List<Object?> errors) {
    final detail = _errorDetail(errors).toUpperCase();
    if (detail.contains('ALREADY') || detail.contains('TAKEN')) {
      return KeygenMachineOutcome.alreadyActivated;
    }
    // Keygen reports a full licence as "machine count has exceeded maximum
    // allowed by current policy (3)". Matched on its parts rather than the
    // whole sentence, which carries the seat count and is not a fixed string.
    if (detail.contains('MACHINE LIMIT') ||
        detail.contains('TOO MANY') ||
        detail.contains('OVERAGE') ||
        (detail.contains('MACHINE COUNT') && detail.contains('EXCEEDED'))) {
      return KeygenMachineOutcome.noSeatAvailable;
    }
    return KeygenMachineOutcome.refused;
  }

  /// The issuer's machine-readable error codes, which are stable where its
  /// `title` and `detail` are human prose.
  static List<String> _errorCodes(List<Object?> errors) => errors
      .map(_object)
      .map((e) => _string(e?['code']) ?? '')
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static String _errorDetail(List<Object?> errors) => errors
      .map(_object)
      .map((e) => _string(e?['detail']) ?? _string(e?['title']) ?? '')
      .where((s) => s.isNotEmpty)
      .join('; ');
}

KeygenValidationCode _codeFrom(String? code) => switch (code) {
  'VALID' => KeygenValidationCode.valid,
  'NO_MACHINE' || 'NO_MACHINES' => KeygenValidationCode.noMachine,
  'FINGERPRINT_SCOPE_MISMATCH' => KeygenValidationCode.fingerprintScopeMismatch,
  'EXPIRED' => KeygenValidationCode.expired,
  'SUSPENDED' || 'BANNED' => KeygenValidationCode.suspended,
  'NOT_FOUND' => KeygenValidationCode.notFound,
  'TOO_MANY_MACHINES' || 'OVERAGE' => KeygenValidationCode.overage,
  _ => KeygenValidationCode.unknown,
};

/// A decoded response and the signature that came over it, if any.
@immutable
class _IssuerReply {
  const _IssuerReply(this.body, [this.attestation]);

  final Map<String, Object?> body;
  final KeygenAttestation? attestation;
}

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// [value] as an int, or `null` when it is not a finite number: `1e400`
/// decodes to `double.infinity`, and `Infinity.toInt()` throws an Error.
int? _int(Object? value) =>
    value is num && value.isFinite ? value.toInt() : null;

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
