// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:crux_sqlite/crux_sqlite_test_support.dart';
import 'package:test/test.dart';

/// A toy three-version store, shaped like the real ones: v1 creates a table,
/// v2 adds a column with a default and backfill, v3 adds an index. Exists
/// only so this file can prove the HARNESS's own properties without needing
/// a real product's schema.
CruxMigrationRunner _toyRunner() => CruxMigrationRunner(
  storeName: 'toy store',
  identity: CruxAppIdentity(product: 'toycrux', appVersion: '1.0.0'),
  migrations: [
    CruxMigration(
      version: 1,
      description: 'Create widgets',
      apply: (db) async {
        await db.execute(
          'CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        );
      },
    ),
    CruxMigration(
      version: 2,
      description: 'Add widgets.weight with a default, backfilled',
      apply: (db) async {
        await db.execute(
          'ALTER TABLE widgets ADD COLUMN weight INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute('UPDATE widgets SET weight = 1');
      },
    ),
    CruxMigration(
      version: 3,
      description: 'Index widgets(name)',
      apply: (db) async {
        await db.execute(
          'CREATE INDEX idx_widgets_name ON widgets(name)',
        );
      },
    ),
  ],
);

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  group('cruxMigrationFixtureCases', () {
    test('builds one case per version, in order', () {
      final cases = cruxMigrationFixtureCases(
        runner: _toyRunner(),
        recovery: CruxDbRecovery.refuse,
        fixturesByVersion: const {},
      );
      expect(cases, hasLength(3));
      expect(cases[0].name, contains('v1'));
      expect(cases[1].name, contains('v2'));
      expect(cases[2].name, contains('v3'));
    });

    test(
      'a version with no registered fixture FAILS when run, not skips',
      () async {
        final cases = cruxMigrationFixtureCases(
          runner: _toyRunner(),
          recovery: CruxDbRecovery.refuse,
          fixturesByVersion: const {},
        );
        await expectLater(
          cases[1].run(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('v2'), contains('no data-preserving fixture')),
            ),
          ),
          reason: 'a missing fixture must throw, never silently pass',
        );
      },
    );

    test(
      'a registered fixture seeds vN, upgrades to HEAD, and is checked',
      () async {
        var sawVersion1Rows = false;
        final cases = cruxMigrationFixtureCases(
          runner: _toyRunner(),
          recovery: CruxDbRecovery.refuse,
          fixturesByVersion: {
            1: CruxMigrationFixture(
              seed: (db, version) async {
                expect(version, 1);
                // v1 has no `weight` column yet — this is the historical
                // shape, not today's.
                expect(await cruxColumnNamesOf(db, 'widgets'), {
                  'id',
                  'name',
                });
                await db.insert('widgets', {'id': 1, 'name': 'bolt'});
              },
              assertAfterUpgrade: (migrated, version, dbPath) async {
                expect(version, 1);
                final rows = await migrated.query('widgets');
                expect(rows, hasLength(1));
                expect(rows.single['name'], 'bolt');
                // The v2 column's declared default/backfill, on a row that
                // existed before the column did.
                expect(rows.single['weight'], 1);
                expect(
                  await cruxIndexNamesOf(migrated, table: 'widgets'),
                  contains('idx_widgets_name'),
                );
                sawVersion1Rows = true;
              },
            ),
            2: CruxMigrationFixture(
              seed: (db, version) async {},
              assertAfterUpgrade: (migrated, version, dbPath) async {},
            ),
            3: CruxMigrationFixture(
              seed: (db, version) async {},
              assertAfterUpgrade: (migrated, version, dbPath) async {},
            ),
          },
        );

        await cases[0].run();
        expect(sawVersion1Rows, isTrue);

        // The other two must not throw either — proves N == latestVersion
        // (a no-op "upgrade") is a legitimate, runnable case too.
        await cases[1].run();
        await cases[2].run();
      },
    );

    test(
      'the seed callback sees the file BEFORE the upgrade path touches it '
      '— building it through the runner alone, not the open policy',
      () async {
        // A precious-store recovery value would normally trigger a
        // pre-upgrade backup and a schema_meta open-stamp; neither should be
        // visible to `seed`, which must see exactly the historical file.
        var seedRanAtV1 = false;
        final cases = cruxMigrationFixtureCases(
          runner: _toyRunner(),
          recovery: CruxDbRecovery.renameAside,
          onRecovery: (_) => fail('no corruption exists in this test'),
          fixturesByVersion: {
            1: CruxMigrationFixture(
              seed: (db, version) async {
                final history = await readCruxSchemaHistory(db);
                expect(
                  history.isPresent,
                  isFalse,
                  reason:
                      'schema_meta does not exist in this toy schema at all, '
                      'and the fixture-building step must not have added '
                      'anything the runner itself would not',
                );
                seedRanAtV1 = true;
              },
              assertAfterUpgrade: (migrated, version, dbPath) async {},
            ),
            2: CruxMigrationFixture(
              seed: (db, version) async {},
              assertAfterUpgrade: (migrated, version, dbPath) async {},
            ),
            3: CruxMigrationFixture(
              seed: (db, version) async {},
              assertAfterUpgrade: (migrated, version, dbPath) async {},
            ),
          },
        );
        await cases[0].run();
        expect(seedRanAtV1, isTrue);
      },
    );
  });
}
