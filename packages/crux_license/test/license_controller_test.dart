// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/keygen_signing.dart';
import 'support/license_fixtures.dart';

/// The licensing state machine.
///
/// The properties under test are the ones that decide whether a paying
/// customer keeps working: that a validated credential resolves with no
/// network at all, that an unreachable issuer never downgrades anyone, that
/// grace runs for the documented window per tier, and that a renewal recorded
/// at the issuer wins over the older date baked into the key.
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

  CruxLicenseController controllerOver(
    _FakeStore store, {
    http.Client? client,
    DateTime? now,
  }) => CruxLicenseController(
    product: CruxProduct.waveCrux,
    validator: validator,
    store: store,
    client: KeygenLicenseClient(
      accountId: testAccountId,
      verifyKey: keys.verifyKey,
      client: client ?? _offlineClient(),
    ),
    machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
    openUrl: (_) async {},
    purchaseUrl: Uri.parse('https://example.test/buy'),
    manageUrl: Uri.parse('https://example.test/manage'),
    now: () => now ?? duringTerm,
  );

  group('offline is the normal case', () {
    test('a stored credential resolves with no network', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.pro);
      expect(
        controller.status.lastCheckedAt,
        isNull,
        reason: 'never having reached the issuer is a fine state to be in',
      );
    });

    test('no credential is Open Core, not an error', () async {
      final controller = controllerOver(_FakeStore());
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.openCore);
      expect(controller.status.tier, LicenseTier.openCore);
    });

    test('an unreachable issuer never downgrades anyone', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(store);
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.refresh();

      expect(result.isOk, isFalse, reason: 'the caller is told it failed');
      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.offline,
      );
      expect(
        controller.status.tier,
        LicenseTier.pro,
        reason: 'the whole airgap story rests on this',
      );
      expect(store.lastCheck, isNull, reason: 'nothing was confirmed');
    });
  });

  group('expiry and grace', () {
    Future<CruxLicenseController> expiredControllerAt(DateTime now) async {
      final store = _FakeStore(
        credential: await keys.mintKey(
          keyPayload(expiry: '2026-10-01T00:00:00.000Z'),
        ),
      );
      return controllerOver(store, now: now);
    }

    test('inside the window, grace keeps the licensed tier', () async {
      // Pro grace is 30 days. Day 10 after expiry is inside it.
      final controller = await expiredControllerAt(DateTime.utc(2026, 10, 11));
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.grace);
      expect(
        controller.status.tier,
        LicenseTier.pro,
        reason: 'keeping the tier is what grace IS',
      );
      expect(
        controller.status.graceDaysRemainingAt(DateTime.utc(2026, 10, 11)),
        20,
      );
    });

    test('past the window, it falls back to Open Core', () async {
      final controller = await expiredControllerAt(DateTime.utc(2026, 11, 15));
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.expired);
      expect(controller.status.tier, LicenseTier.openCore);
    });

    test('each tier gets the window the plan documents', () {
      const policy = LicenseGracePolicy.standard;
      expect(policy.forTier(LicenseTier.pro), const Duration(days: 30));
      expect(policy.forTier(LicenseTier.edu), const Duration(days: 60));
      expect(
        policy.forTier(LicenseTier.enterprise),
        const Duration(days: 90),
        reason: 'the airgapped / semiconductor-customer profile',
      );
      expect(policy.forTier(LicenseTier.openCore), Duration.zero);
    });

    test('an Enterprise licence outlives a Pro one on the same date', () async {
      // The same expiry, 60 days ago: Pro is out of grace, Enterprise is not.
      final expiry = DateTime.utc(2026, 10);
      final now = DateTime.utc(2026, 11, 30);
      const policy = LicenseGracePolicy.standard;
      expect(
        policy.covers(expiry: expiry, tier: LicenseTier.pro, now: now),
        isFalse,
      );
      expect(
        policy.covers(expiry: expiry, tier: LicenseTier.enterprise, now: now),
        isTrue,
      );
    });
  });

  group('the issuer refreshes what the key cannot know', () {
    test('a renewal recorded at the issuer wins over the key date', () async {
      // The key was signed before the renewal, so its own expiry is stale by
      // design. Treating a renewed customer as expired is the failure that
      // costs the most, so the later of the two wins.
      final store = _FakeStore(
        credential: await keys.mintKey(
          keyPayload(expiry: '2026-08-15T00:00:00.000Z'),
        ),
      );
      final controller = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'meta': <String, Object?>{'valid': true, 'code': 'VALID'},
          'data': <String, Object?>{
            'id': 'lic-1',
            'attributes': <String, Object?>{
              'expiry': '2027-08-15T00:00:00.000Z',
              'maxMachines': 3,
              'machinesCount': 2,
            },
          },
        }),
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.refresh();

      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.grant!.expiry, DateTime.utc(2027, 8, 15));
      expect(controller.status.seatsUsed, 2);
      expect(controller.status.seatsTotal, 3);
      expect(store.lastCheck, isNotNull);
    });

    test(
      'a suspended licence is refused even though the key verifies',
      () async {
        final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
        final controller = controllerOver(
          store,
          client: _jsonClient(keys, <String, Object?>{
            'meta': <String, Object?>{'valid': false, 'code': 'SUSPENDED'},
          }),
        );
        addTearDown(controller.dispose);

        await controller.start();
        await controller.refresh();

        expect(controller.status.activation, CruxLicenseActivation.invalid);
        expect(controller.status.tier, LicenseTier.openCore);
      },
    );

    test('an unrecognised code changes nothing', () async {
      // Keygen adds codes. A build that downgraded on an unknown one would be
      // a build that downgrades customers on an upgrade.
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'meta': <String, Object?>{'valid': true, 'code': 'SOMETHING_NEW'},
        }),
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.refresh();

      expect(controller.status.tier, LicenseTier.pro);
    });
  });

  group('what the issuer said survives a relaunch', () {
    // A relaunch inside the phone-home interval does not check in, so the
    // second controller below sees only what the first one left in the store.
    final renewedAnswer = <String, Object?>{
      'meta': <String, Object?>{'valid': true, 'code': 'VALID'},
      'data': <String, Object?>{
        'id': 'lic00000-0000-4000-8000-000000000001',
        'attributes': <String, Object?>{
          'expiry': '2027-08-15T00:00:00.000Z',
          'maxMachines': 3,
          'machinesCount': 1,
        },
      },
    };

    test('a renewed subscriber is not read as expired on relaunch', () async {
      // The key's own expiry passed 17 days ago; the issuer has renewed it.
      final store = _FakeStore(
        credential: await keys.mintKey(
          keyPayload(expiry: '2026-08-15T00:00:00.000Z'),
        ),
      );
      final first = controllerOver(
        store,
        client: _jsonClient(keys, renewedAnswer),
      );
      await first.start();
      await first.refresh();
      await first.dispose();

      final relaunched = controllerOver(store);
      addTearDown(relaunched.dispose);
      await relaunched.start();

      expect(
        relaunched.status.activation,
        CruxLicenseActivation.active,
        reason: 'grace here is a paying customer told their renewal is overdue',
      );
      expect(relaunched.status.grant!.expiry, DateTime.utc(2027, 8, 15));
      expect(relaunched.status.seatsTotal, 3);
    });

    test('a suspension is still refused on relaunch', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final first = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'meta': <String, Object?>{'valid': false, 'code': 'SUSPENDED'},
        }),
      );
      await first.start();
      await first.refresh();
      await first.dispose();

      final relaunched = controllerOver(store);
      addTearDown(relaunched.dispose);
      await relaunched.start();

      expect(relaunched.status.activation, CruxLicenseActivation.invalid);
      expect(
        relaunched.status.tier,
        LicenseTier.openCore,
        reason: 'otherwise every relaunch re-grants a cancelled licence',
      );
    });

    test('a later answer replaces the stored one', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final suspended = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'meta': <String, Object?>{'valid': false, 'code': 'SUSPENDED'},
        }),
      );
      await suspended.start();
      await suspended.refresh();
      await suspended.dispose();

      final reinstated = controllerOver(
        store,
        client: _jsonClient(keys, renewedAnswer),
      );
      addTearDown(reinstated.dispose);
      await reinstated.start();
      await reinstated.refresh();

      expect(reinstated.status.activation, CruxLicenseActivation.active);
      expect(reinstated.status.tier, LicenseTier.pro);
    });

    test('an answer about one licence never applies to another', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final first = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'meta': <String, Object?>{'valid': false, 'code': 'SUSPENDED'},
        }),
      );
      await first.start();
      await first.refresh();
      await first.dispose();

      final other = keyPayload();
      (other['license']! as Map<String, Object?>)['id'] =
          'lic00000-0000-4000-8000-000000000002';
      store.credential = await keys.mintKey(other);

      final relaunched = controllerOver(store);
      addTearDown(relaunched.dispose);
      await relaunched.start();

      expect(relaunched.status.activation, CruxLicenseActivation.active);
      expect(relaunched.status.tier, LicenseTier.pro);
    });

    test('an unreadable snapshot falls back to the key', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()))
        ..lastCheck = duringTerm
        ..issuerSnapshot = 'not json {';
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.start();

      expect(controller.status.activation, CruxLicenseActivation.active);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('deactivating forgets what the issuer said', () async {
      final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
      final controller = controllerOver(
        store,
        client: _jsonClient(keys, renewedAnswer),
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.refresh();
      expect(store.issuerSnapshot, isNotNull);

      await controller.deactivateThisMachine();

      expect(store.issuerSnapshot, isNull);
    });
  });

  group('activation', () {
    test('a bad key is refused and nothing is stored', () async {
      final store = _FakeStore();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      final result = await controller.activate('not a licence at all');

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.rejected,
      );
      expect(store.credential, isNull);
    });

    test('a good key is stored before the network is touched', () async {
      // A customer on a flaky connection should not have to paste a
      // 700-character key twice.
      final store = _FakeStore();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.activate(await keys.mintKey(keyPayload()));

      expect(store.credential, isNotNull);
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('a full licence refuses the seat but keeps the key', () async {
      final store = _FakeStore();
      final controller = controllerOver(
        store,
        client: _jsonClient(keys, <String, Object?>{
          'errors': <Object?>[
            <String, Object?>{
              'title': 'Unprocessable',
              'detail':
                  'machine count has exceeded maximum allowed for license',
            },
          ],
        }, status: 422),
      );
      addTearDown(controller.dispose);

      final result = await controller.activate(
        await keys.mintKey(keyPayload()),
      );

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.noSeatAvailable,
      );
      expect(
        store.credential,
        isNotNull,
        reason: 'the licence is real; only the seat was refused',
      );
      expect(controller.status.activation, CruxLicenseActivation.noSeat);
      expect(
        controller.status.tier,
        LicenseTier.openCore,
        reason: 'a refused machine that kept the tier is a shared licence',
      );
    });
  });

  group('seats are enforced when the issuer says so', () {
    final seatRefused = <String, Object?>{
      'errors': <Object?>[
        <String, Object?>{
          'title': 'Unprocessable resource',
          'detail':
              'machine count has exceeded maximum allowed for license (3)',
          'code': 'MACHINE_LIMIT_EXCEEDED',
        },
      ],
    };
    Map<String, Object?> validated(String code) => <String, Object?>{
      'meta': <String, Object?>{'valid': code == 'VALID', 'code': code},
      'data': <String, Object?>{
        'id': 'lic00000-0000-4000-8000-000000000001',
        'attributes': <String, Object?>{
          'expiry': '2027-01-01T00:00:00.000Z',
          'maxMachines': 3,
          'machinesCount': 3,
        },
      },
    };

    test('a refused seat is still refused after a relaunch', () async {
      final store = _FakeStore();
      final first = controllerOver(
        store,
        client: _IssuerStub(
          keys: keys,
          validate: validated('NO_MACHINE'),
          register: seatRefused,
          registerStatus: 422,
        ).client,
      );
      await first.activate(await keys.mintKey(keyPayload()));
      await first.dispose();

      final relaunched = controllerOver(store);
      addTearDown(relaunched.dispose);
      await relaunched.start();

      expect(relaunched.status.activation, CruxLicenseActivation.noSeat);
      expect(relaunched.status.tier, LicenseTier.openCore);
    });

    test('a freed seat is taken at the next check-in', () async {
      final store = _FakeStore();
      final full = controllerOver(
        store,
        client: _IssuerStub(
          keys: keys,
          validate: validated('NO_MACHINE'),
          register: seatRefused,
          registerStatus: 422,
        ).client,
      );
      await full.activate(await keys.mintKey(keyPayload()));
      await full.dispose();

      final issuer = _IssuerStub(
        keys: keys,
        validate: validated('NO_MACHINE'),
        register: <String, Object?>{
          'data': <String, Object?>{'id': 'machine-7', 'type': 'machines'},
        },
      )..onRegister = (stub) => stub.validate = validated('VALID');
      final freed = controllerOver(store, client: issuer.client);
      addTearDown(freed.dispose);
      await freed.refresh();

      expect(freed.status.activation, CruxLicenseActivation.active);
      expect(freed.status.tier, LicenseTier.pro);
      expect(store.machineId, 'machine-7');
    });

    test('an offline activation is registered at the first check-in, and '
        'refused if the licence is full', () async {
      final store = _FakeStore();
      final onPlane = controllerOver(store);
      await onPlane.activate(await keys.mintKey(keyPayload()));
      expect(
        onPlane.status.tier,
        LicenseTier.pro,
        reason: 'offline keeps the tier; nobody refused anything yet',
      );
      await onPlane.dispose();

      final issuer = _IssuerStub(
        keys: keys,
        validate: validated('NO_MACHINE'),
        register: seatRefused,
        registerStatus: 422,
      );
      final landed = controllerOver(store, client: issuer.client);
      addTearDown(landed.dispose);
      await landed.refresh();

      expect(issuer.calls, contains('POST machines'));
      expect(landed.status.activation, CruxLicenseActivation.noSeat);
      expect(landed.status.tier, LicenseTier.openCore);
    });

    test('an unreachable issuer never refuses a seat', () async {
      final store = _FakeStore();
      final controller = controllerOver(store);
      addTearDown(controller.dispose);

      await controller.activate(await keys.mintKey(keyPayload()));
      await controller.refresh();

      expect(controller.status.activation, isNot(CruxLicenseActivation.noSeat));
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('a licence file registers its seat with the key it embeds', () async {
      final key = await keys.mintKey(keyPayload());
      final file = await keys.mintFile(filePayload(key: key));
      final store = _FakeStore();
      final issuer = _IssuerStub(
        keys: keys,
        validate: validated('VALID'),
        register: <String, Object?>{
          'data': <String, Object?>{'id': 'machine-9', 'type': 'machines'},
        },
      );
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      final result = await controller.activate(file);

      expect(result.isOk, isTrue);
      expect(issuer.calls, contains('POST machines'));
      expect(
        issuer.authorizations,
        contains('License $key'),
        reason: 'the multi-line file itself cannot be sent as a header',
      );
      expect(store.machineId, 'machine-9');
      expect(controller.status.tier, LicenseTier.pro);
    });

    test('a file-activated machine releases its seat', () async {
      final key = await keys.mintKey(keyPayload());
      final store = _FakeStore(
        credential: await keys.mintFile(filePayload(key: key)),
        machineId: 'machine-9',
      );
      final issuer = _IssuerStub(
        keys: keys,
        validate: <String, Object?>{},
        register: <String, Object?>{},
      );
      final controller = controllerOver(store, client: issuer.client);
      addTearDown(controller.dispose);

      final result = await controller.deactivateThisMachine();

      expect(
        result.isOk,
        isTrue,
        reason: 'this read as offline while the issuer was reachable',
      );
      // By fingerprint, which the issuer resolves like the id: the release
      // must work from a sibling product that holds no id for this machine.
      expect(issuer.calls, contains('DELETE fingerprint-1'));
      expect(issuer.authorizations, contains('License $key'));
      expect(store.credential, isNull);
    });

    test(
      'a request that cannot be built is never reported as offline',
      () async {
        final client = KeygenLicenseClient(
          accountId: testAccountId,
          client: _StubClient((_) => throw StateError('must not be sent')),
        );
        addTearDown(client.close);

        final result = await client.deactivateMachine(
          key: '-----BEGIN LICENSE FILE-----\nabc\n-----END LICENSE FILE-----',
          machine: 'machine-9',
        );

        expect(result.outcome, KeygenMachineOutcome.refused);
      },
    );

    test(
      'a licence over its seats runs Open Core on every machine until the '
      'owner frees one',
      () async {
        // The issuer answers TOO_MANY_MACHINES when a licence holds more
        // registered machines than it has seats — which, under NO_OVERAGE,
        // only happens when the seat count was reduced after the machines
        // registered. Enterprise seats are priced per machine, so a licence
        // that kept every machine running after its owner paid for fewer
        // would be selling seats it no longer charges for. Which machines
        // keep theirs is the owner's decision, made in the issuer's portal;
        // until it is made, nobody holds one. The machine is still
        // registered, so no registration is attempted, and the panel shows
        // the count so the owner knows what to free.
        final store = _FakeStore(
          credential: await keys.mintKey(keyPayload()),
          machineId: 'machine-1',
        );
        final over = validated('TOO_MANY_MACHINES');
        (over['data']!
            as Map<String, Object?>)['attributes'] = <String, Object?>{
          'expiry': '2027-01-01T00:00:00.000Z',
          'maxMachines': 2,
          'machinesCount': 3,
        };
        final issuer = _IssuerStub(
          keys: keys,
          validate: over,
          register: seatRefused,
          registerStatus: 422,
        );
        final controller = controllerOver(store, client: issuer.client);
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(issuer.calls, isNot(contains('POST machines')));
        expect(controller.status.activation, CruxLicenseActivation.noSeat);
        expect(controller.status.tier, LicenseTier.openCore);
        expect(controller.status.seatsUsed, 3);
        expect(controller.status.seatsTotal, 2);
      },
    );

    test(
      'a seat count over its machines is still refused after a relaunch',
      () async {
        // The answer is signed and persisted like any other, so the restriction
        // survives until the next check-in says otherwise.
        final store = _FakeStore(
          credential: await keys.mintKey(keyPayload()),
          machineId: 'machine-1',
        );
        final first = controllerOver(
          store,
          client: _IssuerStub(
            keys: keys,
            validate: validated('TOO_MANY_MACHINES'),
            register: seatRefused,
            registerStatus: 422,
          ).client,
        );
        await first.refresh();
        await first.dispose();

        final relaunched = controllerOver(store);
        addTearDown(relaunched.dispose);
        await relaunched.start();

        expect(relaunched.status.activation, CruxLicenseActivation.noSeat);
        expect(relaunched.status.tier, LicenseTier.openCore);
      },
    );

    test(
      'a seat freed at the issuer restores the tier at the next check-in',
      () async {
        final store = _FakeStore(
          credential: await keys.mintKey(keyPayload()),
          machineId: 'machine-1',
        );
        final over = controllerOver(
          store,
          client: _IssuerStub(
            keys: keys,
            validate: validated('TOO_MANY_MACHINES'),
            register: seatRefused,
            registerStatus: 422,
          ).client,
        );
        await over.refresh();
        expect(over.status.activation, CruxLicenseActivation.noSeat);
        await over.dispose();

        final freed = controllerOver(
          store,
          client: _IssuerStub(
            keys: keys,
            validate: validated('VALID'),
            register: seatRefused,
            registerStatus: 422,
          ).client,
        );
        addTearDown(freed.dispose);
        await freed.refresh();

        expect(freed.status.activation, CruxLicenseActivation.active);
        expect(freed.status.tier, LicenseTier.pro);
      },
    );
  });

  group('deactivation', () {
    test('refuses while offline rather than orphaning the seat', () async {
      // Clearing locally while the seat stays counted at the issuer is how a
      // customer ends up unable to activate their own last machine.
      final store = _FakeStore(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(store);
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.deactivateThisMachine();

      expect(
        (result as LicenseActionFailed).failure,
        CruxLicenseActionFailure.offline,
      );
      expect(store.credential, isNotNull);
    });

    test('clears everything once the issuer confirms', () async {
      final store = _FakeStore(
        credential: await keys.mintKey(keyPayload()),
        machineId: 'machine-1',
      );
      final controller = controllerOver(
        store,
        client: _jsonClient(keys, const <String, Object?>{}, status: 204),
      );
      addTearDown(controller.dispose);
      await controller.start();

      final result = await controller.deactivateThisMachine();

      expect(result.isOk, isTrue);
      expect(store.credential, isNull);
      expect(store.machineId, isNull);
      expect(controller.status.activation, CruxLicenseActivation.openCore);
    });
  });

  test('a licence for another product does not unlock this one', () async {
    final netcrux = CruxLicenseValidator(
      product: CruxProduct.netCrux,
      issuers: <LicenseIssuer>[issuer],
    );
    final store = _FakeStore(credential: await keys.mintKey(keyPayload()));
    final controller = CruxLicenseController(
      product: CruxProduct.netCrux,
      validator: netcrux,
      store: store,
      client: KeygenLicenseClient(
        accountId: testAccountId,
        verifyKey: keys.verifyKey,
        client: _offlineClient(),
      ),
      machine: const LicenseMachineIdentity(name: 'lab-01', platform: 'macos'),
      openUrl: (_) async {},
      purchaseUrl: Uri.parse('https://example.test/buy'),
      manageUrl: Uri.parse('https://example.test/manage'),
      now: () => duringTerm,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.status.activation, CruxLicenseActivation.invalid);
    expect(controller.status.rejection, LicenseRejection.productNotEntitled);
  });
}

/// An in-memory [LicenseStore]. The real binding is `crux_secrets` over the
/// OS credential store; nothing here depends on which.
class _FakeStore implements LicenseStore {
  _FakeStore({this.credential, this.machineId});

  String? credential;
  String? machineId;
  DateTime? lastCheck;
  String? fingerprint;

  @override
  Future<void> clear() async {
    credential = null;
    machineId = null;
    lastCheck = null;
    issuerSnapshot = null;
  }

  @override
  Future<DateTime?> readLastCheck() async => lastCheck;

  @override
  Future<String?> readCredential() async => credential;

  @override
  Future<String?> readMachineId() async => machineId;

  @override
  Future<String> readOrCreateFingerprint() async =>
      fingerprint ??= 'fingerprint-1';

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

/// A client that always fails to connect — the airgap case.
http.Client _offlineClient() => _StubClient((_) => throw const _Unreachable());

/// A client answering every call with one JSON body, signed as the issuer
/// signs its answers.
http.Client _jsonClient(
  TestIssuerKeys keys,
  Map<String, Object?> body, {
  int status = 200,
}) => signedJsonClient(keys, body, status: status);

class _Unreachable implements Exception {
  const _Unreachable();
}

/// An issuer that answers machine registration and key validation separately,
/// and records what it was asked as `METHOD last-path-segment`.
class _IssuerStub {
  _IssuerStub({
    required this.keys,
    required this.validate,
    required this.register,
    this.registerStatus = 201,
  });

  final TestIssuerKeys keys;
  Map<String, Object?> validate;
  final Map<String, Object?> register;
  final int registerStatus;
  void Function(_IssuerStub stub)? onRegister;
  final List<String> calls = <String>[];
  final List<String?> authorizations = <String?>[];

  http.Client get client => _StubClient((request) {
    final segment = request.url.pathSegments.last;
    calls.add('${request.method} $segment');
    authorizations.add(request.headers['Authorization']);
    final registering = segment == 'machines';
    final body = registering ? register : validate;
    final status = registering ? registerStatus : 200;
    if (registering && status < 300) onRegister?.call(this);
    return signedIssuerResponse(
      keys: keys,
      request: request,
      body: body,
      status: status,
    );
  });
}

class _StubClient extends http.BaseClient {
  _StubClient(this._answer);

  final http.StreamedResponse Function(http.BaseRequest request) _answer;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _answer(request);
}
