// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// The controller under a fingerprint the whole machine shares.
///
/// Three things follow from sharing it, and each has a way to go wrong that
/// costs a seat or undoes a user's action: a sibling product may have
/// registered the machine first, so "already activated" is the normal answer
/// and the id has to be looked up; a machine this product registered under
/// its old per-product fingerprint is an orphan the issuer still counts, and
/// has to be released before the machine is registered again; and a
/// deactivation made in one product must be honoured by the others before
/// their next check-in re-registers the machine behind the user's back.
void main() {
  late TestIssuerKeys keys;
  late CruxLicenseValidator validator;
  final duringTerm = DateTime.utc(2026, 9);
  const licenceId = 'lic00000-0000-4000-8000-000000000001';

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

  CruxLicenseController controllerOver(
    _Store store, {
    http.Client? client,
    MachineReleaseMarker? marker,
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      client: client ?? stubClient((_) => throw const _Down()),
    ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/buy'),
    now: () => duringTerm,
    releaseMarker: marker ?? const NoMachineReleaseMarker(),
  );

  group('a sibling product registered the machine first', () {
    test('activation answered "already activated" looks the id up and '
        'keeps it', () async {
      final store = _Store();
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..register = _taken
        ..registerStatus = 422
        ..lookup = _machine('machine-7');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(result.isOk, isTrue);
      expect(issuer.calls, contains('GET machines/fingerprint-1'));
      expect(store.machineId, 'machine-7');
      expect(controller.status.tier, LicenseTier.pro);
    });

    test(
      'the same at a check-in that finds the machine unregistered',
      () async {
        final store = _Store(credential: await keys.mintKey(keyPayload()));
        final issuer = _Issuer(keys)
          ..validate = _validated('NO_MACHINE')
          ..register = _taken
          ..registerStatus = 422
          ..lookup = _machine('machine-7')
          ..onRegister = (stub) => stub.validate = _validated('VALID');
        final controller = controllerOver(store, client: issuer.client);
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(issuer.calls, contains('GET machines/fingerprint-1'));
        expect(store.machineId, 'machine-7');
        expect(controller.status.activation, CruxLicenseActivation.active);
      },
    );

    test('an id that cannot be found changes nothing', () async {
      final store = _Store();
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..register = _taken
        ..registerStatus = 422;
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(result.isOk, isTrue);
      expect(store.machineId, isNull);
      expect(controller.status.tier, LicenseTier.pro);
    });
  });

  group('the orphan a shared fingerprint leaves behind', () {
    test('a mismatch while holding an id releases that machine first, '
        'then registers under the fingerprint it has now', () async {
      // This product registered under its old per-product fingerprint; the
      // shared one adopted a sibling's value. The issuer counts the old
      // machine, and registering afresh would take a second seat for the
      // same computer.
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-old',
      );
      final issuer = _Issuer(keys)
        ..validate = _validated('FINGERPRINT_SCOPE_MISMATCH')
        ..register = _machine('machine-new')
        ..onRegister = (stub) => stub.validate = _validated('VALID');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(
        issuer.calls,
        containsAllInOrder(<String>[
          'POST licenses/actions/validate-key',
          'DELETE machines/machine-old',
          'POST machines',
        ]),
      );
      expect(store.machineId, 'machine-new');
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('an orphan that will not go is forgotten and registration '
        'proceeds', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-old',
      );
      final issuer = _Issuer(keys)
        ..validate = _validated('FINGERPRINT_SCOPE_MISMATCH')
        ..register = _machine('machine-new')
        ..delete = _forbidden
        ..deleteStatus = 403
        ..onRegister = (stub) => stub.validate = _validated('VALID');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(issuer.calls, contains('DELETE machines/machine-old'));
      expect(issuer.calls, contains('POST machines'));
      expect(store.machineId, 'machine-new');
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('no machine at all releases nothing: there is no orphan', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-old',
      );
      final issuer = _Issuer(keys)
        ..validate = _validated('NO_MACHINE')
        ..register = _machine('machine-new')
        ..onRegister = (stub) => stub.validate = _validated('VALID');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(
        issuer.calls.where((c) => c.startsWith('DELETE')),
        isEmpty,
        reason:
            'the licence holds no machine; the held id is stale, not '
            'an orphan the issuer counts',
      );
      expect(store.machineId, 'machine-new');
    });
  });

  group('deactivating this machine, suite-wide', () {
    test('releases by fingerprint, not by the id this product holds', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final marker = InMemoryMachineReleaseMarker();
      final issuer = _Issuer(keys);
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.deactivateThisMachine();

      expect(result.isOk, isTrue);
      expect(issuer.calls, contains('DELETE machines/fingerprint-1'));
      expect(issuer.calls, isNot(contains('DELETE machines/machine-1')));
      expect(store.credential, isNull);
      expect(controller.status.activation, CruxLicenseActivation.openCore);
      expect(
        marker.released,
        <String, String>{licenceId: 'fingerprint-1'},
        reason: 'the other products on this machine are told',
      );
    });

    test('works from a product that never registered the machine', () async {
      // No id held: a sibling registered the machine. The release still has
      // to work from here — "deactivate this machine" means the machine.
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker();
      final issuer = _Issuer(keys);
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);

      final result = await controller.deactivateThisMachine();

      expect(result.isOk, isTrue);
      expect(issuer.calls, contains('DELETE machines/fingerprint-1'));
      expect(marker.released, <String, String>{licenceId: 'fingerprint-1'});
      expect(store.credential, isNull);
    });

    test('falls back to the held id when the fingerprint is refused', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final marker = InMemoryMachineReleaseMarker();
      final issuer = _Issuer(keys)
        ..deleteFor = (machine) => machine == 'fingerprint-1'
            ? const _Answer(_forbidden, 403)
            : const _Answer(<String, Object?>{}, 204);
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.deactivateThisMachine();

      expect(result.isOk, isTrue);
      expect(
        issuer.calls.where((c) => c.startsWith('DELETE')),
        <String>['DELETE machines/fingerprint-1', 'DELETE machines/machine-1'],
      );
      expect(store.credential, isNull);
      expect(marker.released, <String, String>{licenceId: 'fingerprint-1'});
    });

    test('a refusal with no id to fall back on keeps the credential', () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker();
      final issuer = _Issuer(keys)
        ..delete = _forbidden
        ..deleteStatus = 403;
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);

      final result = await controller.deactivateThisMachine();

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.refusedByIssuer,
      );
      expect(store.credential, isNotNull);
      expect(marker.released, isEmpty, reason: 'nothing was released');
    });

    test('still refuses while offline, even with no id held', () async {
      // Before the fingerprint was shared a product with no id cleared
      // locally without asking. It cannot now: a sibling may hold the seat
      // under this same fingerprint, and clearing here while it stays
      // counted at the issuer is the trap deactivation exists to avoid.
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker();
      final controller = controllerOver(store, marker: marker);
      addTearDown(controller.dispose);

      final result = await controller.deactivateThisMachine();

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.offline,
      );
      expect(store.credential, isNotNull);
      expect(marker.released, isEmpty);
    });

    test('a file with no key marks the release and clears', () async {
      // Nothing to ask the issuer with, so the local clear is the whole
      // release — and the siblings still get the note.
      final store = _Store(credential: await keys.mintFile(filePayload()));
      final marker = InMemoryMachineReleaseMarker();
      final controller = controllerOver(store, marker: marker);
      addTearDown(controller.dispose);

      final result = await controller.deactivateThisMachine();

      expect(result.isOk, isTrue);
      expect(store.credential, isNull);
      expect(marker.released, <String, String>{licenceId: 'fingerprint-1'});
    });

    test('a marker that throws never fails the release', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(
        store,
        client: _Issuer(keys).client,
        marker: const _ThrowingMarker(),
      );
      addTearDown(controller.dispose);

      expect((await controller.deactivateThisMachine()).isOk, isTrue);
      expect(store.credential, isNull);
    });
  });

  group('a release noted by a sibling product', () {
    test(
      'is honoured at start: the key is dropped and Open Core published',
      () async {
        final store = _Store(credential: await keys.mintKey(keyPayload()));
        final marker = InMemoryMachineReleaseMarker(<String, String>{
          licenceId: 'fingerprint-1',
        });
        final issuer = _Issuer(keys);
        final controller = controllerOver(
          store,
          client: issuer.client,
          marker: marker,
        );
        addTearDown(controller.dispose);

        await controller.start();

        expect(controller.status.activation, CruxLicenseActivation.openCore);
        expect(controller.status.tier, LicenseTier.openCore);
        expect(
          store.credential,
          isNull,
          reason: 'the store, not just the status',
        );
        expect(issuer.calls, isEmpty);
      },
    );

    test('is honoured at a check-in BEFORE the issuer is contacted, so the '
        'machine is not registered again', () async {
      // The order is the whole point. Contacting the issuer first would find
      // the machine unregistered — the sibling released it — and register it
      // again, undoing the user's deactivation from a product they were not
      // looking at. An issuer that would happily register is wired in, and
      // must never be asked.
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker(<String, String>{
        licenceId: 'fingerprint-1',
      });
      final issuer = _Issuer(keys)
        ..validate = _validated('NO_MACHINE')
        ..register = _machine('machine-again')
        ..onRegister = (stub) => stub.validate = _validated('VALID');
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);

      final result = await controller.refresh();

      expect(result.isOk, isTrue);
      expect(
        issuer.calls,
        isEmpty,
        reason: 'any call here is the re-registration this guards against',
      );
      expect(store.credential, isNull);
      expect(store.machineId, isNull);
      expect(controller.status.activation, CruxLicenseActivation.openCore);
    });

    test("for another licence is not this product's business", () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker(<String, String>{
        'lic00000-0000-4000-8000-000000000002': 'fingerprint-1',
      });
      final controller = controllerOver(store, marker: marker);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(store.credential, isNotNull);
    });

    test("for another fingerprint predates this machine's identity", () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final marker = InMemoryMachineReleaseMarker(<String, String>{
        licenceId: 'fingerprint-from-before',
      });
      final controller = controllerOver(store, marker: marker);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(store.credential, isNotNull);
    });

    test('is cleared by activating the licence again', () async {
      final store = _Store();
      final marker = InMemoryMachineReleaseMarker(<String, String>{
        licenceId: 'fingerprint-1',
      });
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..register = _machine('machine-1');
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: marker,
      );
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(result.isOk, isTrue);
      expect(marker.released, isEmpty, reason: 'the note is gone');
      expect(store.credential, isNotNull);
      expect(controller.status.tier, LicenseTier.pro);

      // And the next launch keeps the key, because the note is gone.
      final relaunched = controllerOver(store, marker: marker);
      addTearDown(relaunched.dispose);
      await relaunched.start();
      expect(relaunched.status.tier, LicenseTier.pro);
    });

    test('can never clear the key the user just pasted, even when the note '
        'cannot be cleared', () async {
      // The marker below says "released" and refuses to forget it. The
      // activation path does not consult it, so the paste stands.
      final store = _Store();
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..register = _machine('machine-1');
      final controller = controllerOver(
        store,
        client: issuer.client,
        marker: const _StuckMarker(),
      );
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(result.isOk, isTrue);
      expect(store.credential, isNotNull);
      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('a marker that throws is a marker that noted nothing', () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(store, marker: const _ThrowingMarker());
      addTearDown(controller.dispose);

      await controller.start();
      final result = await controller.refresh();

      expect(controller.status.tier, LicenseTier.pro);
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.offline,
        reason: 'the issuer is unreachable here; nothing else changed',
      );
    });
  });

  group('the machine this product holds is reconciled with the shared '
      'fingerprint', () {
    test('a held id that is not the machine the fingerprint names is an '
        'orphan: released, and the real one kept', () async {
      // The first machine a suite licence was used on: a sibling's machine
      // stands under the shared fingerprint, so the issuer says VALID, and
      // nothing else would ever ask about the record this product left
      // under the fingerprint it had before.
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-old',
      );
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..lookup = _machine('machine-shared');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(issuer.calls, contains('GET machines/fingerprint-1'));
      expect(issuer.calls, contains('DELETE machines/machine-old'));
      expect(issuer.calls, isNot(contains('POST machines')));
      expect(store.machineId, 'machine-shared');
      expect(controller.status.activation, CruxLicenseActivation.active);
    });

    test('is asked once per launch', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-shared',
      );
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..lookup = _machine('machine-shared');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();
      await controller.refresh();

      expect(
        issuer.calls.where((c) => c == 'GET machines/fingerprint-1'),
        hasLength(1),
      );
      expect(issuer.calls, isNot(contains(startsWith('DELETE'))));
      expect(store.machineId, 'machine-shared');
    });

    test("a product holding no id learns the machine's", () async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..lookup = _machine('machine-shared');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(issuer.calls, isNot(contains(startsWith('DELETE'))));
      expect(store.machineId, 'machine-shared');
    });

    test('a lookup the issuer cannot answer changes nothing and is asked '
        'again next time', () async {
      final store = _Store(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-old',
      );
      final issuer = _Issuer(keys)..validate = _validated('VALID');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.refresh();
      await controller.refresh();

      expect(
        issuer.calls.where((c) => c == 'GET machines/fingerprint-1'),
        hasLength(2),
      );
      expect(issuer.calls, isNot(contains(startsWith('DELETE'))));
      expect(store.machineId, 'machine-old');
      expect(controller.status.activation, CruxLicenseActivation.active);
    });

    test('activating again from a product that holds an orphan releases '
        'it', () async {
      final store = _Store(machineId: 'machine-old');
      final issuer = _Issuer(keys)
        ..validate = _validated('VALID')
        ..register = _taken
        ..registerStatus = 422
        ..lookup = _machine('machine-shared');
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(result.isOk, isTrue);
      expect(issuer.calls, contains('DELETE machines/machine-old'));
      expect(store.machineId, 'machine-shared');
    });
  });

  group('a check is due when the recorded answer is not about this '
      'fingerprint', () {
    Future<_Store> recordedUnder(String fingerprint, _Issuer issuer) async {
      final store = _Store(credential: await keys.mintKey(keyPayload()));
      issuer.validate = _scoped(_validated('VALID'), fingerprint);
      final earlier = controllerOver(store, client: issuer.client);
      await earlier.refresh();
      await earlier.dispose();
      expect(store.issuerSnapshot, isNotNull);
      expect(store.lastCheck, duringTerm);
      issuer
        ..calls.clear()
        ..validate = _validated('VALID');
      return store;
    }

    test('a product that just adopted the shared fingerprint asks at once, '
        'however recent its last check', () async {
      final issuer = _Issuer(keys);
      final store = await recordedUnder('fingerprint-0', issuer);
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.start();
      await pumpEventQueue();

      expect(issuer.calls, contains('POST licenses/actions/validate-key'));
    });

    test('and one whose recorded answer was about this fingerprint waits '
        'for the interval', () async {
      final issuer = _Issuer(keys);
      final store = await recordedUnder('fingerprint-1', issuer);
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      await controller.start();
      await pumpEventQueue();

      expect(issuer.calls, isEmpty);
      expect(controller.status.tier, LicenseTier.pro);
    });
  });
}

