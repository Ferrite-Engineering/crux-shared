// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// A check that is skipped or fails leaves a trace.
///
/// `lastCheck` moves only on an attested answer, which is what keeps a failure
/// to reach the issuer from downgrading anyone. That left no record of an
/// attempt, so a stuck check and a check that never ran looked the same on
/// disk. `lastAttempt` and its outcome are written beside it, and none of the
/// cases below may change the stored state.
void main() {
  late TestIssuerKeys keys;
  late CruxLicenseValidator validator;
  late Directory home;

  final duringTerm = DateTime.utc(2026, 9);
  const keyExpiry = '2027-08-15T00:00:00.000Z';
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

  setUp(() => home = Directory.systemTemp.createTempSync('crux_attempt_'));
  tearDown(() => home.deleteSync(recursive: true));

  final answer = <String, Object?>{
    'meta': <String, Object?>{
      'valid': true,
      'code': 'VALID',
      'scope': <String, Object?>{'fingerprint': 'fingerprint-1'},
    },
    'data': <String, Object?>{
      'type': 'licenses',
      'id': licenseId,
      'attributes': <String, Object?>{
        'expiry': keyExpiry,
        'maxMachines': 3,
      },
    },
  };

  CruxLicenseController controllerOver(
    _Store store,
    KeygenLicenseClient client, {
    LicenseFallbackFile? fallbackFile,
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: client,
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'linux'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/buy'),
    now: () => duringTerm,
    fallbackFile:
        fallbackFile ??
        LicenseFallbackFile.forProduct(
          'wavecrux',
          environment: <String, String>{
            'HOME': home.path,
            'XDG_DATA_HOME': home.path,
            'LOCALAPPDATA': home.path,
          },
        ),
  );

  KeygenLicenseClient unreachable() => KeygenLicenseClient(
    accountId: testAccountId,
    verifyKey: keys.verifyKey,
    client: stubClient((_) => throw const _Unreachable()),
  );

  KeygenLicenseClient unsigned() => KeygenLicenseClient(
    accountId: testAccountId,
    verifyKey: keys.verifyKey,
    client: stubClient((_) => unsignedIssuerResponse(answer)),
  );

  KeygenLicenseClient signed() => KeygenLicenseClient(
    accountId: testAccountId,
    verifyKey: keys.verifyKey,
    client: signedJsonClient(keys, answer),
  );

  test('an unreachable issuer leaves an attempt and no check', () async {
    final store = _Store(credential: await keys.mintKey(keyPayload()));
    final controller = controllerOver(store, unreachable());
    addTearDown(controller.dispose);

    await controller.start();
    await controller.refresh();

    expect(
      await controller.readLastAttempt(),
      LicenseCheckAttempt(duringTerm, LicenseCheckOutcome.notAttested),
    );
    expect(store.lastCheck, isNull, reason: 'nobody was reached');
    expect(controller.status.activation, CruxLicenseActivation.active);
  });

  test('an unsigned answer leaves an attempt and no check', () async {
    final store = _Store(credential: await keys.mintKey(keyPayload()));
    final controller = controllerOver(store, unsigned());
    addTearDown(controller.dispose);

    await controller.start();
    await controller.refresh();

    expect(
      await controller.readLastAttempt(),
      LicenseCheckAttempt(duringTerm, LicenseCheckOutcome.notAttested),
    );
    expect(store.lastCheck, isNull);
    expect(store.issuerSnapshot, isNull);
    expect(controller.status.activation, CruxLicenseActivation.active);
  });

  test('a key-less licence file leaves a noKey attempt', () async {
    final store = _Store();
    final controller = controllerOver(store, unreachable());
    addTearDown(controller.dispose);

    await controller.importOfflineToken(await keys.mintFile(filePayload()));
    await controller.refresh();

    expect(
      await controller.readLastAttempt(),
      LicenseCheckAttempt(duringTerm, LicenseCheckOutcome.noKey),
    );
    expect(store.lastCheck, isNull, reason: 'a key-less file is not checked');
    expect(controller.status.activation, CruxLicenseActivation.active);
  });

  test('an attested answer records both the check and the attempt', () async {
    final store = _Store(credential: await keys.mintKey(keyPayload()));
    final controller = controllerOver(store, signed());
    addTearDown(controller.dispose);

    await controller.start();
    await controller.refresh();

    expect(store.lastCheck, duringTerm);
    expect(
      await controller.readLastAttempt(),
      LicenseCheckAttempt(duringTerm, LicenseCheckOutcome.attested),
    );
  });

  test('a failed attempt after a success keeps the success', () async {
    final store = _Store(credential: await keys.mintKey(keyPayload()))
      ..lastCheck = DateTime.utc(2026, 8);
    final controller = controllerOver(store, unreachable());
    addTearDown(controller.dispose);

    await controller.start();
    await controller.refresh();

    expect(store.lastCheck, DateTime.utc(2026, 8), reason: 'never downgraded');
    expect(
      (await controller.readLastAttempt())?.outcome,
      LicenseCheckOutcome.notAttested,
    );
  });

  test('the attempt lands in the fallback file, beside lastCheck', () async {
    final fallback = LicenseFallbackFile.forProduct(
      'wavecrux',
      environment: <String, String>{
        'HOME': home.path,
        'XDG_DATA_HOME': home.path,
        'LOCALAPPDATA': home.path,
      },
    );
    final store = _Store(failWrites: true);
    final controller = controllerOver(
      store,
      unreachable(),
      fallbackFile: fallback,
    );
    addTearDown(controller.dispose);

    final key = await keys.mintKey(keyPayload());
    await controller.importOfflineToken(
      await keys.mintFile(filePayload(key: key)),
    );
    await controller.refresh();

    final onDisk =
        json.decode(File(fallback.path!).readAsStringSync())
            as Map<String, Object?>;
    expect(onDisk['lastAttempt'], '2026-09-01T00:00:00.000Z');
    expect(onDisk['lastAttemptOutcome'], 'notAttested');
    expect(onDisk.containsKey('lastCheck'), isFalse);

    // A relaunch reads it back from the file.
    final relaunched = controllerOver(
      store,
      unreachable(),
      fallbackFile: fallback,
    );
    addTearDown(relaunched.dispose);
    expect(
      await relaunched.readLastAttempt(),
      LicenseCheckAttempt(duringTerm, LicenseCheckOutcome.notAttested),
    );
  });
}

class _Unreachable implements Exception {
  const _Unreachable();
}

class _Store implements LicenseStore {
  _Store({this.credential, this.failWrites = false});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String? issuerSnapshot;
  final bool failWrites;

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
  Future<void> writeCredential(String credential) async {
    if (failWrites) throw StateError('no secret service');
    this.credential = credential;
  }

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
