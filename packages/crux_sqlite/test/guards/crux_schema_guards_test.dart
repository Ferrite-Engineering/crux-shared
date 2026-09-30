// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Engine-correctness for guards G1, G2 and G6 — the three that work off a
// migration list rather than off source text.
//
// A GUARD NEVER SEEN RED IS NOT A GUARD. Each is driven here against a
// synthetic store whose migration list contains exactly the violation it
// targets, so the green runs in the product repos mean the migration lists are
// sound rather than that the check silently did nothing.

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:crux_sqlite/crux_sqlite_guards.dart';
import 'package:crux_sqlite/crux_sqlite_test_support.dart';
import 'package:test/test.dart';

final _identity = CruxAppIdentity(
  product: 'guardtest',
  appVersion: '0.0.1',
);

CruxMigrationRunner _runner(List<CruxMigration> migrations) =>
    CruxMigrationRunner(
      storeName: 'guard fixture store',
      migrations: migrations,
      identity: _identity,
    );

/// v1: one table, two columns, one index.
CruxMigration _v1() => CruxMigration(
  version: 1,
  description: 'Create widgets',
  apply: (db) async {
    await db.execute(
      'CREATE TABLE widgets (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
    );
    await db.execute('CREATE INDEX idx_widgets_name ON widgets(name)');
  },
);