/// [answer] with the fingerprint the issuer echoes as the question's scope.
Map<String, Object?> _scoped(Map<String, Object?> answer, String fingerprint) =>
    <String, Object?>{
      ...answer,
      'meta': <String, Object?>{
        ...answer['meta']! as Map<String, Object?>,
        'scope': <String, Object?>{'fingerprint': fingerprint},
      },
    };

/// A validate-key answer about the fixture licence, with [code].
Map<String, Object?> _validated(String code) => <String, Object?>{
  'meta': <String, Object?>{'valid': code == 'VALID', 'code': code},
  'data': <String, Object?>{
    'id': 'lic00000-0000-4000-8000-000000000001',
    'attributes': <String, Object?>{
      'expiry': '2027-01-01T00:00:00.000Z',
      'maxMachines': 3,
      'machinesCount': 1,
    },
  },
};

/// A machine resource with [id], as registration and lookup answer it.
Map<String, Object?> _machine(String id) => <String, Object?>{
  'data': <String, Object?>{'id': id, 'type': 'machines'},
};

/// What the issuer says when this fingerprint is already registered.
const Map<String, Object?> _taken = <String, Object?>{
  'errors': <Object?>[
    <String, Object?>{
      'title': 'Unprocessable resource',
      'detail': 'fingerprint has already been taken',
    },
  ],
};

