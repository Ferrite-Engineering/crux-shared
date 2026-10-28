// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/license_fixtures.dart';

/// A machine whose credential store answers every call with an exception:
/// a Linux session with no secret service, where libsecret reports
/// `secret_service_get_sync: Could not connect: Connection refused`.
///
/// What still has to work there, and what has to fail in a way the user can
/// act on:
///
/// - a licence the organization's policy file supplies resolves from the
///   policy file at every launch, with nothing stored;
/// - a licence key the user pastes is refused as
///   [CruxLicenseActionFailure.storeUnavailable], not as an unknown error,
///   and grants nothing for the session;
/// - a store that kept the credential in a file says so, and the status
///   carries the file for the panel.
///
/// The fingerprint is not the credential store's: it is the suite's shared
/// file, which works on such a machine, so every store here answers it.
void main() {
  late TestIssuerKeys issuer;
  late CruxLicenseValidator validator;
  final duringTerm = DateTime.utc(2026, 9);

  setUpAll(() async {
    issuer = await TestIssuerKeys.fromSeed(7);
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[
        KeygenLicenseIssuer(
          accountId: testAccountId,
          verifyKey: issuer.verifyKey,
          policies: testPolicies,
        ),
      ],
    );
  });

  late int attempts;
  setUp(() => attempts = 0);

  Future<CruxLicenseController> startedController(LicenseStore store) async {
    final controller = CruxLicenseController(
      product: CruxProduct.waveCrux,
      validator: validator,
      store: store,
      client: KeygenLicenseClient(
        accountId: testAccountId,
        verifyKey: issuer.verifyKey,
        client: _Unreachable(() => attempts++),
      ),
      machine: const LicenseMachineIdentity(name: 'lab-07', platform: 'linux'),
      openUrl: (_) async {},
      purchaseUrl: Uri.parse('https://example.test/pricing'),
      now: () => duringTerm,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();
    return controller;
  }

  DayOnePolicy policyWith(Map<String, Object?> license) => DayOnePolicy.of(
    PolicyDocument.parse(
      jsonEncode(<String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{'license': license},
      }),
    ),
  );

  group('a policy licence needs no store', () {
    test('an inline key resolves with a store that throws on every '
        'call, and again on the next launch', () async {
      final key = await issuer.mintKey(keyPayload());
      final policy = policyWith({'key': key});

      for (final launch in <int>[1, 2]) {
        final store = _KeyringlessStore();
        final controller = await startedController(store);
        expect(
          controller.status.tier,
          LicenseTier.openCore,
          reason: 'launch $launch: nothing could be stored',
        );

        final applied = await applyPolicyLicense(
          controller: controller,
          policy: policy,
          readFile: (_) async => null,
        );

        expect(applied, isTrue, reason: 'launch $launch');
        expect(controller.status.tier, LicenseTier.pro, reason: '$launch');
        expect(controller.status.activation, CruxLicenseActivation.active);
        expect(store.writes, greaterThan(0), reason: 'the store was asked');
        expect(controller.status.credentialFile, isNull);
      }
    });

    test('a licence file from the share resolves the same way', () async {
      final file = await issuer.mintFile(
        filePayload(
          entitlements: const <String>['TIER_ENTERPRISE', 'WAVECRUX'],
        ),
      );
      final controller = await startedController(_KeyringlessStore());

      final applied = await applyPolicyLicense(
        controller: controller,
        policy: policyWith({'file': '/share/seat.lic'}),
        readFile: (path) async => path == '/share/seat.lic' ? file : null,
      );

      expect(applied, isTrue);
      expect(controller.status.tier, LicenseTier.enterprise);
    });

    test('a check-in later in the session keeps the tier', () async {
      final key = await issuer.mintKey(keyPayload());
      final controller = await startedController(_KeyringlessStore());
      await applyPolicyLicense(
        controller: controller,
        policy: policyWith({'key': key}),
        readFile: (_) async => null,
      );

      final result = await controller.refresh();

      expect(result, isA<LicenseActionFailed>());
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.offline,
        reason: 'the held credential was asked about, and nobody answered',
      );
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('a refused policy credential is not held', () async {
      final foreign = await issuer.mintKey(
        keyPayload(account: 'acc0acc0-0000-4000-8000-0000000000ff'),
      );
      final controller = await startedController(_KeyringlessStore());

      final applied = await applyPolicyLicense(
        controller: controller,
        policy: policyWith({'key': foreign}),
        readFile: (_) async => null,
      );

      expect(applied, isFalse);
      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.hasCredential, isFalse);
    });

    test('with a working store the policy credential is stored, and the '
        'next launch does not activate again', () async {
      final key = await issuer.mintKey(keyPayload());
      final policy = policyWith({'key': key});
      final store = _MapStore();

      final first = await startedController(store);
      expect(
        await applyPolicyLicense(
          controller: first,
          policy: policy,
          readFile: (_) async => null,
        ),
        isTrue,
      );
      expect(store.credential, key);

      final second = await startedController(store);
      expect(second.status.tier, LicenseTier.pro);
      expect(
        await applyPolicyLicense(
          controller: second,
          policy: policy,
          readFile: (_) async => null,
        ),
        isFalse,
        reason: 'already licensed from the store',
      );
    });
  });

  group('a pasted credential the store cannot keep', () {
    test(
      'a licence key fails as storeUnavailable and grants nothing',
      () async {
        final key = await issuer.mintKey(keyPayload());
        final controller = await startedController(_KeyringlessStore());

        final result = await controller.activate(key);

        expect(result, isA<LicenseActionFailed>());
        expect(
          (result as LicenseActionFailed).failure,
          CruxLicenseActionFailure.storeUnavailable,
        );
        expect(result.detail, contains('credential store unavailable'));
        expect(controller.status.tier, LicenseTier.openCore);
        expect(controller.status.busy, isFalse);
        expect(attempts, 0, reason: 'nothing to register a seat for');
      },
    );

    test('a key does not ride on a held policy credential', () async {
      final policyKey = await issuer.mintKey(keyPayload());
      final controller = await startedController(_KeyringlessStore());
      await applyPolicyLicense(
        controller: controller,
        policy: policyWith({'key': policyKey}),
        readFile: (_) async => null,
      );
      final other = await issuer.mintKey(
        keyPayload(policy: testSuiteEnterprisePolicyId),
      );

      final result = await controller.activate(other);

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.storeUnavailable,
      );
      expect(controller.status.tier, LicenseTier.pro, reason: 'unchanged');
    });

    test('a fingerprint that cannot be read is storeUnavailable', () async {
      final key = await issuer.mintKey(keyPayload());
      final controller = await startedController(
        _KeyringlessStore(fingerprintWorks: false),
      );

      final result = await controller.activate(key);

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.storeUnavailable,
      );
    });
  });

  group('a store that fell back to a file', () {
    test('the status names the file', () async {
      final file = await issuer.mintFile(filePayload());
      final store = _MapStore(fallbackPath: '/home/eng/.local/x.license');
      final controller = await startedController(store);

      expect(await controller.activate(file), isA<LicenseActionSucceeded>());

      expect(controller.status.tier, LicenseTier.pro);
      expect(controller.status.credentialFile, '/home/eng/.local/x.license');
    });

    test('a store in the credential store names nothing', () async {
      final store = _MapStore();
      final controller = await startedController(store);

      await controller.activate(await issuer.mintKey(keyPayload()));

      expect(controller.status.credentialFile, isNull);
    });

    test('a store that cannot say names nothing', () async {
      final store = _MapStore(fallbackThrows: true);
      final controller = await startedController(store);

      await controller.activate(await issuer.mintKey(keyPayload()));

      expect(controller.status.tier, LicenseTier.pro);
      expect(controller.status.credentialFile, isNull);
    });
  });
}