/// v2: the model additive migration — ADD COLUMN with a default, backfilled.
CruxMigration _v2Additive() => CruxMigration(
  version: 2,
  description: 'Add widgets.size with a default, backfilled from name',
  apply: (db) async {
    await db.execute(
      'ALTER TABLE widgets ADD COLUMN size INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('UPDATE widgets SET size = LENGTH(name)');
  },
);

CruxSchemaManifest _manifestOf(
  List<CruxSchemaSnapshot> snapshots, {
  String source = 'test-manifest',
}) => CruxSchemaManifest(
  storeName: 'guard fixture store',
  fingerprints: <int, String>{
    for (final s in snapshots) s.version: s.fingerprint,
  },
  source: source,
);

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  group('schema snapshots', () {
    test('one per version, and normalisation ignores formatting', () async {
      final tidy = _runner([_v1(), _v2Additive()]);
      final reformatted = _runner([
        CruxMigration(
          version: 1,
          description: 'Create widgets',
          apply: (db) async {
            await db.execute('''
              CREATE TABLE widgets (
                id     INTEGER PRIMARY KEY,
                name   TEXT    NOT NULL
              )
            ''');
            await db.execute('''
              CREATE INDEX idx_widgets_name
                ON widgets(name)
            ''');
          },
        ),
        _v2Additive(),
      ]);

      final a = await cruxSchemaSnapshotsOf(tidy);
      final b = await cruxSchemaSnapshotsOf(reformatted);
      expect(a, hasLength(2));
      expect(
        b.map((s) => s.fingerprint),
        a.map((s) => s.fingerprint),
        reason:
            'reindenting a CREATE TABLE literal is not a schema change; '
            'adding a column is',
      );
      expect(a.last.columnsByTable['widgets'], {'id', 'name', 'size'});
      expect(a.first.columnsByTable['widgets'], {'id', 'name'});
    });
  });

  group('G1 — frozen schema fingerprints', () {
    test('green against a manifest that matches', () async {
      final runner = _runner([_v1(), _v2Additive()]);
      final snapshots = await cruxSchemaSnapshotsOf(runner);
      final report = cruxAuditSchemaFingerprints(
        runner: runner,
        snapshots: snapshots,
        manifest: _manifestOf(snapshots),
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('RED when a shipped migration is edited', () async {
      final shipped = _runner([_v1(), _v2Additive()]);
      final manifest = _manifestOf(await cruxSchemaSnapshotsOf(shipped));

      // The edit: v1 grows a column in place instead of getting a v3.
      final edited = _runner([
        CruxMigration(
          version: 1,
          description: 'Create widgets',
          apply: (db) async {
            await db.execute(
              'CREATE TABLE widgets (id INTEGER PRIMARY KEY, '
              'name TEXT NOT NULL, colour TEXT)',
            );
            await db.execute('CREATE INDEX idx_widgets_name ON widgets(name)');
          },
        ),
        _v2Additive(),
      ]);
      final report = cruxAuditSchemaFingerprints(
        runner: edited,
        snapshots: await cruxSchemaSnapshotsOf(edited),
        manifest: manifest,
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.map((f) => f.location),
        containsAll(<String>[
          'guard fixture store: v1',
          'guard fixture store: v2',
        ]),
        reason: 'editing v1 changes every fingerprint downstream of it',
      );
      expect(report.describe(), contains('produces a different schema'));
    });

    test('RED when a new version has no manifest line', () async {
      final shipped = _runner([_v1()]);
      final manifest = _manifestOf(await cruxSchemaSnapshotsOf(shipped));

      final grown = _runner([_v1(), _v2Additive()]);
      final report = cruxAuditSchemaFingerprints(
        runner: grown,
        snapshots: await cruxSchemaSnapshotsOf(grown),
        manifest: manifest,
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.location, 'guard fixture store: v2');
      expect(report.describe(), contains('not recorded'));
    });

    test('RED when the latest version decreases', () async {
      final shipped = _runner([_v1(), _v2Additive()]);
      final manifest = _manifestOf(await cruxSchemaSnapshotsOf(shipped));

      final shrunk = _runner([_v1()]);
      final report = cruxAuditSchemaFingerprints(
        runner: shrunk,
        snapshots: await cruxSchemaSnapshotsOf(shrunk),
        manifest: manifest,
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('cannot be withdrawn'));
    });

    test('the manifest round-trips through its own renderer', () async {
      final runner = _runner([_v1(), _v2Additive()]);
      final snapshots = await cruxSchemaSnapshotsOf(runner);
      final text = cruxRenderSchemaManifest(
        snapshots,
        storeName: 'guard fixture store',
      );
      final parsed = CruxSchemaManifest.parse(
        text,
        storeName: 'guard fixture store',
        source: 'rendered',
      );
      expect(parsed.fingerprints, <int, String>{
        for (final s in snapshots) s.version: s.fingerprint,
      });
      expect(
        text,
        contains('APPEND ONLY'),
        reason: 'the file has to say what it is to somebody who opens it cold',
      );
    });

    test('an unreadable manifest line is a FormatException, not a pass', () {
      expect(
        () => CruxSchemaManifest.parse(
          'v1 not-a-digest',
          storeName: 's',
          source: 'x',
        ),
        throwsFormatException,
      );
    });
  });

  group('G2 — additive-only monotonicity', () {
    test('green for ADD COLUMN with a backfill', () async {
      final runner = _runner([_v1(), _v2Additive()]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('green when an index is replaced — indexes carry no data', () async {
      final runner = _runner([
        _v1(),
        CruxMigration(
          version: 2,
          description: 'Replace the name index with a composite one',
          apply: (db) async {
            await db.execute('DROP INDEX idx_widgets_name');
            await db.execute(
              'CREATE INDEX idx_widgets_name_id ON widgets(name, id)',
            );
          },
        ),
      ]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('RED when a column is dropped', () async {
      final runner = _runner([
        _v1(),
        CruxMigration(
          version: 2,
          description: 'Tidy up: widgets.name was unused',
          apply: (db) async {
            // SQLite refuses to drop an indexed column, so the index goes
            // first — which is exactly how a real "tidy-up" migration would
            // have to be written, and exactly why G2 works off the resulting
            // schema rather than off the SQL.
            await db.execute('DROP INDEX idx_widgets_name');
            await db.execute('ALTER TABLE widgets DROP COLUMN name');
          },
        ),
      ]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.single.location,
        'guard fixture store v1 -> v2: `widgets`.`name`',
      );
    });

    test('RED when a table is dropped', () async {
      final runner = _runner([
        _v1(),
        CruxMigration(
          version: 2,
          description: 'Drop widgets',
          apply: (db) => db.execute('DROP TABLE widgets'),
        ),
      ]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('Every row it held'));
    });

    test('RED for a rename, which G3 cannot distinguish from a drop', () async {
      final runner = _runner([
        _v1(),
        CruxMigration(
          version: 2,
          description: 'Rename widgets.name to widgets.label',
          apply: (db) =>
              db.execute('ALTER TABLE widgets RENAME COLUMN name TO label'),
        ),
      ]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('RENAMED'));
    });

    test('RED for a table rebuild that silently loses a column', () async {
      // The 12-step table rebuild done wrong: the INSERT ... SELECT enumerates
      // fewer columns than the old table had. It is well-formed, it commits,
      // and it is wrong — exactly the failure a fingerprint alone would not
      // name.
      final runner = _runner([
        _v1(),
        CruxMigration(
          version: 2,
          description: 'Rebuild widgets with a corrected primary key',
          apply: (db) async {
            await db.execute(
              'CREATE TABLE widgets_new (id INTEGER PRIMARY '
              'KEY)',
            );
            await db.execute(
              'INSERT INTO widgets_new (id) SELECT id FROM widgets',
            );
            await db.execute('DROP TABLE widgets');
            await db.execute('ALTER TABLE widgets_new RENAME TO widgets');
          },
        ),
      ]);
      final report = cruxAuditAdditiveOnly(
        runner: runner,
        snapshots: await cruxSchemaSnapshotsOf(runner),
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.single.location,
        contains('`widgets`.`name`'),
        reason:
            'the column vanished through a rebuild, with no DROP COLUMN '
            'anywhere in the source — this is what G2 sees and a source scan '
            'does not',
      );
    });
  });

  group('G6 — fixture coverage', () {
    test('green when every version has a fixture', () {
      final runner = _runner([_v1(), _v2Additive()]);
      final report = cruxAuditFixtureCoverage(
        runner: runner,
        fixtureVersions: const {1, 2},
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('RED when a new version has no fixture', () {
      final runner = _runner([_v1(), _v2Additive()]);
      final report = cruxAuditFixtureCoverage(
        runner: runner,
        fixtureVersions: const {1},
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.location, 'guard fixture store: v2');
      expect(
        report.findings.single.detail,
        contains('Add widgets.size with a default'),
        reason: 'the message names the migration nobody proved',
      );
    });

    test('RED when a fixture is numbered past the list', () {
      final runner = _runner([_v1()]);
      final report = cruxAuditFixtureCoverage(
        runner: runner,
        fixtureVersions: const {1, 2},
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('cannot produce'));
    });

    test(
      'agrees with the runtime harness about which versions are covered',
      () {
        // The two halves of G6, checked against each other: the harness emits a
        // case per version regardless of coverage, and this guard reports the
        // gap up front. Neither is allowed to think the list is a different
        // length than the other.
        final runner = _runner([_v1(), _v2Additive()]);
        final cases = cruxMigrationFixtureCases(
          runner: runner,
          recovery: CruxDbRecovery.refuse,
          fixturesByVersion: const {},
        );
        expect(cases, hasLength(runner.latestVersion));
        final report = cruxAuditFixtureCoverage(
          runner: runner,
          fixtureVersions: const {},
        );
        expect(report.findings, hasLength(runner.latestVersion));
      },
    );
  });
}