const Map<String, Object?> _forbidden = <String, Object?>{
  'errors': <Object?>[
    <String, Object?>{'title': 'Forbidden', 'detail': 'refused'},
  ],
};

class _Answer {
  const _Answer(this.body, this.status);

  final Map<String, Object?> body;
  final int status;
}

/// An issuer answering each endpoint separately, recording every call as
/// `METHOD path-under-the-account` in the order it was made.
class _Issuer {
  _Issuer(this.keys);

  final TestIssuerKeys keys;
  final List<String> calls = <String>[];

  Map<String, Object?> validate = _validated('VALID');
  Map<String, Object?> register = _machine('machine-new');
  int registerStatus = 201;
  Map<String, Object?>? lookup;
  Map<String, Object?> delete = const <String, Object?>{};
  int deleteStatus = 204;
  _Answer Function(String machine)? deleteFor;
  void Function(_Issuer stub)? onRegister;

  http.Client get client => stubClient((request) {
    final path = request.url.path;
    const under = '/accounts/$testAccountId/';
    final route = path.substring(path.indexOf(under) + under.length);
    calls.add('${request.method} $route');

    final _Answer answer;
    if (route == 'licenses/actions/validate-key') {
      answer = _Answer(validate, 200);
    } else if (route == 'machines' && request.method == 'POST') {
      answer = _Answer(register, registerStatus);
      if (registerStatus < 300) onRegister?.call(this);
    } else if (route.startsWith('machines/') && request.method == 'GET') {
      final found = lookup;
      answer = found == null
          ? const _Answer(<String, Object?>{
              'errors': <Object?>[
                <String, Object?>{
                  'title': 'Not found',
                  'detail': 'not found',
                  'code': 'NOT_FOUND',
                },
              ],
            }, 404)
          : _Answer(found, 200);
    } else if (route.startsWith('machines/') && request.method == 'DELETE') {
      final machine = route.substring('machines/'.length);
      answer = deleteFor?.call(machine) ?? _Answer(delete, deleteStatus);
    } else {
      answer = const _Answer(<String, Object?>{
        'errors': <Object?>[
          <String, Object?>{'title': 'Unexpected', 'detail': 'no such route'},
        ],
      }, 500);
    }
    if (answer.status == 204) {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 204);
    }
    return signedIssuerResponse(
      keys: keys,
      request: request,
      body: answer.body,
      status: answer.status,
    );
  });
}

