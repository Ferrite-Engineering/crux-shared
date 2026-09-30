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

import 'support/ed25519_sign.dart';
import 'support/license_fixtures.dart';

/// A licence the organization deploys in its policy file, taken the whole way
/// a managed seat takes it: a `.crux-policy.json` on disk, signed or not, the
/// organization's key beside it or not, through the real [PolicyLoader], into
/// [DayOnePolicy], and through [applyPolicyLicense] into a real
/// [CruxLicenseController] whose issuer is never reachable.
///
/// This is the activation path of an air-gapped Enterprise deployment, and it
/// had no test at all: every product calls [applyPolicyLicense] at startup and
/// nothing proved what it does.
///
/// Two properties matter above the rest:
///
/// - **Licence files parse at every tier.** A file arriving through the policy
///   is the same credential a user could paste, and it resolves whatever tier
///   it carries — Pro, EDU and Enterprise alike. Enterprise buys self-serve
///   issuance, which is a commercial matter, not a code path.
/// - **A key already in use wins.** A machine that is already licensed is
///   never re-activated from the policy, which would be a network call on
///   every launch of an air-gapped seat and would replace a user's own key.
void main() {
  late TestIssuerKeys issuer;
  late CruxLicenseValidator validator;
  late TestEd25519KeyPair orgKey;
  late Directory root;

  /// A moment inside every fixture credential's term.
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
    orgKey = TestEd25519KeyPair.fromSeed(List<int>.filled(32, 42));
  });

  setUp(() => root = Directory.systemTemp.createTempSync('crux_policy_lic_'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Every attempt the controller makes to reach the issuer. An air-gapped
  /// seat gets no refusal from anyone; the socket never opens.
  late int attempts;
  setUp(() => attempts = 0);

  // --- the deployment ----------------------------------------------------

  /// The administrator-only directory a policy file is installed in.
  String wellKnownDir() {
    final dir = Directory(p.join(root.path, 'EDACrux'))
      ..createSync(recursive: true);
    return dir.path;
  }

  String wellKnownPath() => p.join(wellKnownDir(), PolicyLoader.policyFileName);

  /// Write [policy] to [path], signed with [signer] when given.
  void writePolicy(
    String path,
    Map<String, Object?> policy, {
    TestEd25519KeyPair? signer,
  }) {
    final body = <String, Object?>{...policy};
    if (signer != null) {
      final payload = PolicyLoader.canonicalPayload(body);
      body['signature'] = base64.encode(signer.sign(utf8.encode(payload)));
    }
    File(path).writeAsStringSync(jsonEncode(body));
  }

  /// Install the organization's public key beside the well-known policy path.
  void installOrgKey() {
    File(
      p.join(wellKnownDir(), kPolicyPublicKeyFileName),
    ).writeAsStringSync('${base64.encode(orgKey.publicKey)}\n');
  }

  /// What a product sees at startup: the loader it would run, pointed at this
  /// test's directory instead of the machine's, with an empty environment so
  /// the developer's own `CRUX_POLICY` cannot leak in.
  PolicyLoadResult load({Map<String, String> environment = const {}}) =>
      PolicyLoader(
        wellKnownPath: wellKnownPath(),
        environment: environment,
      ).load();

  Map<String, Object?> policyWithLicense(Map<String, Object?> license) =>
      <String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{'license': license},
      };

  // --- the machine -------------------------------------------------------

  Future<CruxLicenseController> startedController(_Store store) async {
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
    // `start` fires its phone-home unawaited. Let it land, so an attempt it
    // makes is never counted against the call under test.
    await pumpEventQueue();
    return controller;
  }

  /// The `readFile` every product passes: the file's text, or `null` when it
  /// cannot be read. Records what it was asked for.
  final reads = <String>[];
  setUp(reads.clear);
  Future<String?> readFile(String path) async {
    reads.add(path);
    try {
      return await File(path).readAsString();
    } on Object {
      return null;
    }
  }

  Future<bool> apply(CruxLicenseController controller, PolicyLoadResult r) =>
      applyPolicyLicense(
        controller: controller,
        policy: DayOnePolicy.of(r.document),
        readFile: readFile,
      );

  /// A licence file on the organization's share, returning its path.
  Future<String> licenceFileOnShare({
    List<String> entitlements = const <String>['TIER_PRO', 'WAVECRUX'],
  }) async {
    final share = Directory(p.join(root.path, 'share'))
      ..createSync(recursive: true);
    final path = p.join(share.path, 'seat.lic');
    File(path).writeAsStringSync(
      await issuer.mintFile(filePayload(entitlements: entitlements)),
    );
    return path;
  }

  group('unsigned, at the well-known path', () {
    test(
      'an inline key licenses the seat with the issuer unreachable',
      () async {
        final key = await issuer.mintKey(keyPayload());
        writePolicy(wellKnownPath(), policyWithLicense({'key': key}));
        final store = _Store();
        final controller = await startedController(store);

        final loaded = load();
        expect(loaded.wasLoaded, isTrue);
        expect(await apply(controller, loaded), isTrue);

        expect(controller.status.tier, LicenseTier.pro);
        expect(controller.status.activation, CruxLicenseActivation.active);
        expect(store.credential, key);
        expect(reads, isEmpty, reason: 'an inline key reads no file');
        expect(
          attempts,
          greaterThan(0),
          reason:
              'it tried the issuer, and being refused by the network is fine',
        );
      },
    );

    test('a file reference is read from the share and activated', () async {
      final path = await licenceFileOnShare();
      writePolicy(wellKnownPath(), policyWithLicense({'file': path}));
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isTrue);

      expect(reads, <String>[path], reason: 'the path the policy named');
      expect(controller.status.tier, LicenseTier.pro);
      expect(store.credential, contains('BEGIN LICENSE FILE'));
    });

    test('licence files resolve at every tier — there is no gate', () async {
      for (final (code, tier) in const <(String, LicenseTier)>[
        ('TIER_PRO', LicenseTier.pro),
        ('TIER_EDU', LicenseTier.edu),
        ('TIER_ENTERPRISE', LicenseTier.enterprise),
      ]) {
        final path = await licenceFileOnShare(
          entitlements: <String>[code, 'WAVECRUX'],
        );
        writePolicy(wellKnownPath(), policyWithLicense({'file': path}));
        final controller = await startedController(_Store());

        expect(await apply(controller, load()), isTrue, reason: code);
        expect(controller.status.tier, tier, reason: code);
      }
    });

    test('a machine file resolves only on the machine it names', () async {
      final share = Directory(p.join(root.path, 'share'))..createSync();
      final path = p.join(share.path, 'lab-07.lic');
      File(path).writeAsStringSync(
        await issuer.mintMachineFile(
          machineFilePayload(
            fingerprint: 'fp-lab-07',
            policy: testSuiteEnterprisePolicyId,
            entitlements: const <String>['TIER_ENTERPRISE', 'WAVECRUX'],
          ),
        ),
      );
      writePolicy(wellKnownPath(), policyWithLicense({'file': path}));

      final here = _Store(fingerprint: 'fp-lab-07');
      final ours = await startedController(here);
      expect(await apply(ours, load()), isTrue);
      expect(ours.status.tier, LicenseTier.enterprise);

      // The same policy, the same share, another workstation.
      final elsewhere = _Store(fingerprint: 'fp-lab-08');
      final theirs = await startedController(elsewhere);
      expect(await apply(theirs, load()), isFalse);
      expect(theirs.status.tier, LicenseTier.openCore);
      expect(
        elsewhere.credential,
        isNull,
        reason: 'a refused credential is not stored half-way',
      );
    });
  });

  group('signed', () {
    test('verified against the installed key, the licence applies', () async {
      installOrgKey();
      final key = await issuer.mintKey(
        keyPayload(policy: testSuiteEnterprisePolicyId),
      );
      writePolicy(
        wellKnownPath(),
        policyWithLicense({'key': key}),
        signer: orgKey,
      );
      final controller = await startedController(_Store());

      final loaded = load();
      expect(loaded.signed, isTrue);
      expect(loaded.keyStatus, PolicyKeyStatus.configured);
      expect(await apply(controller, loaded), isTrue);
      expect(controller.status.tier, LicenseTier.enterprise);
    });

    test('from CRUX_POLICY on a share, verified, it applies too', () async {
      // The deployment that most needs the signature: a file on a network
      // share an unprivileged process can point at.
      installOrgKey();
      final elsewhere = p.join(root.path, 'share-policy.json');
      writePolicy(
        elsewhere,
        policyWithLicense({'key': await issuer.mintKey(keyPayload())}),
        signer: orgKey,
      );
      final controller = await startedController(_Store());

      final loaded = load(environment: {'CRUX_POLICY': elsewhere});
      expect(loaded.discovery, PolicyDiscovery.environmentVariable);
      expect(await apply(controller, loaded), isTrue);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('with no key installed, nothing from the file is honoured', () async {
      final path = await licenceFileOnShare();
      writePolicy(
        wellKnownPath(),
        policyWithLicense({'file': path}),
        signer: orgKey,
      );
      final store = _Store();
      final controller = await startedController(store);

      final loaded = load();
      expect(loaded.rejection, PolicyRejection.noPublicKey);
      expect(await apply(controller, loaded), isFalse);

      expect(reads, isEmpty, reason: 'a refused file names no path we read');
      expect(store.credential, isNull);
      expect(controller.status.tier, LicenseTier.openCore);
    });

    test('a licence swapped in after signing is refused', () async {
      // The attack the signature exists for: someone who can write the share
      // replaces the licence the administrator signed.
      installOrgKey();
      final signed = policyWithLicense({
        'key': await issuer.mintKey(keyPayload()),
      });
      final payload = PolicyLoader.canonicalPayload(signed);
      final tampered = policyWithLicense({
        'key': await issuer.mintKey(
          keyPayload(policy: testSuiteEnterprisePolicyId),
        ),
      })..['signature'] = base64.encode(orgKey.sign(utf8.encode(payload)));
      File(wellKnownPath()).writeAsStringSync(jsonEncode(tampered));
      final store = _Store();
      final controller = await startedController(store);

      final loaded = load();
      expect(loaded.rejection, PolicyRejection.badSignature);
      expect(await apply(controller, loaded), isFalse);
      expect(store.credential, isNull);
      expect(controller.status.tier, LicenseTier.openCore);
    });
  });

  group('unsigned, outside the trusted path', () {
    test('a CRUX_POLICY file licenses nobody', () async {
      // An unprivileged process can set CRUX_POLICY, so an unsigned file it
      // names is not an administrator's instruction — whether or not a key
      // is installed.
      installOrgKey();
      final elsewhere = p.join(root.path, 'mine.json');
      writePolicy(
        elsewhere,
        policyWithLicense({'key': await issuer.mintKey(keyPayload())}),
      );
      final store = _Store();
      final controller = await startedController(store);

      final loaded = load(environment: {'CRUX_POLICY': elsewhere});
      expect(loaded.rejection, PolicyRejection.untrustedUnsigned);
      expect(await apply(controller, loaded), isFalse);
      expect(store.credential, isNull);
    });
  });

  group('what applyPolicyLicense itself decides', () {
    test('a policy with no licence does nothing', () async {
      writePolicy(wellKnownPath(), <String, Object?>{
        'schema': 1,
        'suite': <String, Object?>{'telemetry': 'deny'},
      });
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isFalse);
      expect(reads, isEmpty);
      expect(store.credential, isNull);
      expect(attempts, 0, reason: 'nothing to activate, nothing to ask');
    });

    test('a key already in use wins over the policy', () async {
      // A user whose own key predates the deployment keeps it. The policy
      // offers a different licence — Enterprise, even — and is not applied.
      final own = await issuer.mintKey(keyPayload());
      final path = await licenceFileOnShare(
        entitlements: const <String>['TIER_ENTERPRISE', 'WAVECRUX'],
      );
      writePolicy(wellKnownPath(), policyWithLicense({'file': path}));
      final store = _Store(credential: own);
      final controller = await startedController(store);
      expect(controller.status.tier, LicenseTier.pro);
      final before = attempts;

      expect(await apply(controller, load()), isFalse);

      expect(store.credential, own);
      expect(controller.status.tier, LicenseTier.pro);
      expect(reads, isEmpty, reason: 'the share is not even read');
      expect(attempts, before, reason: 'and the issuer is not asked');
    });

    test('the second launch of a licensed seat is silent', () async {
      // An air-gapped seat must not reach for the issuer on every launch
      // because the policy still names a licence.
      final key = await issuer.mintKey(keyPayload());
      writePolicy(wellKnownPath(), policyWithLicense({'key': key}));
      final store = _Store();

      final first = await startedController(store);
      expect(await apply(first, load()), isTrue);
      await first.dispose();

      final second = await startedController(store);
      final before = attempts;
      expect(await apply(second, load()), isFalse);
      expect(attempts, before);
      expect(second.status.tier, LicenseTier.pro);
    });

    test('a file that is not there yet is not an activation', () async {
      // The share is not mounted, or the licence has not been copied to it.
      writePolicy(
        wellKnownPath(),
        policyWithLicense({'file': p.join(root.path, 'absent', 'seat.lic')}),
      );
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isFalse);
      expect(reads, hasLength(1));
      expect(store.credential, isNull);
      expect(attempts, 0);
    });

    test('an empty licence file is not an activation', () async {
      final path = p.join(root.path, 'blank.lic');
      File(path).writeAsStringSync('  \n\t\n');
      writePolicy(wellKnownPath(), policyWithLicense({'file': path}));
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isFalse);
      expect(store.credential, isNull);
    });

    test('a forged licence in a trusted policy is still refused', () async {
      // The policy vouches for where the credential came from, not for the
      // credential. It gets no exemption from the checks a pasted key faces.
      final forger = await TestIssuerKeys.fromSeed(99);
      writePolicy(
        wellKnownPath(),
        policyWithLicense({
          'key': await forger.mintKey(
            keyPayload(policy: testSuiteEnterprisePolicyId),
          ),
        }),
      );
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isFalse);
      expect(store.credential, isNull);
      expect(controller.status.tier, LicenseTier.openCore);
    });

    test('a policy naming both a key and a file is ignored whole', () async {
      // Guessing which one the administrator meant is worse than neither.
      writePolicy(
        wellKnownPath(),
        policyWithLicense({
          'key': await issuer.mintKey(keyPayload()),
          'file': await licenceFileOnShare(),
        }),
      );
      final store = _Store();
      final controller = await startedController(store);

      expect(await apply(controller, load()), isFalse);
      expect(reads, isEmpty);
      expect(store.credential, isNull);
    });
  });
}

class _Store implements LicenseStore {
  _Store({this.credential, this.fingerprint = 'fingerprint-1'});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String? issuerSnapshot;
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
  Future<void> writeCredential(String credential) async =>
      this.credential = credential;

  @override
  Future<String> readOrCreateFingerprint() async => fingerprint;

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

/// Every request fails before a byte is sent, as on a machine with no route
/// to the issuer.
class _Unreachable extends http.BaseClient {
  _Unreachable(this._onAttempt);

  final void Function() _onAttempt;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    _onAttempt();
    throw const SocketException('no route to host');
  }
}
