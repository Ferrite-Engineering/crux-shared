// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage whose reads throw, standing in for a preferences layer that is
/// not there — a plugin missing on a platform, a corrupt store, a sandbox
/// denying the read.
class _ThrowingStorage extends CruxEulaStorage {
  @override
  Future<String?> read(String key) async => throw StateError('no storage');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no storage');

  @override
  Future<void> remove(String key) async => throw StateError('no storage');
}

ProviderContainer _container(CruxEulaStorage storage) {
  final c = ProviderContainer(
    overrides: [cruxEulaStorageProvider.overrideWithValue(storage)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('CruxEulaAcceptanceStore', () {
    test(
      'a fresh installation has accepted nothing and must be asked',
      () async {
        final c = _container(InMemoryCruxEulaStorage());

        await c.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;

        expect(c.read(cruxEulaAcceptanceStoreProvider), isNull);
        expect(c.read(cruxEulaAcceptanceRequiredProvider), isTrue);
      },
    );

    test(
      'an installation that accepted the current version is not asked again',
      () async {
        final c = _container(
          InMemoryCruxEulaStorage({
            kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
          }),
        );

        await c.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;

        expect(c.read(cruxEulaAcceptanceStoreProvider), kCruxEulaVersion);
        expect(c.read(cruxEulaAcceptanceRequiredProvider), isFalse);
      },
    );

    // The whole reason the store holds a version rather than a bool. A bool
    // would read "accepted" here and carry an acceptance of an older agreement
    // silently forward over one the user has never seen, which is exactly what
    // EULA section 2.3 forbids.
    test('accepting an EARLIER version still requires re-acceptance', () async {
      final c = _container(
        InMemoryCruxEulaStorage({
          kCruxEulaAcceptedVersionKey: '0.9-superseded',
        }),
      );

      await c.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;

      expect(c.read(cruxEulaAcceptanceStoreProvider), '0.9-superseded');
      expect(c.read(cruxEulaAcceptanceRequiredProvider), isTrue);
    });

    test('accept() records the current version and persists it', () async {
      final storage = InMemoryCruxEulaStorage();
      final c = _container(storage);

      await c.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;
      await c.read(cruxEulaAcceptanceStoreProvider.notifier).accept();

      expect(c.read(cruxEulaAcceptanceRequiredProvider), isFalse);
      expect(
        storage.values[kCruxEulaAcceptedVersionKey],
        kCruxEulaVersion,
        reason: 'the acceptance must survive a restart',
      );
    });

    // The safe direction is "ask", never "proceed". An unreadable store is not
    // an acceptance, and section 2.1 does not let the app through without one.
    test('an unreadable store resolves to asking, not to proceeding', () async {
      final c = _container(_ThrowingStorage());

      await c
          .read(cruxEulaAcceptanceStoreProvider.notifier)
          .loaded
          .timeout(const Duration(seconds: 5));

      expect(c.read(cruxEulaAcceptanceStoreProvider), isNull);
      expect(c.read(cruxEulaAcceptanceRequiredProvider), isTrue);
    });

    test('an empty stored value is not an acceptance', () async {
      final c = _container(
        InMemoryCruxEulaStorage({kCruxEulaAcceptedVersionKey: ''}),
      );

      await c.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;

      expect(c.read(cruxEulaAcceptanceRequiredProvider), isTrue);
    });

    test(
      'resetCruxEulaAcceptance puts the installation back to un-asked',
      () async {
        final storage = InMemoryCruxEulaStorage({
          kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
        });

        await resetCruxEulaAcceptance(storage);

        expect(storage.values, isNot(contains(kCruxEulaAcceptedVersionKey)));
      },
    );
  });

  group('the embedded agreement', () {
    test('is the document counsel finalised, not a summary', () {
      expect(kCruxEulaVersion, '1.0');
      expect(kCruxEulaEffectiveDate, 'October 1, 2026');
      expect(kCruxEulaDocument.length, greaterThan(80));
    });

    // Each of these is a promise the surface or the suite depends on, and each
    // would be silently lost if the generator were pointed at a summary or an
    // older draft.
    test('carries the sections the acceptance surface depends on', () {
      final headings = kCruxEulaDocument
          .where((b) => b.isHeading)
          .map((b) => b.text)
          .toList();

      expect(headings, contains('2. Acceptance'));
      expect(headings, contains('3. Open-Source Components'));
      expect(headings, contains('8. Telemetry'));

      final body = kCruxEulaDocument.map((b) => b.text).join('\n');
      expect(
        body,
        contains('does not proceed until you accept it'),
        reason: 'section 2.1 is what the gate implements',
      );
      expect(
        body,
        contains(
          'no in-application dialog presented under Section 2.1, '
          'conditions any right',
        ),
        reason: 'section 3 is what the open-source note restates',
      );
    });

    test('has no leftover markdown emphasis', () {
      for (final block in kCruxEulaDocument) {
        expect(block.text, isNot(contains('**')));
      }
    });
  });
}