class _Store implements LicenseStore {
  _Store({this.credential, this.machineId});

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
  Future<String?> readIssuerSnapshot() async => issuerSnapshot;

  @override
  Future<void> writeCredential(String credential) async =>
      this.credential = credential;

  @override
  Future<void> writeIssuerSnapshot(String? snapshot) async =>
      issuerSnapshot = snapshot;

  @override
  Future<void> writeLastCheck(DateTime at) async => lastCheck = at;

  @override
  Future<void> writeMachineId(String? machineId) async =>
      this.machineId = machineId;
}

/// A marker whose every method throws: the broken profile.
class _ThrowingMarker implements MachineReleaseMarker {
  const _ThrowingMarker();

  @override
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  }) async => throw StateError('marker unavailable');

  @override
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  }) async => throw StateError('marker unavailable');

  @override
  Future<void> clearReleased({required String licenseId}) async =>
      throw StateError('marker unavailable');
}

/// A marker that says "released" for everything and cannot be cleared.
class _StuckMarker implements MachineReleaseMarker {
  const _StuckMarker();

  @override
  Future<void> markReleased({
    required String licenseId,
    required String fingerprint,
  }) async {}

  @override
  Future<bool> wasReleased({
    required String licenseId,
    required String fingerprint,
  }) async => true;

  @override
  Future<void> clearReleased({required String licenseId}) async =>
      throw StateError('cannot write the marker');
}

class _Down implements Exception {
  const _Down();
}
