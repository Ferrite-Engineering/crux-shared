// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// What the issuer last said is stored beside the credential, and the stored
/// answer can extend the licence — a renewal recorded at the issuer wins over
/// the older date baked into the key. That makes the store the one place a
/// user can write something that grants more than their key does.
///
/// The property under test: **nothing in the store extends a licence unless
/// the issuer signed it.** The issuer signs every response it sends, over the
/// request target, the host, the date and a digest of the body, with the same
/// account key that signs the credentials themselves. The controller keeps
/// that signed answer verbatim, verifies it on every load, and believes the
/// key's own claims when the signature does not hold. A hand-written answer,
/// an edited one, one replayed from another licence or another install, and
/// one that arrived unsigned all resolve to exactly what the key says.
///
/// What this deliberately does not try to prevent: deleting the stored answer.
/// A user who deletes a recorded suspension is in the same position as one
/// who blocked the issuer before the suspension was recorded — the key's own
/// expiry bounds both, and offline never downgrades by design.
void main() {
  late TestIssuerKeys keys;
  late CruxLicenseValidator validator;

  final duringTerm = DateTime.utc(2026, 9);
  const keyExpiry = '2026-08-15T00:00:00.000Z';
  const licenseId = 'lic00000-0000-4000-8000-000000000001';

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

  /// The issuer's answer for a subscriber who renewed after the key was cut.
  final renewed = <String, Object?>{
    'meta': <String, Object?>{
      'valid': true,
      'code': 'VALID',
      'scope': <String, Object?>{'fingerprint': 'fingerprint-1'},
    },
    'data': <String, Object?>{
      'type': 'licenses',
      'id': licenseId,
      'attributes': <String, Object?>{
        'expiry': '2027-08-15T00:00:00.000Z',
        'maxMachines': 3,
      },
    },
  };

  CruxLicenseController controllerOver(
    _Store store, {
    KeygenLicenseClient? client,
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client:
        client ??
        KeygenLicenseClient(
          accountId: testAccountId,
          verifyKey: keys.verifyKey,
          client: stubClient((_) => throw const _Unreachable()),
        ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/buy'),
    now: () => duringTerm,
  );

  /// Runs one online session that records the issuer's signed renewal, and
  /// hands back the store it left behind.
  Future<_Store> recordedRenewal({String fingerprint = 'fingerprint-1'}) async {
    final store = _Store(
      credential: await keys.mintKey(keyPayload(expiry: keyExpiry)),
      fingerprint: fingerprint,
    );
    final online = controllerOver(
      store,
      client: KeygenLicenseClient(
        accountId: testAccountId,
        verifyKey: keys.verifyKey,
        client: signedJsonClient(keys, renewed),
      ),
    );
    await online.start();
    await online.refresh();
    await online.dispose();
    expect(store.issuerSnapshot, isNotNull);
    return store;
  }

  test('the signed renewal is honoured on relaunch — the baseline', () async {
    final store = await recordedRenewal();

    final relaunched = controllerOver(store);
    addTearDown(relaunched.dispose);
    await relaunched.start();

    expect(relaunched.status.activation, CruxLicenseActivation.active);
    expect(relaunched.status.grant!.expiry, DateTime.utc(2027, 8, 15));
  });

  test('a hand-written answer does not extend the licence', () async {
    // The exploit: a subscriber whose key has lapsed writes the answer they
    // would like the issuer to have given straight into the store, then keeps
    // the issuer unreachable. Nothing signed it, so nothing believes it.
    final store =
        _Store(
            credential: await keys.mintKey(
              keyPayload(expiry: '2026-06-01T00:00:00Z'),
            ),
          )
          ..lastCheck = duringTerm
          ..issuerSnapshot = json.encode(<String, Object?>{
            'licenseId': licenseId,
            'code': 'valid',
            'expiry': '2999-01-01T00:00:00.000Z',
            'maxMachines': 3,
            'machineCount': 1,
            'seatRefused': false,
          });
    final controller = controllerOver(store);
    addTearDown(controller.dispose);

    await controller.start();

    expect(
      controller.status.activation,
      CruxLicenseActivation.expired,
      reason:
          'THE assertion: the key expired in June and Pro grace ran out in '
          'July; a store entry nobody signed must not say otherwise',
    );
    expect(controller.status.tier, LicenseTier.openCore);
    expect(controller.status.grant!.expiry, DateTime.utc(2026, 6));
  });

  test('an edited signed answer is discarded whole, not partly', () async {
    final store = await recordedRenewal();
    // The stored answer carries the issuer's body verbatim, so the date is
    // right there to edit. One changed byte breaks the digest, the digest is
    // signed, and the answer stops being an answer.
    store.issuerSnapshot = store.issuerSnapshot!.replaceAll(
      '2027-08-15',
      '2999-01-01',
    );

    final relaunched = controllerOver(store);
    addTearDown(relaunched.dispose);
    await relaunched.start();

    expect(
      relaunched.status.grant!.expiry,
      DateTime.utc(2026, 8, 15),
      reason: 'neither the forged date nor the genuine renewal survives',
    );
    expect(relaunched.status.activation, CruxLicenseActivation.grace);
  });

  test('a signed answer about another licence is not applied', () async {
    // Replay: the answer is genuinely the issuer's, about a licence that was
    // renewed, kept and pointed at a licence that was not.
    final store = await recordedRenewal();
    final other = keyPayload(expiry: keyExpiry);
    (other['license']! as Map<String, Object?>)['id'] =
        'lic00000-0000-4000-8000-000000000002';
    store.credential = await keys.mintKey(other);
    final snapshot = json.decode(store.issuerSnapshot!) as Map<String, Object?>;
    snapshot['licenseId'] = 'lic00000-0000-4000-8000-000000000002';
    store.issuerSnapshot = json.encode(snapshot);

    final relaunched = controllerOver(store);
    addTearDown(relaunched.dispose);
    await relaunched.start();

    expect(relaunched.status.grant!.expiry, DateTime.utc(2026, 8, 15));
    expect(relaunched.status.activation, CruxLicenseActivation.grace);
  });

  test('a signed answer about another install is not applied', () async {
    // The issuer echoes the fingerprint the question was scoped to, inside
    // the signed body. Copying the store from one machine to another carries
    // the answer along with the credential; the answer stays behind.
    final store = await recordedRenewal();
    final copied = _Store(
      credential: store.credential,
      fingerprint: 'fingerprint-2',
    )..issuerSnapshot = store.issuerSnapshot;

    final relaunched = controllerOver(copied);
    addTearDown(relaunched.dispose);
    await relaunched.start();

    expect(relaunched.status.grant!.expiry, DateTime.utc(2026, 8, 15));
    expect(relaunched.status.activation, CruxLicenseActivation.grace);
  });

  test('an unsigned answer is not an answer', () async {
    // A proxy on the path that rewrites the body — or an issuer whose signing
    // changed shape — produces a body with no signature over it. Treated as
    // not having reached the issuer: nothing changes, and nothing is stored.
    final store = _Store(
      credential: await keys.mintKey(keyPayload(expiry: keyExpiry)),
    );
    final controller = controllerOver(
      store,
      client: KeygenLicenseClient(
        accountId: testAccountId,
        verifyKey: keys.verifyKey,
        client: stubClient((_) => unsignedIssuerResponse(renewed)),
      ),
    );
    addTearDown(controller.dispose);

    await controller.start();
    final result = await controller.refresh();

    expect(result.isOk, isFalse);
    expect(
      (result as LicenseActionFailed).failure,
      CruxLicenseActionFailure.offline,
    );
    expect(controller.status.grant!.expiry, DateTime.utc(2026, 8, 15));
    expect(store.lastCheck, isNull, reason: 'nobody trustworthy was reached');
    expect(store.issuerSnapshot, isNull);
  });

  test('a restriction survives without a signature', () async {
    // The seat refusal is recorded from a machine registration, which is not
    // the answer the signature protects, and it needs no protection: forging
    // it can only take a tier away. What matters is that it still applies.
    final store =
        _Store(
            credential: await keys.mintKey(keyPayload(expiry: keyExpiry)),
          )
          ..lastCheck = duringTerm
          ..issuerSnapshot = json.encode(<String, Object?>{
            'licenseId': licenseId,
            'seatRefused': true,
          });
    final controller = controllerOver(store);
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.status.activation, CruxLicenseActivation.noSeat);
    expect(controller.status.tier, LicenseTier.openCore);
  });
}

class _Store implements LicenseStore {
  _Store({this.credential, this.fingerprint = 'fingerprint-1'});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String fingerprint;
  String? issuerSnapshot;

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

  @override
  Future<String?> readIssuerSnapshot() async => issuerSnapshot;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async =>
      issuerSnapshot = snapshot;

  @override
  Future<void> writeMachineId(String? machineId) async =>
      this.machineId = machineId;
}

class _Unreachable implements Exception {
  const _Unreachable();
}
