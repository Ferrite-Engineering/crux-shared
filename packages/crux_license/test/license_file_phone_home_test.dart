// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// A licence **file** is never posted to `validate-key`; the key it embeds is.
///
/// `airgap_round_trip_test.dart` covers the machine that can never reach the
/// issuer, and it passes because the socket never opens. This file covers the
/// case that sits one step to the side of it: a machine holding a file that
/// **can** reach Keygen. That is not a hypothetical customer — offline
/// activation is offered at every tier, so the person it describes is
/// somebody whose machine has intermittent or later connectivity, not
/// somebody permanently air gapped.
///
/// ### The two things that went wrong, in turn
///
/// First, `_refreshFromIssuer` posted whatever was stored as `meta.key`. A
/// licence file is not a key, so the live account answered — measured, not
/// assumed:
///
/// ```text
/// POST /v1/accounts/<acc>/licenses/actions/validate-key
/// {"meta":{"key":"-----BEGIN LICENSE FILE----- …"}}
///
/// HTTP 200
/// {"data":null,"meta":{"valid":false,"detail":"does not exist",
///                      "code":"NOT_FOUND"}}
/// ```
///
/// **HTTP 200**, so nothing in the client treated it as an error, and
/// `NOT_FOUND` reads as revoked. A valid, signed, in-term Enterprise file
/// became `invalid` on the first phone-home after the machine found a
/// network, with no grace at all.
///
/// The fix for that skipped the phone-home for files altogether — which is the
/// second thing. A file then never asked the issuer anything after import: a
/// cancelled or refunded licence kept running on every machine that held the
/// file until the file's own expiry, and a renewal was never learned. The
/// file embeds the licence's key, and that key is exactly what `validate-key`
/// takes, so the question is asked about the key. The file itself is still
/// never posted; that part stays.
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

  late List<String> validated;
  setUp(() => validated = <String>[]);

  /// A controller over an issuer that knows exactly one key, [knownKey], and
  /// answers `NOT_FOUND` to anything else — a file's text included.
  CruxLicenseController controllerOver(_Store store, {String? knownKey}) =>
      CruxLicenseController(
        product: CruxProduct.waveCrux,
        validator: validator,
        store: store,
        client: KeygenLicenseClient(
          accountId: testAccountId,
          verifyKey: keys.verifyKey,
          client: _KeygenIssuer(keys, validated.add, knownKey),
        ),
        machine: const LicenseMachineIdentity(
          name: 'lab-01',
          platform: 'macos',
        ),
        openUrl: (_) async {},
        purchaseUrl: Uri.parse('https://example.test/pricing'),
        now: () => duringTerm,
      );

  Future<String> enterpriseFile({required String key}) => keys.mintFile(
    filePayload(
      key: key,
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

  test('the file itself is never posted; the key it embeds is', () async {
    final key = await keys.mintKey(
      keyPayload(policy: testSuiteEnterprisePolicyId),
    );
    final store = _Store();
    final controller = controllerOver(store, knownKey: key);
    addTearDown(controller.dispose);

    await controller.importOfflineToken(await enterpriseFile(key: key));

    expect(
      validated,
      everyElement(key),
      reason:
          'THE assertion. Posting the file gets NOT_FOUND, which reads as '
          'revoked; posting the key gets the answer about the licence.',
    );
    expect(validated, isNotEmpty, reason: 'and the question is asked');
    expect(controller.status.activation, CruxLicenseActivation.active);
    expect(controller.status.tier, LicenseTier.enterprise);
    expect(store.lastCheck, duringTerm, reason: 'confirmed by the issuer');
  });

  test('the daily phone-home keeps asking about the key', () async {
    final key = await keys.mintKey(keyPayload());
    final store = _Store();
    final controller = controllerOver(store, knownKey: key);
    addTearDown(controller.dispose);
    await controller.importOfflineToken(
      await keys.mintFile(filePayload(key: key)),
    );
    final asked = validated.length;

    final result = await controller.refresh();

    expect(result.isOk, isTrue);
    expect(validated.length, asked + 1);
    expect(validated.last, key);
    expect(controller.status.activation, CruxLicenseActivation.active);
    expect(controller.status.tier, LicenseTier.pro);
  });

  test('a file whose licence the issuer no longer knows is revoked', () async {
    // The revenue case for asking at all: a chargeback, a refund or a
    // cancellation ends in a licence the issuer suspends or deletes. A file
    // that never asked kept running on every machine that held it.
    final key = await keys.mintKey(keyPayload());
    final store = _Store();
    final controller = controllerOver(store, knownKey: 'some-other-key');
    addTearDown(controller.dispose);

    await controller.importOfflineToken(
      await keys.mintFile(filePayload(key: key)),
    );

    expect(validated, everyElement(key));
    expect(
      controller.status.activation,
      CruxLicenseActivation.invalid,
      reason: "NOT_FOUND on the licence's own key means revoked",
    );
    expect(controller.status.tier, LicenseTier.openCore);
  });

  test('a machine file is asked about with the key it includes', () async {
    final key = await keys.mintKey(keyPayload());
    final store = _Store();
    final controller = controllerOver(store, knownKey: key);
    addTearDown(controller.dispose);

    await controller.importOfflineToken(
      await keys.mintMachineFile(machineFilePayload(key: key)),
    );

    expect(validated, everyElement(key));
    expect(validated, isNotEmpty);
    expect(controller.status.activation, CruxLicenseActivation.active);
  });

  group('a file that embeds no key', () {
    // Nothing to ask with, so it is left to its own signed claims — which is
    // the whole file story from before, kept for the file that has no key.
    test('is never posted and stays licensed', () async {
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.importOfflineToken(await keys.mintFile(filePayload()));
      await controller.refresh();

      expect(validated, isEmpty);
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('refreshing reports success, not offline', () async {
      // The panel renders `offline` as "Could not reach the license server
      // ... try again when you are online", which would be both untrue and
      // unactionable for somebody whose network is fine: no call would ever
      // succeed, because the file answers the question by itself.
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);
      await controller.importOfflineToken(await keys.mintFile(filePayload()));

      final result = await controller.refresh();

      expect(result.isOk, isTrue);
      expect(validated, isEmpty);
    });

    test('is not marked as issuer-confirmed', () async {
      // `lastCheckedAt` drives "Last checked" in the licence panel. Such a
      // file was never confirmed by anybody, and writing a timestamp for a
      // call that was never made would say otherwise.
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.importOfflineToken(await keys.mintFile(filePayload()));
      await controller.refresh();

      expect(store.lastCheck, isNull);
    });
  });

  test(
    'a licence KEY is still validated, and NOT_FOUND still revokes',
    () async {
      // Revocation on refund, chargeback and cancellation is the only thing
      // the phone-home can actually take away, and it has to keep working.
      final store = _Store();
      final controller = controllerOver(store, knownKey: 'some-other-key');
      addTearDown(controller.dispose);

      await controller.activate(await keys.mintKey(keyPayload()));

      expect(validated, isNotEmpty, reason: 'a key must still be checked');
      expect(
        controller.status.activation,
        CruxLicenseActivation.invalid,
        reason: 'NOT_FOUND on a real key means revoked and must stay that way',
      );
    },
  );
}

/// Answers validate-key as the live account does: `VALID` for the one key it
/// knows, and **HTTP 200** with `meta.code: NOT_FOUND` for any other text —
/// the 200 is the load-bearing part, because a 4xx would have been swallowed
/// by the client and nothing would have broken. Machine registration succeeds:
/// if it refused, `activate()` would return early and never reach the
/// refresh, and every test here would pass for the wrong reason.
class _KeygenIssuer extends http.BaseClient {
  _KeygenIssuer(this._keys, this._onValidate, [this._knownKey]);

  final TestIssuerKeys _keys;
  final void Function(String key) _onValidate;
  final String? _knownKey;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('licenses/actions/validate-key')) {
      final body =
          json.decode((request as http.Request).body) as Map<String, Object?>;
      final meta = body['meta']! as Map<String, Object?>;
      final key = meta['key']! as String;
      _onValidate(key);
      final known = key == _knownKey;
      return signedIssuerResponse(
        keys: _keys,
        request: request,
        body: <String, Object?>{
          'data': known
              ? <String, Object?>{
                  'type': 'licenses',
                  'id': 'lic00000-0000-4000-8000-000000000001',
                  'attributes': <String, Object?>{
                    'expiry': '2027-06-01T00:00:00.000Z',
                  },
                }
              : null,
          'meta': <String, Object?>{
            'valid': known,
            'detail': known ? 'is valid' : 'does not exist',
            'code': known ? 'VALID' : 'NOT_FOUND',
            'scope': meta['scope'],
          },
        },
      );
    }
    return signedIssuerResponse(
      keys: _keys,
      request: request,
      status: 201,
      body: <String, Object?>{
        'data': <String, Object?>{'type': 'machines', 'id': 'machine-1'},
      },
    );
  }
}

class _Store implements LicenseStore {
  String? credential;
  String? machineId;
  DateTime? lastCheck;

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
  Future<String> readOrCreateFingerprint() async => 'fingerprint-1';

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
