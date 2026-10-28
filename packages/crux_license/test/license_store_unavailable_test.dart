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
import 'package:path/path.dart' as p;

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
/// - a licence file or machine file is kept in an owner-only fallback file,
///   found again after a restart, named in the status for the panel, and
///   removed when the licence is cleared;
/// - a licence key the user pastes is refused as
///   [CruxLicenseActionFailure.storeUnavailable], not as an unknown error,
///   is never written to a file, and grants nothing for the session;
/// - where the store works, none of this changes anything.
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

  // Every controller here gets its fallback file under a temporary
  // directory: the default is the developer's real licence directory.
  late Directory home;
  late Map<String, String> environment;
  setUp(() {
    home = Directory.systemTemp.createTempSync('crux_license_nostore_');
    environment = <String, String>{
      'HOME': home.path,
      'XDG_DATA_HOME': home.path,
      'LOCALAPPDATA': home.path,
    };
  });
  tearDown(() => home.deleteSync(recursive: true));

  LicenseFallbackFile fallbackFor(CruxProduct product) =>
      LicenseFallbackFile.forProduct(
        product.entitlementCode.toLowerCase(),
        environment: environment,
      );

  File fallbackOnDisk([CruxProduct product = CruxProduct.waveCrux]) =>
      File(fallbackFor(product).path!);

  Future<CruxLicenseController> startedController(
    LicenseStore store, {
    LicenseFallbackFile? fallbackFile,
  }) async {
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
      fallbackFile: fallbackFile ?? fallbackFor(CruxProduct.waveCrux),
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

  Future<bool> applyFrom(
    CruxLicenseController controller,
    Map<String, Object?> license, {
    String? fileContents,
  }) => applyPolicyLicense(
    controller: controller,
    policy: policyWith(license),
    readFile: (_) async => fileContents,
  );

  group('a policy licence needs no store', () {
    test('an inline key resolves with a store that throws on every call, '
        'and again on the next launch', () async {
      final key = await issuer.mintKey(keyPayload());

      for (final launch in <int>[1, 2]) {
        final store = _KeyringlessStore();
        final controller = await startedController(store);
        expect(
          controller.status.tier,
          LicenseTier.openCore,
          reason: 'launch $launch: nothing could be stored',
        );

        expect(await applyFrom(controller, {'key': key}), isTrue);

        expect(controller.status.tier, LicenseTier.pro, reason: '$launch');
        expect(controller.status.activation, CruxLicenseActivation.active);
        expect(store.writes, greaterThan(0), reason: 'the store was asked');
        expect(controller.status.credentialFile, isNull);
        expect(fallbackOnDisk().existsSync(), isFalse, reason: 'a key');
      }
    });

    test('a licence file from the share goes to the fallback file', () async {
      final file = await issuer.mintFile(
        filePayload(
          entitlements: const <String>['TIER_ENTERPRISE', 'WAVECRUX'],
        ),
      );
      final controller = await startedController(_KeyringlessStore());

      expect(
        await applyFrom(controller, {
          'file': '/share/seat.lic',
        }, fileContents: file),
        isTrue,
      );

      expect(controller.status.tier, LicenseTier.enterprise);
      expect(controller.status.credentialFile, fallbackOnDisk().path);
    });

    test('a licence file with nowhere to go is held, like a key', () async {
      final controller = await startedController(
        _KeyringlessStore(),
        fallbackFile: LicenseFallbackFile(() => throw StateError('no home')),
      );

      expect(
        await applyFrom(controller, {
          'file': '/share/seat.lic',
        }, fileContents: await issuer.mintFile(filePayload())),
        isTrue,
      );

      expect(controller.status.tier, LicenseTier.pro);
      expect(controller.status.credentialFile, isNull);
    });

    test('a check-in later in the session keeps the tier', () async {
      final controller = await startedController(_KeyringlessStore());
      await applyFrom(controller, {'key': await issuer.mintKey(keyPayload())});

      final result = await controller.refresh();

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

      expect(await applyFrom(controller, {'key': foreign}), isFalse);

      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.hasCredential, isFalse);
    });

    test('with a working store the policy credential is stored, and the '
        'next launch does not activate again', () async {
      final key = await issuer.mintKey(keyPayload());
      final store = _MapStore();

      final first = await startedController(store);
      expect(await applyFrom(first, {'key': key}), isTrue);
      expect(store.credential, key);

      final second = await startedController(store);
      expect(second.status.tier, LicenseTier.pro);
      expect(
        await applyFrom(second, {'key': key}),
        isFalse,
        reason: 'already licensed from the store',
      );
    });
  });

  group('a pasted licence key the store cannot keep', () {
    test('fails as storeUnavailable and grants nothing', () async {
      final key = await issuer.mintKey(keyPayload());
      final controller = await startedController(_KeyringlessStore());

      final result = await controller.activate(key);

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.storeUnavailable,
      );
      expect(result.detail, contains('credential store unavailable'));
      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.busy, isFalse);
      expect(attempts, 0, reason: 'nothing to register a seat for');
      expect(
        fallbackOnDisk().existsSync(),
        isFalse,
        reason: 'a key is never written to a file',
      );
    });

    test('does not ride on a held policy credential', () async {
      final controller = await startedController(_KeyringlessStore());
      await applyFrom(controller, {'key': await issuer.mintKey(keyPayload())});

      final result = await controller.activate(
        await issuer.mintKey(keyPayload(policy: testSuiteEnterprisePolicyId)),
      );

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.storeUnavailable,
      );
      expect(controller.status.tier, LicenseTier.pro, reason: 'unchanged');
    });

    test('a fingerprint that cannot be read is storeUnavailable', () async {
      final controller = await startedController(
        _KeyringlessStore(fingerprintWorks: false),
      );

      final result = await controller.activate(
        await issuer.mintKey(keyPayload()),
      );

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.storeUnavailable,
      );
    });
  });

  group('a licence file or machine file the store cannot keep', () {
    final forms = <String, Future<String> Function()>{
      'a licence file': () => issuer.mintFile(filePayload()),
      // Checked out for 'fingerprint-1', the fingerprint every store here
      // answers.
      'a machine file': () => issuer.mintMachineFile(machineFilePayload()),
    };

    for (final MapEntry(key: kind, value: mint) in forms.entries) {
      test('$kind is kept in an owner-only file and found after a '
          'restart', () async {
        final credential = await mint();
        final first = await startedController(_KeyringlessStore());

        expect(await first.activate(credential), isA<LicenseActionSucceeded>());

        final file = fallbackOnDisk();
        expect(first.status.tier, LicenseTier.pro);
        expect(first.status.credentialFile, file.path);
        expect(
          p.dirname(file.path),
          cruxLicenseDirectory(environment: environment),
          reason: 'beside install.fingerprint',
        );
        if (!Platform.isWindows) {
          expect(file.statSync().mode & 0x1ff, 0x180, reason: 'rw-------');
        }
        final document =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(document['format'], 'crux.license-fallback/v1');
        expect(document['credential'], credential.trim());

        final second = await startedController(_KeyringlessStore());
        expect(second.status.tier, LicenseTier.pro, reason: 'after restart');
        expect(second.status.credentialFile, file.path);
      });
    }

    test('deactivating removes the file', () async {
      final controller = await startedController(_KeyringlessStore());
      await controller.activate(await issuer.mintFile(filePayload()));
      expect(fallbackOnDisk().existsSync(), isTrue);

      final result = await controller.deactivateThisMachine();

      expect(result, isA<LicenseActionSucceeded>());
      expect(fallbackOnDisk().existsSync(), isFalse);
      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.credentialFile, isNull);
    });

    test('a file kept without a keyring is found with one, until the '
        'keyring takes a licence', () async {
      final keyless = await startedController(_KeyringlessStore());
      await keyless.activate(await issuer.mintFile(filePayload()));

      final store = _MapStore();
      final withKeyring = await startedController(store);
      expect(withKeyring.status.tier, LicenseTier.pro);
      expect(withKeyring.status.credentialFile, fallbackOnDisk().path);

      final key = await issuer.mintKey(
        keyPayload(policy: testSuiteEnterprisePolicyId),
      );
      expect(await withKeyring.activate(key), isA<LicenseActionSucceeded>());

      expect(store.credential, key);
      expect(fallbackOnDisk().existsSync(), isFalse, reason: 'superseded');
      expect(withKeyring.status.tier, LicenseTier.enterprise);
      expect(withKeyring.status.credentialFile, isNull);
    });

    test('a file edited to hold a key holds nothing', () async {
      fallbackOnDisk()
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'format': 'crux.license-fallback/v1',
            'credential': await issuer.mintKey(keyPayload()),
          }),
        );

      final controller = await startedController(_KeyringlessStore());

      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.credentialFile, isNull);
    });

    test('another product does not read this one', () async {
      final controller = await startedController(_KeyringlessStore());
      await controller.activate(await issuer.mintFile(filePayload()));

      expect(fallbackOnDisk().existsSync(), isTrue);
      expect(fallbackOnDisk(CruxProduct.netCrux).existsSync(), isFalse);
    });

    test('with a working store, no file is written', () async {
      final store = _MapStore();
      final controller = await startedController(store);

      await controller.activate(await issuer.mintFile(filePayload()));

      expect(store.credential, contains('BEGIN LICENSE FILE'));
      expect(controller.status.credentialFile, isNull);
      expect(home.listSync(recursive: true), isEmpty);
    });
  });

  group('the fingerprint on a machine with no secret service', () {
    Future<String?> refused() async => throw const _SecretServiceRefused();

    test('on Linux, a legacy source that throws reads as none', () async {
      final shared = SharedInstallFingerprint(
        environment: environment,
        operatingSystem: 'linux',
      );

      final fingerprint = await shared.readOrCreate(legacy: [refused]);

      expect(fingerprint, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
    });

    test('elsewhere, it still propagates', () async {
      for (final os in <String>['macos', 'windows']) {
        final shared = SharedInstallFingerprint(
          environment: environment,
          operatingSystem: os,
        );
        await expectLater(
          shared.readOrCreate(legacy: [refused]),
          throwsA(isA<_SecretServiceRefused>()),
          reason: os,
        );
      }
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

/// A working store.
class _MapStore implements LicenseStore {
  String? credential;
  String? machineId;
  DateTime? lastCheck;
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
