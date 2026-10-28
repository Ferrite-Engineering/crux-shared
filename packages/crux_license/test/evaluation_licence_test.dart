// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/license_fixtures.dart';

/// Evaluation licences: an `EVALUATION` entitlement, no grace period, and a
/// clock high-water mark that a paid licence never gets.
///
/// The fixtures are issued 2026-08-01 and expire 2027-01-01, on a machine
/// that never reaches the issuer: the air-gapped evaluation is the case the
/// clock check exists for.
void main() {
  late TestIssuerKeys keys;
  late CruxLicenseValidator validator;

  const evaluationCodes = <String>['WAVECRUX', 'TIER_ENTERPRISE', 'EVALUATION'];
  const paidCodes = <String>['WAVECRUX', 'TIER_ENTERPRISE'];
  final expiry = DateTime.utc(2027);

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(9);
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

  Future<LicenseGrant?> grantOf(String credential) async =>
      (await validator.validate(
        credential,
        now: DateTime.utc(2026, 9),
        fingerprint: 'fingerprint-1',
      )).grant;

  group('the entitlement is read from every credential format', () {
    test('a licence file', () async {
      final file = await keys.mintFile(
        filePayload(entitlements: evaluationCodes),
      );
      final grant = await grantOf(file);
      expect(grant!.isEvaluation, isTrue);
      expect(grant.issued, DateTime.utc(2026, 8));
    });

    test('a machine file', () async {
      final file = await keys.mintMachineFile(
        machineFilePayload(entitlements: evaluationCodes),
      );
      final grant = await grantOf(file);
      expect(grant!.isEvaluation, isTrue);
      expect(grant.issued, DateTime.utc(2026, 8));
    });

    test('a key whose dataset lists it, as codes or as objects', () async {
      final beside = keyPayload()..['entitlements'] = <Object?>['EVALUATION'];
      final onLicence = keyPayload();
      (onLicence['license']!
          as Map<String, Object?>)['entitlements'] = <Object?>[
        <String, Object?>{'code': 'evaluation'},
      ];
      for (final payload in [beside, onLicence]) {
        final grant = await grantOf(await keys.mintKey(payload));
        expect(grant!.isEvaluation, isTrue);
        // Still resolved through the table: EVALUATION names no tier.
        expect(grant.tier, LicenseTier.pro);
        expect(grant.resolvedFromEntitlements, isFalse);
        expect(grant.issued, DateTime.utc(2026, 8));
      }
    });

    test('a paid credential of each format is not an evaluation', () async {
      final credentials = [
        await keys.mintFile(filePayload(entitlements: paidCodes)),
        await keys.mintMachineFile(
          machineFilePayload(entitlements: paidCodes),
        ),
        await keys.mintKey(keyPayload()),
      ];
      for (final credential in credentials) {
        expect((await grantOf(credential))!.isEvaluation, isFalse);
      }
    });

    test(
      'a key dataset whose entitlements are not a list reads as none',
      () async {
        final payload = keyPayload()..['entitlements'] = 'EVALUATION';
        final grant = await grantOf(await keys.mintKey(payload));
        expect(grant!.isEvaluation, isFalse);
      },
    );
  });

  group('LicenseGracePolicy', () {
    const grace = LicenseGracePolicy.standard;

    test('gives an evaluation none, whatever its tier', () {
      for (final tier in [
        LicenseTier.pro,
        LicenseTier.edu,
        LicenseTier.enterprise,
      ]) {
        expect(grace.forTier(tier, evaluation: true), Duration.zero);
        expect(grace.endsAfter(expiry, tier, evaluation: true), expiry);
        expect(
          grace.covers(
            expiry: expiry,
            tier: tier,
            now: expiry.add(const Duration(seconds: 1)),
            evaluation: true,
          ),
          isFalse,
        );
      }
    });

    test('keeps the paid windows unchanged', () {
      expect(grace.forTier(LicenseTier.pro), const Duration(days: 30));
      expect(grace.forTier(LicenseTier.edu), const Duration(days: 60));
      expect(grace.forTier(LicenseTier.enterprise), const Duration(days: 90));
    });
  });

  group('the controller, offline', () {
    late DateTime clock;
    late InMemoryLicenseClockMark mark;

    setUp(() {
      clock = DateTime.utc(2026, 10);
      mark = InMemoryLicenseClockMark();
    });

    Future<CruxLicenseController> started(String credential) async {
      final controller = CruxLicenseController(
        product: CruxProduct.waveCrux,
        validator: validator,
        store: _Store(credential: credential),
        client: KeygenLicenseClient(
          accountId: testAccountId,
          verifyKey: keys.verifyKey,
          client: _Unreachable(),
        ),
        machine: const LicenseMachineIdentity(
          name: 'lab-01',
          platform: 'macos',
        ),
        openUrl: (_) async {},
        purchaseUrl: Uri.parse('https://example.test/pricing'),
        now: () => clock,
        clockMark: mark,
      );
      addTearDown(controller.dispose);
      await controller.start();
      return controller;
    }

    Future<String> evaluationFile() =>
        keys.mintFile(filePayload(entitlements: evaluationCodes));
    Future<String> paidFile() =>
        keys.mintFile(filePayload(entitlements: paidCodes));

    test('an evaluation at its expiry drops to Open Core, no grace', () async {
      clock = expiry.add(const Duration(minutes: 1));
      final controller = await started(await evaluationFile());
      expect(controller.status.activation, CruxLicenseActivation.expired);
      expect(controller.status.tier, LicenseTier.openCore);
      expect(controller.status.isEvaluation, isTrue);
      expect(controller.status.clockSetBack, isFalse);
    });

    test('a paid licence at its expiry still gets its grace', () async {
      clock = expiry.add(const Duration(minutes: 1));
      final controller = await started(await paidFile());
      expect(controller.status.activation, CruxLicenseActivation.grace);
      expect(controller.status.tier, LicenseTier.enterprise);
      expect(
        controller.status.graceEndsAt,
        expiry.add(const Duration(days: 90)),
      );
    });

    test('an evaluation before its expiry runs at its tier', () async {
      final controller = await started(await evaluationFile());
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.enterprise);
      expect(mark.marks['lic00000-0000-4000-8000-000000000001'], clock);
    });

    test('a clock set back before the high-water mark ends an evaluation, '
        'and setting it right resumes it', () async {
      final controller = await started(await evaluationFile());
      expect(controller.status.activation, CruxLicenseActivation.active);

      clock = DateTime.utc(2026, 9, 20);
      await controller.refresh();
      expect(controller.status.activation, CruxLicenseActivation.expired);
      expect(controller.status.clockSetBack, isTrue);
      expect(controller.status.tier, LicenseTier.openCore);
      expect(
        mark.marks.values.single,
        DateTime.utc(2026, 10),
        reason: 'a set-back clock never moves the mark',
      );

      clock = DateTime.utc(2026, 10, 2);
      await controller.refresh();
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.clockSetBack, isFalse);
    });

    test('the same set-back clock does not touch a paid licence', () async {
      final controller = await started(await paidFile());
      clock = DateTime.utc(2026, 9, 20);
      await controller.refresh();
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.clockSetBack, isFalse);
      expect(mark.marks, isEmpty, reason: 'a paid licence keeps no mark');
    });

    test('a small backward correction is within the tolerance', () async {
      clock = DateTime.utc(2026, 10, 1, 18);
      final controller = await started(await evaluationFile());
      clock = clock.subtract(
        kEvaluationClockTolerance - const Duration(minutes: 1),
      );
      await controller.refresh();
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.clockSetBack, isFalse);
    });

    test('a clock earlier than the file was issued ends it on the first '
        'launch, with nothing recorded yet', () async {
      clock = DateTime.utc(2026, 7);
      final controller = await started(await evaluationFile());
      expect(controller.status.activation, CruxLicenseActivation.expired);
      expect(controller.status.clockSetBack, isTrue);
    });

    test('the mark persists across controllers sharing it', () async {
      await started(await evaluationFile());
      clock = DateTime.utc(2026, 9, 15);
      final relaunched = await started(await evaluationFile());
      expect(relaunched.status.clockSetBack, isTrue);
    });
  });

  group('FileLicenseClockMark', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('crux_clock_mark_'));
    tearDown(() => dir.deleteSync(recursive: true));

    FileLicenseClockMark over() => FileLicenseClockMark(
      environment: <String, String>{'HOME': dir.path},
      operatingSystem: 'macos',
    );

    test(
      'reads nothing until advanced, then only ever moves forward',
      () async {
        final mark = over();
        expect(await mark.read(licenseId: 'lic-1'), isNull);
        await mark.advance(licenseId: 'lic-1', at: DateTime.utc(2026, 10));
        await mark.advance(licenseId: 'lic-1', at: DateTime.utc(2026, 9));
        expect(await over().read(licenseId: 'lic-1'), DateTime.utc(2026, 10));
        expect(await over().read(licenseId: 'lic-2'), isNull);
      },
    );

    test('a malformed document reads as empty and is replaced', () async {
      File('${dir.path}/Library/Application Support/crux/license/clock.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      final mark = over();
      expect(await mark.read(licenseId: 'lic-1'), isNull);
      await mark.advance(licenseId: 'lic-1', at: DateTime.utc(2026, 10));
      expect(await mark.read(licenseId: 'lic-1'), DateTime.utc(2026, 10));
    });
  });

  group('FileLicenseNoticeMemory', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('crux_notices_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('remembers a shown notice across instances', () async {
      FileLicenseNoticeMemory over() => FileLicenseNoticeMemory(
        environment: <String, String>{'HOME': dir.path},
        operatingSystem: 'macos',
        now: () => DateTime.utc(2027, 2),
      );
      expect(await over().wasShown('a'), isFalse);
      await over().markShown('a');
      expect(await over().wasShown('a'), isTrue);
      expect(await over().wasShown('b'), isFalse);
    });

    test('forgets entries past the retention when it next writes', () async {
      var now = DateTime.utc(2027, 2);
      FileLicenseNoticeMemory over() => FileLicenseNoticeMemory(
        environment: <String, String>{'HOME': dir.path},
        operatingSystem: 'macos',
        now: () => now,
      );
      await over().markShown('old');
      now = now
          .add(FileLicenseNoticeMemory.retention)
          .add(
            const Duration(days: 1),
          );
      await over().markShown('new');
      expect(await over().wasShown('old'), isFalse);
      expect(await over().wasShown('new'), isTrue);
    });
  });
}

class _Store implements LicenseStore {
  _Store({this.credential});

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

  @override
  Future<String?> readIssuerSnapshot() async => issuerSnapshot;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async =>
      issuerSnapshot = snapshot;

  @override
  Future<void> writeMachineId(String? machineId) async =>
      this.machineId = machineId;
}

/// An issuer that never answers: the socket never opens.
class _Unreachable extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future<http.StreamedResponse>.error(const SocketException('offline'));
}
