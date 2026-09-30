// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// The controller's action surface: the paths the panel's buttons reach.
///
/// `activate`, grace and expiry are covered in `license_controller_test.dart`.
/// This covers what is left — the offline round trip, the commerce links, the
/// educational request, and the Keygen responses each one has to survive.
void main() {
  late TestIssuerKeys keys;
  late KeygenLicenseIssuer issuer;
  late CruxLicenseValidator validator;
  final duringTerm = DateTime.utc(2026, 9);

  setUpAll(() async {
    keys = await TestIssuerKeys.fromSeed(7);
    issuer = KeygenLicenseIssuer(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      policies: testPolicies,
    );
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[issuer],
    );
  });

  final opened = <Uri>[];

  CruxLicenseController controllerOver(
    _Store store, {
    http.Client? client,
    Uri? manageUrl,
    Uri? eduUrl,
    Future<void> Function(Uri)? openUrl,
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      client: client ?? _stub((_) => throw const _Down()),
    ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: openUrl ?? (url) async => opened.add(url),
    purchaseUrl: Uri.parse('https://example.test/pricing'),
    manageUrl: manageUrl,
    educationalRequestUrl: eduUrl,
    now: () => duringTerm,
  );

  setUp(opened.clear);

  group('offline activation', () {
    test(
      'the exported request identifies the machine and nothing else',
      () async {
        final controller = controllerOver(_Store());
        addTearDown(controller.dispose);

        final result = await controller.exportOfflineRequest();
        final payload = (result as LicenseActionSucceeded).payload!;
        final doc = json.decode(payload) as Map<String, Object?>;

        expect(doc['kind'], 'crux.offline-activation-request/v1');
        expect(doc['product'], 'WAVECRUX');
        expect(doc['fingerprint'], 'fingerprint-1');
        expect(doc['machine'], 'lab-01');
        expect(doc['platform'], 'macos');
        expect(
          payload,
          isNot(contains('key/')),
          reason: 'it travels on a USB stick; it must carry no credential',
        );
      },
    );

    test('an unreadable store fails the export instead of throwing', () async {
      final controller = controllerOver(_Store(brokenFingerprint: true));
      addTearDown(controller.dispose);

      final result = await controller.exportOfflineRequest();
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.unknown,
      );
    });

    test('importing a licence file activates, offline', () async {
      // The return leg. A licence file embeds its own entitlements, which is
      // why it resolves on a machine that can never reach the issuer — the
      // client here refuses every connection.
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken(
        await keys.mintFile(filePayload()),
      );

      expect(result.isOk, isTrue);
      expect(controller.status.tier, LicenseTier.pro);
      expect(controller.status.grant!.resolvedFromEntitlements, isTrue);
      expect(store.credential, isNotNull);
    });

    test('importing junk is refused', () async {
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);

      final result = await controller.importOfflineToken('not a licence');
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.rejected,
      );
    });
  });

  group('commerce links', () {
    test('the purchase page opens', () async {
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);

      expect((await controller.openPurchasePage()).isOk, isTrue);
      expect(opened.single.toString(), contains('pricing'));
      expect(controller.supportsPurchaseLinks, isTrue);
    });

    test(
      'with no manage URL the capability is off and the call refuses',
      () async {
        final controller = controllerOver(_Store());
        addTearDown(controller.dispose);

        expect(controller.supportsManageLink, isFalse);
        expect(
          ((await controller.openManagePage()) as LicenseActionFailed).failure,
          CruxLicenseActionFailure.notSupported,
        );
        expect(opened, isEmpty);
      },
    );

    test('with a manage URL it opens', () async {
      final controller = controllerOver(
        _Store(),
        manageUrl: Uri.parse('https://example.test/account'),
      );
      addTearDown(controller.dispose);

      expect(controller.supportsManageLink, isTrue);
      expect((await controller.openManagePage()).isOk, isTrue);
      expect(opened.single.toString(), contains('account'));
    });

    test('a launcher that throws is reported, not propagated', () async {
      final controller = controllerOver(
        _Store(),
        openUrl: (_) async => throw StateError('no browser'),
      );
      addTearDown(controller.dispose);

      final result = await controller.openPurchasePage();
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.unknown,
      );
      expect(result.detail, contains('no browser'));
    });
  });

  group('the educational request', () {
    test('is unavailable without an endpoint', () async {
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);

      expect(controller.supportsEducationalRequest, isFalse);
      expect(
        ((await controller.requestEducationalLicense('a@uni.edu'))
                as LicenseActionFailed)
            .failure,
        CruxLicenseActionFailure.notSupported,
      );
    });

    test('rejects a malformed address before any network call', () async {
      final controller = controllerOver(
        _Store(),
        eduUrl: Uri.parse('https://example.test/edu/request'),
        client: _stub((_) => throw StateError('must not be called')),
      );
      addTearDown(controller.dispose);

      for (final bad in <String>['nobody', 'no@domain', '@example.com', '']) {
        final result = await controller.requestEducationalLicense(bad);
        expect(
          (result as LicenseActionFailed).failure,
          CruxLicenseActionFailure.invalidEmail,
          reason: bad,
        );
      }
    });

    test('accepts institutional addresses that are not .edu', () async {
      // .edu is a US convention. ac.uk, edu.au and uni-*.de are just as
      // institutional, and rejecting them would be a support ticket.
      final controller = controllerOver(
        _Store(),
        eduUrl: Uri.parse('https://example.test/edu/request'),
        client: _json(keys, const <String, Object?>{'ok': true}),
      );
      addTearDown(controller.dispose);

      for (final good in <String>[
        'a@cam.ac.uk',
        'b@unimelb.edu.au',
        'c@uni-bonn.de',
        'd@stanford.edu',
      ]) {
        expect(
          (await controller.requestEducationalLicense(good)).isOk,
          isTrue,
          reason: good,
        );
      }
    });

    // What the panel says next depends entirely on this flag, and the two
    // answers are not variations on a theme: one tells the applicant to go
    // and follow a link, the other tells them to wait for a person. The
    // backend distinguishes them; before this the app threw the distinction
    // away on the way past, and every reviewed applicant was told to watch
    // for a confirmation email that the backend had deliberately not sent.
    test('an address sent for review says so', () async {
      final controller = controllerOver(
        _Store(),
        eduUrl: Uri.parse('https://example.test/edu/request'),
        client: _json(keys, const <String, Object?>{
          'ok': true,
          'review': true,
        }),
      );
      addTearDown(controller.dispose);

      final result = await controller.requestEducationalLicense(
        'someone@robotics-lab.example',
      );
      expect(result.isOk, isTrue);
      expect((result as LicenseActionSucceeded).underReview, isTrue);
    });

    test('an automatic issue does not claim to be under review', () async {
      final controller = controllerOver(
        _Store(),
        eduUrl: Uri.parse('https://example.test/edu/request'),
        client: _json(keys, const <String, Object?>{'ok': true}),
      );
      addTearDown(controller.dispose);

      final result = await controller.requestEducationalLicense(
        'student@cam.ac.uk',
      );
      expect((result as LicenseActionSucceeded).underReview, isFalse);
    });

    test('the two sentences are different, and both are actionable', () {
      // A guard against "fixing" this by pointing both paths at one string.
      const s = CruxLicensePanelStringsEn();
      expect(s.licenseEduUnderReview, isNot(s.licenseEduCheckYourEmail));
      expect(
        s.licenseEduCheckYourEmail,
        contains('link'),
        reason: 'the automatic path has a link to follow',
      );
      expect(
        s.licenseEduUnderReview,
        contains('edu@ferriteengineering.com'),
        reason:
            'the reviewed path has nothing to follow, so it must say '
            'where to chase it',
      );
    });

    test('maps the endpoint failures onto sentences the panel knows', () async {
      const cases = <int, CruxLicenseActionFailure>{
        400: CruxLicenseActionFailure.invalidEmail,
        422: CruxLicenseActionFailure.invalidEmail,
        409: CruxLicenseActionFailure.alreadyRequested,
        500: CruxLicenseActionFailure.unknown,
      };
      for (final entry in cases.entries) {
        final controller = controllerOver(
          _Store(),
          eduUrl: Uri.parse('https://example.test/edu/request'),
          client: _json(
            keys,
            <String, Object?>{'error': 'nope'},
            status: entry.key,
          ),
        );
        addTearDown(controller.dispose);

        final result = await controller.requestEducationalLicense('a@uni.edu');
        expect(
          (result as LicenseActionFailed).failure,
          entry.value,
          reason: 'HTTP ${entry.key}',
        );
      }
    });

    test('an unreachable endpoint reports offline', () async {
      final controller = controllerOver(
        _Store(),
        eduUrl: Uri.parse('https://example.test/edu/request'),
        client: _stub((_) => throw const _Down()),
      );
      addTearDown(controller.dispose);

      expect(
        ((await controller.requestEducationalLicense('a@uni.edu'))
                as LicenseActionFailed)
            .failure,
        CruxLicenseActionFailure.offline,
      );
    });
  });

  group('the status stream', () {
    test('publishes every transition the panel needs to see', () async {
      final store = _Store();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      final seen = <CruxLicenseActivation>[];
      final sub = controller.statuses.listen((s) => seen.add(s.activation));
      addTearDown(sub.cancel);

      await controller.start();
      await controller.activate(await keys.mintKey(keyPayload()));
      await Future<void>.delayed(Duration.zero);

      expect(seen, contains(CruxLicenseActivation.openCore));
      expect(seen, contains(CruxLicenseActivation.active));
    });

    test('dispose stops the timer and closes the stream', () async {
      final controller = controllerOver(_Store());
      await controller.start();
      await controller.dispose();
      expect(controller.statuses.isBroadcast, isTrue);
    });
  });

  group('deactivation against the issuer', () {
    test('a machine already gone counts as success', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(
        store,
        client: _json(keys, <String, Object?>{
          'errors': <Object?>[
            <String, Object?>{'title': 'Not found', 'detail': 'not found'},
          ],
        }, status: 404),
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect((await controller.deactivateThisMachine()).isOk, isTrue);
      expect(store.credential, isNull);
    });

    test('an unrecognised refusal keeps the credential', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(
        store,
        client: _json(keys, <String, Object?>{
          'errors': <Object?>[
            <String, Object?>{'title': 'Forbidden', 'detail': 'refused'},
          ],
        }, status: 403),
      );
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.deactivateThisMachine();
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.refusedByIssuer,
      );
      expect(
        store.credential,
        isNotNull,
        reason:
            'an issuer refusal we cannot interpret is not a licence to '
            'throw the credential away',
      );
    });

    // The next two are the end states of a customer who bought and stopped,
    // and they are not hypothetical: the bodies below are what the live
    // Keygen account answers a machine deletion with, measured with a
    // throwaway licence. A cancellation suspends the licence; support
    // deleting one takes its key with it, so the call cannot even
    // authenticate. Before these, both left the customer unable to clear a
    // dead licence out of their own app — Deactivate failed for ever, and the
    // key travelled with the machine if they passed it on.
    test(
      'a suspended licence — the refunded customer — can still clear',
      () async {
        final store = _Store(
          credential: await keys.mintKey(keyPayload()),
          machineId: 'machine-1',
        );
        final controller = controllerOver(
          store,
          client: _json(keys, <String, Object?>{
            'errors': <Object?>[
              <String, Object?>{
                'title': 'Access denied',
                'detail': 'License is suspended',
                'code': 'LICENSE_SUSPENDED',
              },
            ],
          }, status: 403),
        );
        addTearDown(controller.dispose);
        await controller.start();

        expect((await controller.deactivateThisMachine()).isOk, isTrue);
        expect(store.credential, isNull);
        expect(store.machineId, isNull);
        expect(controller.status.activation, CruxLicenseActivation.openCore);
      },
    );

    test('a deleted licence — support cleanup — can still clear', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(
        store,
        client: _json(keys, <String, Object?>{
          'errors': <Object?>[
            <String, Object?>{
              'title': 'Unauthorized',
              'detail': 'You must be authenticated to complete the request',
              'code': 'LICENSE_INVALID',
            },
          ],
        }, status: 401),
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect((await controller.deactivateThisMachine()).isOk, isTrue);
      expect(store.credential, isNull);
    });

    test('with no credential it simply clears', () async {
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);

      expect((await controller.deactivateThisMachine()).isOk, isTrue);
    });
  });

  group('activation against the issuer', () {
    test('a machine already registered is success, not an error', () async {
      final controller = controllerOver(
        _Store(),
        client: _json(keys, <String, Object?>{
          'errors': <Object?>[
            <String, Object?>{
              'title': 'Unprocessable',
              'detail': 'fingerprint has already been taken',
            },
          ],
        }, status: 422),
      );
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );
      expect(result.isOk, isTrue);
    });

    test('refresh with no credential is a no-op success', () async {
      final controller = controllerOver(_Store());
      addTearDown(controller.dispose);
      expect((await controller.refresh()).isOk, isTrue);
    });

    test('a 204 with an empty body is handled', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'm-1',
      );
      final controller = controllerOver(
        store,
        client: _stub(
          (_) => http.StreamedResponse(const Stream<List<int>>.empty(), 204),
        ),
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect((await controller.deactivateThisMachine()).isOk, isTrue);
    });
  });
}

class _Store implements LicenseStore {
  _Store({this.credential, this.machineId, this.brokenFingerprint = false});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  final bool brokenFingerprint;

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
  Future<String> readOrCreateFingerprint() async =>
      brokenFingerprint ? throw StateError('keychain locked') : 'fingerprint-1';

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

class _Down implements Exception {
  const _Down();
}

http.Client _stub(http.StreamedResponse Function(http.BaseRequest) answer) =>
    _StubClient(answer);

/// One signed JSON answer for every call: what the issuer's answers look like
/// to the client, which refuses a validate answer that carries no signature.
http.Client _json(
  TestIssuerKeys keys,
  Map<String, Object?> body, {
  int status = 200,
}) => signedJsonClient(keys, body, status: status);

class _StubClient extends http.BaseClient {
  _StubClient(this._answer);

  final http.StreamedResponse Function(http.BaseRequest request) _answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _answer(request);
}
