// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/crux_secrets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CruxSecretKey', () {
    test('renders a namespaced storage key', () {
      final key = CruxSecretKey(product: 'simcrux', name: 'pr_token');
      expect(key.storageKey, 'crux.simcrux.pr_token');
    });

    test('prefixFor matches the keys of that product', () {
      final key = CruxSecretKey(product: 'lintcrux', name: 'team_db_password');
      expect(
        key.storageKey.startsWith(CruxSecretKey.prefixFor('lintcrux')),
        isTrue,
      );
      expect(
        key.storageKey.startsWith(CruxSecretKey.prefixFor('simcrux')),
        isFalse,
      );
    });

    test('rejects empty halves', () {
      expect(
        () => CruxSecretKey(product: '', name: 'x'),
        throwsArgumentError,
      );
      expect(
        () => CruxSecretKey(product: 'simcrux', name: ''),
        throwsArgumentError,
      );
    });

    test('rejects characters that platform credential APIs escape '
        'differently', () {
      for (final bad in <String>[
        'Sim Crux',
        'sim.crux',
        'sim/crux',
        'SIMCRUX',
        'sim-crux',
      ]) {
        expect(
          () => CruxSecretKey(product: bad, name: 'token'),
          throwsArgumentError,
          reason: '"$bad" should be rejected',
        );
      }
    });

    test('equality is by (product, name)', () {
      expect(
        CruxSecretKey(product: 'simcrux', name: 'a'),
        CruxSecretKey(product: 'simcrux', name: 'a'),
      );
      expect(
        CruxSecretKey(product: 'simcrux', name: 'a'),
        isNot(CruxSecretKey(product: 'simcrux', name: 'b')),
      );
    });

    test('toString carries the key and never a value', () {
      final key = CruxSecretKey(product: 'simcrux', name: 'pr_token');
      expect(key.toString(), contains('crux.simcrux.pr_token'));
    });
  });

  group('InMemoryCruxSecretStore', () {
    late CruxSecretKey token;
    late CruxSecretKey other;

    setUp(() {
      token = CruxSecretKey(product: 'simcrux', name: 'pr_token');
      other = CruxSecretKey(product: 'lintcrux', name: 'team_db_password');
    });

    test('read of an absent key is null, not an error', () async {
      final store = InMemoryCruxSecretStore();
      expect(await store.read(token), isNull);
    });

    test('round-trips a value', () async {
      final store = InMemoryCruxSecretStore();
      await store.write(token, 'ghp_secret');
      expect(await store.read(token), 'ghp_secret');
    });

    test('writing null deletes rather than storing null', () async {
      final store = InMemoryCruxSecretStore();
      await store.write(token, 'ghp_secret');
      await store.write(token, null);
      expect(await store.read(token), isNull);
      expect(store.storedKeys, isNot(contains(token.storageKey)));
    });

    test('writing empty deletes — a blanked field must not read back as '
        'configured', () async {
      final store = InMemoryCruxSecretStore();
      await store.write(token, 'ghp_secret');
      await store.write(token, '');
      expect(await store.read(token), isNull);
      expect(store.storedKeys, isNot(contains(token.storageKey)));
    });

    test('delete of an absent key succeeds silently', () async {
      final store = InMemoryCruxSecretStore();
      await expectLater(store.delete(token), completes);
    });

    test('deleteAll removes only the named product', () async {
      final store = InMemoryCruxSecretStore();
      await store.write(token, 'a');
      await store.write(other, 'b');

      await store.deleteAll('simcrux');

      expect(await store.read(token), isNull);
      expect(
        await store.read(other),
        'b',
        reason: "another product's secrets must survive",
      );
    });
  });

  group('UnavailableCruxSecretStore', () {
    late CruxSecretKey token;

    setUp(() {
      token = CruxSecretKey(product: 'simcrux', name: 'pr_token');
    });

    test('read returns null so startup "is it configured?" works', () async {
      const store = UnavailableCruxSecretStore();
      expect(await store.read(token), isNull);
    });

    test(
      'write throws rather than silently discarding the credential',
      () async {
        const store = UnavailableCruxSecretStore();
        await expectLater(
          store.write(token, 'ghp_secret'),
          throwsA(isA<CruxSecretStoreException>()),
        );
      },
    );

    test('delete and deleteAll throw', () async {
      const store = UnavailableCruxSecretStore();
      await expectLater(
        store.delete(token),
        throwsA(isA<CruxSecretStoreException>()),
      );
      await expectLater(
        store.deleteAll('simcrux'),
        throwsA(isA<CruxSecretStoreException>()),
      );
    });

    test('the exception explains how to bind a real store', () async {
      const store = UnavailableCruxSecretStore();
      try {
        await store.write(token, 'x');
        fail('expected a CruxSecretStoreException');
      } on CruxSecretStoreException catch (e) {
        expect(e.message, contains('cruxSecretStoreProvider'));
        expect(e.toString(), contains('crux.simcrux.pr_token'));
      }
    });
  });
}
