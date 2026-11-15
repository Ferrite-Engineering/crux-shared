// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/edu_fixtures.dart';
import 'support/license_fixtures.dart';

/// The controller with a self-issued educational licence, and the exchange
/// that turns a Keygen educational key into one.
///
/// The properties guarded: an educational licence never reaches Keygen at
/// all; a Keygen educational key is exchanged once, on the check-in, and
/// replaced only by a credential that validates here as EDU; and every
/// other outcome keeps the key the user already has.
void main() {
  const eduPolicyId = 'p0000000-0000-4000-8000-0000000000ed';
  const exchangeUrl = 'https://commerce.example.test/edu/exchange';
  final duringTerm = DateTime.utc(2026, 9);

  late TestIssuerKeys keygenKeys;
  late TestIssuerKeys eduKeys;
  late TestIssuerKeys strangerKeys;
  late CruxLicenseValidator validator;

  setUpAll(() async {
    keygenKeys = await TestIssuerKeys.fromSeed(7);
    eduKeys = await TestIssuerKeys.fromSeed(9);
    strangerKeys = await TestIssuerKeys.fromSeed(11);
    validator = CruxLicenseValidator(
      product: CruxProduct.waveCrux,
      issuers: <LicenseIssuer>[
        KeygenLicenseIssuer(
          accountId: testAccountId,
          verifyKey: keygenKeys.verifyKey,
          policies: const <String, KeygenPolicy>{
            ...testPolicies,
            eduPolicyId: KeygenPolicy(
              id: eduPolicyId,
              name: 'edu-annual',
              tier: LicenseTier.edu,
              products: <CruxProduct>{
                CruxProduct.waveCrux,
                CruxProduct.netCrux,
                CruxProduct.lintCrux,
                CruxProduct.simCrux,
              },
              duration: Duration(seconds: 31622400),
            ),
          },
        ),
        EduLicenseIssuer(keyId: 'edu-test', verifyKey: eduKeys.verifyKey),
      ],
    );
  });

  CruxLicenseController controllerOver(
    _Store store,
    _Wire wire, {
    Uri? educationalExchangeUrl,
    MachineReleaseMarker releaseMarker = const NoMachineReleaseMarker(),
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keygenKeys.verifyKey,
      client: wire,
    ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/buy'),
    manageUrl: Uri.parse('https://example.test/manage'),
    educationalExchangeUrl: educationalExchangeUrl ?? Uri.parse(exchangeUrl),
    releaseMarker: releaseMarker,
    fallbackFile: _noFallbackFile,
    now: () => duringTerm,
  );

  Future<String> keygenEduKey() => keygenKeys.mintKey(
    keyPayload(policy: eduPolicyId, expiry: '2027-07-01T00:00:00.000Z'),
  );

  String exchangedCredential({TestIssuerKeys? signer}) => mintEdu(
    signer ?? eduKeys,
    eduPayload(
      id: 'edu00000-0000-4000-8000-0000000000ex',
      exp: '2027-07-01T00:00:00Z',
      src: 'exchange',
    ),
  );

  group('an educational licence never reaches Keygen', () {
    test('start, refresh, activate and remove make no call at all', () async {
      final credential = mintEdu(eduKeys, eduPayload());
      final wire = _Wire((_) => fail('nothing may be sent'));
      final store = _Store(credential: credential);
      final marker = InMemoryMachineReleaseMarker();
      final controller = controllerOver(store, wire, releaseMarker: marker);
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.edu);
      expect(controller.status.grant!.issuerId, kEduLicenseIssuerId);
      expect(controller.status.grant!.email, 'student@example.edu');

      final refreshed = await controller.refresh();
      expect(
        refreshed.isOk,
        isTrue,
        reason: 'there is no issuer to be offline from',
      );

      final activated = await controller.activate(credential);
      expect(activated.isOk, isTrue);
      expect(controller.status.tier, LicenseTier.edu);
      expect(store.machineId, isNull, reason: 'no machine was registered');

      final removed = await controller.deactivateThisMachine();
      expect(removed.isOk, isTrue);
      expect(store.credential, isNull);
      expect(controller.status.activation, CruxLicenseActivation.openCore);
      expect(
        marker.released,
        isEmpty,
        reason: 'it holds no seat, so siblings have nothing to honour',
      );

      expect(wire.requests, isEmpty);
    });

    test('a stale Keygen machine id does not bring Keygen back', () async {
      final wire = _Wire((_) => fail('nothing may be sent'));
      final store = _Store(
        credential: mintEdu(eduKeys, eduPayload()),
        machineId: 'mach-old',
      );
      final controller = controllerOver(store, wire);
      addTearDown(controller.dispose);

      await controller.start();
      await controller.refresh();
      await controller.deactivateThisMachine();

      expect(wire.requests, isEmpty);
    });
  });

  group('exchanging a Keygen educational key', () {
    test('a 200 with an EDU credential replaces the key', () async {
      final replacement = exchangedCredential();
      final wire = _Wire(
        (request) => _json(<String, Object?>{'credential': replacement}),
      );
      final store = _Store(credential: await keygenEduKey())
        ..machineId = 'mach-keygen'
        ..issuerSnapshot = '{}';
      final key = store.credential!;
      final controller = controllerOver(store, wire);
      addTearDown(controller.dispose);

      final result = await controller.refresh();

      expect(result.isOk, isTrue);
      expect(wire.requests, hasLength(1), reason: 'the exchange, nothing else');
      final request = wire.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), exchangeUrl);
      expect(jsonDecode(request.body), <String, Object?>{
        'key': key,
        'accepts': <String>['edu-v1'],
      });

      expect(store.credential, replacement);
      expect(store.machineId, isNull);
      expect(store.issuerSnapshot, isNull);
      expect(controller.status.tier, LicenseTier.edu);
      expect(controller.status.grant!.issuerId, kEduLicenseIssuerId);
      expect(controller.status.grant!.expiry, DateTime.utc(2027, 7));

      // And from then on, nothing is sent anywhere.
      await controller.refresh();
      expect(wire.requests, hasLength(1));
    });

    for (final status in <int>[400, 404, 429, 500, 503]) {
      test('HTTP $status keeps the key, and is not retried', () async {
        final wire = _Wire(
          (request) => request.url.toString() == exchangeUrl
              ? _json(<String, Object?>{'error': 'no'}, status: status)
              : throw const _Unreachable(),
        );
        final store = _Store(credential: await keygenEduKey());
        final key = store.credential;
        final controller = controllerOver(store, wire);
        addTearDown(controller.dispose);

        await controller.refresh();
        await controller.refresh();

        expect(store.credential, key);
        expect(controller.status.tier, LicenseTier.edu);
        expect(controller.status.grant!.issuerId, 'keygen');
        expect(
          wire.requests.where((r) => r.url.toString() == exchangeUrl),
          hasLength(1),
          reason: 'one attempt per process',
        );
        expect(
          wire.requests.where((r) => r.url.toString() != exchangeUrl),
          isNotEmpty,
          reason: 'the ordinary Keygen check still runs',
        );
      });
    }

    test('an unreachable backend keeps the key', () async {
      final wire = _Wire((_) => throw const _Unreachable());
      final store = _Store(credential: await keygenEduKey());
      final key = store.credential;
      final controller = controllerOver(store, wire);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(store.credential, key);
      expect(controller.status.tier, LicenseTier.edu);
    });

    final unusable = <String, Future<String> Function()>{
      'signed by an untrusted key': () async =>
          exchangedCredential(signer: strangerKeys),
      'not a credential at all': () async => 'edu/garbage',
      'a Keygen key, even an EDU one': () =>
          keygenKeys.mintKey(keyPayload(policy: eduPolicyId)),
      'a paid Keygen key': () => keygenKeys.mintKey(keyPayload()),
      'an expired educational licence': () async => mintEdu(
        eduKeys,
        eduPayload(iat: '2025-01-01T00:00:00Z', exp: '2026-01-01T00:00:00Z'),
      ),
      'an educational licence for other products': () async => mintEdu(
        eduKeys,
        eduPayload(products: const <String>['netcrux']),
      ),
    };
    for (final MapEntry(key: name, value: answer) in unusable.entries) {
      test('a 200 carrying $name keeps the key', () async {
        final returned = await answer();
        final wire = _Wire(
          (request) => request.url.toString() == exchangeUrl
              ? _json(<String, Object?>{'credential': returned})
              : throw const _Unreachable(),
        );
        final store = _Store(credential: await keygenEduKey());
        final key = store.credential;
        final controller = controllerOver(store, wire);
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(store.credential, key);
        expect(controller.status.tier, LicenseTier.edu);
        expect(controller.status.grant!.issuerId, 'keygen');
      });
    }

    test(
      'a store that will not take the new credential keeps the key',
      () async {
        final wire = _Wire(
          (request) => request.url.toString() == exchangeUrl
              ? _json(<String, Object?>{'credential': exchangedCredential()})
              : throw const _Unreachable(),
        );
        final store = _Store(credential: await keygenEduKey())
          ..refuseWrites = true;
        final key = store.credential;
        final controller = controllerOver(store, wire);
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(store.credential, key);
        expect(controller.status.tier, LicenseTier.edu);
      },
    );

    test('a key that is not EDU is never offered for exchange', () async {
      final wire = _Wire((_) => throw const _Unreachable());
      final store = _Store(credential: await keygenKeys.mintKey(keyPayload()));
      final controller = controllerOver(store, wire);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(wire.requests, isNotEmpty);
      expect(
        wire.requests.where((r) => r.url.path.endsWith('/edu/exchange')),
        isEmpty,
      );
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('nothing is exchanged before the check-in', () async {
      final wire = _Wire((_) => throw const _Unreachable());
      final store = _Store(credential: await keygenEduKey())
        ..lastCheck = duringTerm;
      final controller = controllerOver(store, wire);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.tier, LicenseTier.edu);
      expect(wire.requests, isEmpty, reason: 'the check was not due');
    });
  });

  group('where the exchange is sent', () {
    Future<Uri> exchangedAt(CruxLicenseController Function(_Wire) make) async {
      final wire = _Wire((_) => throw const _Unreachable());
      final controller = make(wire);
      addTearDown(controller.dispose);
      await controller.refresh();
      return wire.requests.first.url;
    }

    test('by default, the commerce backend', () async {
      final store = _Store(credential: await keygenEduKey());
      final url = await exchangedAt(
        (wire) => CruxLicenseController(
          product: CruxProduct.waveCrux,
          validator: validator,
          store: store,
          client: KeygenLicenseClient(
            accountId: testAccountId,
            verifyKey: keygenKeys.verifyKey,
            client: wire,
          ),
          machine: const LicenseMachineIdentity(name: 'm', platform: 'macos'),
          openUrl: (_) async {},
          purchaseUrl: Uri.parse('https://example.test/buy'),
          fallbackFile: _noFallbackFile,
          now: () => duringTerm,
        ),
      );
      expect(url.toString(), 'https://commerce.edacrux.app/edu/exchange');
    });

    test('beside a configured educational request endpoint', () async {
      final store = _Store(credential: await keygenEduKey());
      final url = await exchangedAt(
        (wire) => CruxLicenseController(
          product: CruxProduct.waveCrux,
          validator: validator,
          store: store,
          client: KeygenLicenseClient(
            accountId: testAccountId,
            verifyKey: keygenKeys.verifyKey,
            client: wire,
          ),
          machine: const LicenseMachineIdentity(name: 'm', platform: 'macos'),
          openUrl: (_) async {},
          purchaseUrl: Uri.parse('https://example.test/buy'),
          // The argument is deprecated; overlays that still pass it keep
          // their origin for the exchange too.
          // ignore: deprecated_member_use_from_same_package
          educationalRequestUrl: Uri.parse(
            'https://staging.example.test/edu/request?x=1',
          ),
          fallbackFile: _noFallbackFile,
          now: () => duringTerm,
        ),
      );
      expect(url.toString(), 'https://staging.example.test/edu/exchange');
    });
  });

  group('the client', () {
    test('an educational request says it reads edu-v1', () async {
      final wire = _Wire(
        (_) => _json(<String, Object?>{'ok': true}, status: 202),
      );
      final client = KeygenLicenseClient(
        accountId: testAccountId,
        verifyKey: keygenKeys.verifyKey,
        client: wire,
      );
      addTearDown(client.close);

      final result = await client.requestEducationalLicense(
        endpoint: Uri.parse('https://commerce.example.test/edu/request'),
        email: 'student@example.edu',
      );

      expect(result.isOk, isTrue);
      expect(jsonDecode(wire.requests.single.body), <String, Object?>{
        'email': 'student@example.edu',
        'accepts': <String>['edu-v1'],
      });
    });

    test('an exchange reads the credential from a 200 only', () async {
      Future<String?> exchange(http.StreamedResponse Function() answer) {
        final client = KeygenLicenseClient(
          accountId: testAccountId,
          verifyKey: keygenKeys.verifyKey,
          client: _Wire((_) => answer()),
        );
        addTearDown(client.close);
        return client.exchangeEducationalLicense(
          endpoint: Uri.parse(exchangeUrl),
          key: 'key/abc.def',
        );
      }

      expect(
        await exchange(() => _json(<String, Object?>{'credential': 'edu/x'})),
        'edu/x',
      );
      expect(
        await exchange(
          () => _json(<String, Object?>{'credential': 'edu/x'}, status: 201),
        ),
        isNull,
      );
      expect(await exchange(() => _json(<String, Object?>{})), isNull);
      expect(
        await exchange(() => _json(<String, Object?>{'credential': 7})),
        isNull,
      );
      expect(
        await exchange(
          () => http.StreamedResponse(
            Stream<List<int>>.value(utf8.encode('<html>')),
            200,
          ),
        ),
        isNull,
      );
    });
  });
}

/// A fallback file that cannot be resolved, so nothing under test writes to
/// the real licence directory and a refused store write stays refused.
final LicenseFallbackFile _noFallbackFile = LicenseFallbackFile(
  () => throw StateError('no licence directory under test'),
);

http.StreamedResponse _json(Map<String, Object?> body, {int status = 200}) =>
    http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );

/// Records every request, then answers it with [_answer]. A test that wants
/// no request at all asserts [requests] is empty: a failure thrown inside a
/// send is caught by the client as "unreachable", so throwing alone would
/// prove nothing.
class _Wire extends http.BaseClient {
  _Wire(this._answer);

  final http.StreamedResponse Function(http.Request request) _answer;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final recorded = request as http.Request;
    requests.add(recorded);
    return _answer(recorded);
  }
}

class _Unreachable implements Exception {
  const _Unreachable();
}

class _Store implements LicenseStore {
  _Store({this.credential, this.machineId});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String? issuerSnapshot;
  bool refuseWrites = false;

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
  Future<void> writeCredential(String credential) async {
    if (refuseWrites) throw StateError('store refused the write');
    this.credential = credential;
  }

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