/// Every credential-store call throws; the fingerprint, which is the suite's
/// shared file rather than the credential store, answers unless told not to.
class _KeyringlessStore implements LicenseStore {
  _KeyringlessStore({this.fingerprintWorks = true});

  final bool fingerprintWorks;

  /// How many writes were attempted.
  int writes = 0;

  static const _refused = _SecretServiceRefused();

  @override
  Future<void> clear() async => throw _refused;

  @override
  Future<String?> readCredential() async => throw _refused;

  @override
  Future<void> writeCredential(String credential) async {
    writes++;
    throw _refused;
  }

  @override
  Future<String> readOrCreateFingerprint() async =>
      fingerprintWorks ? 'fingerprint-1' : throw _refused;

  @override
  Future<String?> readMachineId() async => throw _refused;

  @override
  Future<void> writeMachineId(String? machineId) async {
    writes++;
    throw _refused;
  }

  @override
  Future<DateTime?> readLastCheck() async => throw _refused;

  @override
  Future<void> writeLastCheck(DateTime at) async {
    writes++;
    throw _refused;
  }

  @override
  Future<String?> readIssuerSnapshot() async => throw _refused;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async {
    writes++;
    throw _refused;
  }
}

class _SecretServiceRefused implements Exception {
  const _SecretServiceRefused();

  @override
  String toString() =>
      'secret_service_get_sync: Could not connect: Connection refused';
}

/// A working store, which may say it keeps the credential in a file.
class _MapStore implements LicenseStore, LicenseStoreFallback {
  _MapStore({this.fallbackPath, this.fallbackThrows = false});

  final String? fallbackPath;
  final bool fallbackThrows;

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String? issuerSnapshot;

  @override
  Future<String?> credentialFilePath() async {
    if (fallbackThrows) throw const FileSystemException('unreadable');
    return credential == null ? null : fallbackPath;
  }

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
  Future<void> writeCredential(String credential) async =>
      this.credential = credential;

  @override
  Future<String> readOrCreateFingerprint() async => 'fingerprint-1';

  @override
  Future<String?> readMachineId() async => machineId;

  @override
  Future<void> writeMachineId(String? machineId) async =>
      this.machineId = machineId;

  @override
  Future<DateTime?> readLastCheck() async => lastCheck;

  @override
  Future<void> writeLastCheck(DateTime at) async => lastCheck = at;

  @override
  Future<String?> readIssuerSnapshot() async => issuerSnapshot;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async =>
      issuerSnapshot = snapshot;
}

class _Unreachable extends http.BaseClient {
  _Unreachable(this._onAttempt);

  final void Function() _onAttempt;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _onAttempt();
    throw const SocketException('no route to host');
  }
}
