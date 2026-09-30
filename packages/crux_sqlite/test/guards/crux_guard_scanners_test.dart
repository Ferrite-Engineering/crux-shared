// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Engine-correctness for the text scanners behind guards G3, G4, G5 and the
// G6 store registry.
//
// A GUARD NEVER SEEN RED IS NOT A GUARD. Each scanner is driven here against
// hand-written sources that violate exactly one rule, and against the
// legitimate shapes that sit closest to that violation, so a green run in a
// product repo means "the tree is clean" rather than "the regex rotted". The
// per-repo tests under each product's `test/static/` assert their own `lib/`
// is clean; this file is what makes that assertion mean something.
//
// The negative fixtures matter as much as the positive ones. Both products
// delete ordinary files constantly (JSON baselines, waveform archives, scratch
// directories) and both run bounded retention DELETEs on every ingest. A guard
// that fired on those would be switched off within a week, so each one is
// pinned here as MUST NOT FLAG.

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite_guards.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

CruxSourceFile _src(String source) =>
    CruxSourceFile.inline('lib/fixture.dart', source);

void main() {
  group('G3 — destructive DDL scanner', () {
    CruxGuardReport scan(String source) =>
        cruxAuditDestructiveDdl(sources: [_src(source)], subject: 'fixture');

    test('flags an unwaived DROP TABLE', () {
      final report = scan('''
Future<void> apply(Database db) async {
  await db.execute('DROP TABLE violation_data_points');
}
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('DROP TABLE'));
      expect(report.findings.single.location, 'lib/fixture.dart:2');
    });

    test('flags DROP COLUMN, RENAME TO and RENAME COLUMN', () {
      final report = scan('''
await db.execute('ALTER TABLE runs DROP COLUMN metadata');
await db.execute('ALTER TABLE new_runs RENAME TO runs');
await db.execute('ALTER TABLE runs RENAME COLUMN a TO b');
''');
      expect(report.findings, hasLength(3));
    });

    test('flags a bare DELETE FROM and spares a bounded one', () {
      final bare = scan("await db.execute('DELETE FROM runs');");
      expect(bare.isClean, isFalse, reason: 'an unbounded DELETE empties it');

      final bounded = scan(
        "await db.rawDelete('DELETE FROM test_results WHERE started_at < ?');",
      );
      expect(
        bounded.isClean,
        isTrue,
        reason: 'bounded retention deletes are how both products prune',
      );
    });

    test('a waiver naming a ruling and a rationale makes it green', () {
      final report = scan('''
// MIGRATION-DESTRUCTIVE(R-SQL-2): the 12-step rebuild; the pre-v4 VACUUM
// INTO backup beside the file is what a bad copy is recovered from.
await db.execute('DROP TABLE runs_old');
''');
      expect(report.isClean, isTrue, reason: report.describe());
      expect(report.observations.single.detail, contains('R-SQL-2'));
    });

    test('a waiver naming no ruling is still red', () {
      final report = scan('''
// MIGRATION-DESTRUCTIVE(): tidying up
await db.execute('DROP TABLE runs_old');
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('names no ruling'));
    });

    test('a waiver with a ruling but no rationale is still red', () {
      final report = scan('''
// MIGRATION-DESTRUCTIVE(R-SQL-2)
await db.execute('DROP TABLE runs_old');
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('says nothing about why'));
    });

    test('a waiver too far above does not reach', () {
      final report = scan('''
// MIGRATION-DESTRUCTIVE(R-SQL-2): backed up by the pre-upgrade snapshot.
//
//
//
await db.execute('DROP TABLE runs_old');
''');
      expect(
        report.isClean,
        isFalse,
        reason:
            'a file-level marker would waive statements nobody looked at, '
            'including ones added later by somebody who never saw the ruling',
      );
    });
  });

  group('G4 — delete-database allowlist', () {
    CruxGuardReport scan(
      String source, {
      List<CruxDeleteAllowlistEntry> allowlist = const [],
    }) => cruxAuditDatabaseDeletes(
      sources: [_src(source)],
      allowlist: allowlist,
      subject: 'fixture',
    );

    test('flags the F1 shape — deleteDatabase on an open failure', () {
      final report = scan('''
try {
  return await openDatabase(path, options: options);
} on Object {
  await databaseFactory.deleteDatabase(path);
  return openDatabase(path, options: options);
}
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('deleteDatabase'));
    });

    test('flags a dart:io delete of a .db path', () {
      final report = scan('await File(dbPath).delete();');
      expect(report.isClean, isFalse);
    });

    test(
      "spares sqflite's ROW delete — Database.delete(table, {where}) is not "
      'a file delete',
      () {
        // The two shapes that actually exist in LintCrux Pro today, at the
        // two sites most likely to be read as proof this guard is noise.
        // `_db` matches every "names a database" heuristic there is; what
        // distinguishes it is the positional table argument.
        final report = scan('''
final n = await _db.delete(
  'cache_entries',
  where: 'rowid IN (SELECT rowid FROM cache_entries ORDER BY x LIMIT ?)',
  whereArgs: [limit],
);
await _db.delete('acknowledged_alerts');
await database.delete('runs', where: 'started_at < ?', whereArgs: [cutoff]);
''');
        expect(
          report.isClean,
          isTrue,
          reason:
              'a bounded row delete is how retention works in both products '
              'and is explicitly permitted\n${report.describe()}',
        );
      },
    );

    test('spares deletes of files that are not databases', () {
      final report = scan('''
Future<void> delete(String path) => File(path).delete();
if (await file.exists()) await file.delete();
if (remaining.isEmpty) runDir.deleteSync();
await _sentinel.delete();
''');
      expect(
        report.isClean,
        isTrue,
        reason:
            'waveform archives, JSON baselines and scratch dirs are deleted '
            'legitimately and constantly; a guard that fired on them would be '
            'switched off within a week\n${report.describe()}',
      );
    });

    test(
      "the package's own recreate arm is sanctioned structurally, with no "
      'allowlist entry',
      () {
        final report = scan('''
switch (recovery) {
  case CruxDbRecovery.refuse:
    throw CruxDatabaseCorruptionException();
  case CruxDbRecovery.renameAside:
    quarantinedPath = quarantineDatabaseFile(dbPath);
  case CruxDbRecovery.recreate:
    await resolved.deleteDatabase(dbPath);
    quarantinedPath = null;
}
''');
        expect(report.isClean, isTrue, reason: report.describe());
        expect(report.observations.single.detail, contains('recreate'));
      },
    );

    test('the same delete under the renameAside arm is red', () {
      final report = scan('''
switch (recovery) {
  case CruxDbRecovery.recreate:
    quarantinedPath = null;
  case CruxDbRecovery.renameAside:
    await resolved.deleteDatabase(dbPath);
}
''');
      expect(
        report.isClean,
        isFalse,
        reason:
            'the structural exemption is the recreate arm specifically, not '
            'the presence of a CruxDbRecovery switch',
      );
    });

    test('an allowlist entry on a DERIVABLE store permits the delete', () {
      final report = scan(
        'await databaseFactory.deleteDatabase(dbPath);',
        allowlist: const [
          CruxDeleteAllowlistEntry(
            file: 'lib/fixture.dart',
            storeName: 'LintCrux lint cache',
            recovery: CruxDbRecovery.recreate,
            reason: 'engine output; a fresh lint run reproduces every row',
          ),
        ],
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('the allowlist cannot admit a PRECIOUS store', () {
      final report = scan(
        'await databaseFactory.deleteDatabase(dbPath);',
        allowlist: const [
          CruxDeleteAllowlistEntry(
            file: 'lib/fixture.dart',
            storeName: 'LintCrux trend store',
            recovery: CruxDbRecovery.renameAside,
            reason: 'it was flaky and this fixed it',
          ),
        ],
      );
      expect(
        report.isClean,
        isFalse,
        reason:
            'this is the property that keeps the allowlist from being a hole: '
            "entries reference the store's own recovery declaration, so a "
            'store turning precious withdraws its own permission',
      );
      expect(report.findings.first.detail, contains('PRECIOUS'));
    });

    test('an allowlist entry matching nothing is red', () {
      final report = scan(
        'const x = 1;',
        allowlist: const [
          CruxDeleteAllowlistEntry(
            file: 'lib/gone.dart',
            storeName: 'LintCrux lint cache',
            recovery: CruxDbRecovery.recreate,
            reason: 'derivable',
          ),
        ],
      );
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('matches no delete site'));
    });
  });

  group('G5 — open-options conformance', () {
    CruxGuardReport scan(String source, {Set<String> pinned = const {}}) =>
        cruxAuditOpenOptions(
          sources: [_src(source)],
          subject: 'fixture',
          expectedDirectOpenFiles: pinned,
        );

    test('flags a versioned options object with no onDowngrade', () {
      final report = scan('''
final options = OpenDatabaseOptions(
  version: 2,
  onConfigure: (db) => db.execute('PRAGMA busy_timeout = 5000'),
  onCreate: (db, v) => _create(db),
);
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('onDowngrade:'));
    });

    test('flags a versioned options object with no busy_timeout', () {
      final report = scan('''
final options = OpenDatabaseOptions(
  version: 2,
  onCreate: (db, v) => _create(db),
  onDowngrade: (db, o, n) async => throw StateError('no'),
);
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.detail, contains('busy_timeout'));
    });

    test('a conforming options object is green', () {
      final report = scan('''
final options = OpenDatabaseOptions(
  version: runner.latestVersion,
  onConfigure: (db) async {
    await db.execute('PRAGMA busy_timeout = 5000');
  },
  onCreate: (db, v) => runner.upgrade(db, 0, v),
  onDowngrade: (db, o, n) async => throw CruxSchemaVersionSkewException(),
);
''');
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test(
      "an options object with no version: is not this guard's business",
      () {
        final report = scan('final o = OpenDatabaseOptions(readOnly: true);');
        expect(report.isClean, isTrue, reason: report.describe());
      },
    );

    test(
      'an unpinned direct openDatabase is red; a pinned one is observed',
      () {
        const source =
            'final db = await databaseFactory.openDatabase(p, options: o);';
        expect(scan(source).isClean, isFalse);

        final pinned = scan(source, pinned: {'lib/fixture.dart'});
        expect(pinned.isClean, isTrue, reason: pinned.describe());
        expect(pinned.observations, hasLength(1));
      },
    );

    test('a pin that no longer matches anything is red', () {
      final report = scan('const x = 1;', pinned: {'lib/fixture.dart'});
      expect(report.isClean, isFalse);
      expect(
        report.findings.single.detail,
        contains(
          'the set is meant to '
          'shrink',
        ),
      );
    });
  });

  group('G5b — catch shapes at an open site', () {
    // The store factory these fixtures call. Written the way a real one is —
    // a `static` method whose body goes through the open policy — because
    // the whole difficulty of this guard is that the violation was never a
    // catch around `openDatabase`. It was a catch around a call two steps
    // away from one, and a scanner that only knew sqflite's own API would
    // have watched it go past.
    const storeFactory = '''
class SqliteLintRunCacheService {
  static Future<SqliteLintRunCacheService> open({String? path}) async {
    final policy = CruxSqliteOpenPolicy(runner: _runner, recovery: dataValue);
    final db = await policy.open(path ?? inMemoryDatabasePath);
    return SqliteLintRunCacheService._(db);
  }
}
''';

    CruxGuardReport scan(
      String source, {
      List<CruxOpenCatchAllowlistEntry> allowlist = const [],
      Set<String> extra = const {},
    }) => cruxAuditOpenCatchShapes(
      sources: [
        CruxSourceFile.inline('lib/store.dart', storeFactory),
        _src(source),
      ],
      subject: 'fixture',
      allowlist: allowlist,
      extraOpenEntryPoints: extra,
    );

    test('the store factory is DERIVED, not listed', () {
      // The property that makes this guard survive a new store: nobody has
      // to come back and name it. `SqliteLintRunCacheService.open` is an
      // open-reaching call because its body reaches one, and the round after
      // that is what sees a caller of it.
      final points = cruxOpenReachingEntryPoints(
        sources: [
          CruxSourceFile.inline('lib/store.dart', storeFactory),
          CruxSourceFile.inline('lib/wrapper.dart', '''
class CacheBootstrap {
  static Future<void> warm(String path) async {
    await SqliteLintRunCacheService.open(path: path);
  }
}
'''),
        ],
      );
      expect(
        points,
        {
          'SqliteLintRunCacheService.open',
          'CacheBootstrap.warm',
        },
        reason: 'transitive: the second name is only reachable via the first',
      );
    });

    test('the derivation spares an `open` that opens no database', () {
      // Both products are full of these. A dialog's `static Future<void>
      // open(BuildContext)` is the single most common `Class.open(` in the
      // suite, and treating it as an open site would flag every error
      // boundary in the app on day one.
      final points = cruxOpenReachingEntryPoints(
        sources: [
          CruxSourceFile.inline('lib/dialog.dart', '''
class SearchDialog {
  static Future<void> open(BuildContext context) =>
      showDialog<void>(context: context, builder: (_) => const SearchDialog());
}
'''),
        ],
      );
      expect(points, isEmpty);
    });

    test('flags `on Object` around a call that reaches an open', () {
      // The exact shape that survived every earlier review, in LintCrux
      // Pro's `_openSafe`: a catch-all one step downstream of
      // a policy-conforming open, so G5 could not see it.
      final report = scan('''
Future<SqliteLintRunCacheService?> _openSafe(String path) async {
  try {
    return await SqliteLintRunCacheService.open(path: path);
  } on Object {
    return null;
  }
}
''');
      expect(report.isClean, isFalse);
      expect(report.findings.single.location, 'lib/fixture.dart:4');
      expect(
        report.findings.single.detail,
        allOf(
          contains('on Object'),
          contains('SqliteLintRunCacheService.open'),
          contains('version skew'),
        ),
      );
    });

    test(
      'flags `catch (e)`, `on dynamic` and a catch-all after typed arms',
      () {
        final untyped = scan('''
try {
  await SqliteLintRunCacheService.open(path: path);
} catch (e, st) {
  report(e, st);
}
''');
        expect(untyped.findings, hasLength(1));
        expect(untyped.findings.single.detail, contains('catch (…)'));

        final dynamicCatch = scan('''
try {
  await SqliteLintRunCacheService.open(path: path);
} on dynamic catch (e) {
  return null;
}
''');
        expect(
          dynamicCatch.isClean,
          isFalse,
          reason:
              '`on dynamic` reads as a deliberate narrowing to somebody '
              'skimming for the word Object, and catches exactly as much',
        );

        final trailing = scan('''
try {
  await SqliteLintRunCacheService.open(path: path);
} on CruxSqliteException catch (e) {
  report(e);
} catch (e) {
  return null;
}
''');
        expect(
          trailing.isClean,
          isFalse,
          reason:
              'a typed arm in front of a catch-all does not narrow it — '
              'everything the typed arm misses still lands in the catch-all',
        );
      },
    );

    test('flags a catch-all around the raw sqflite and policy roots', () {
      final raw = scan('''
try {
  return await databaseFactory.openDatabase(path, options: options);
} on Object {
  return null;
}
''');
      expect(raw.findings.single.detail, contains('openDatabase(...)'));

      final viaPolicy = scan('''
try {
  return await _policyFor(onCorruption).open(dbPath);
} catch (e) {
  return null;
}
''');
      expect(
        viaPolicy.findings.single.detail,
        contains('CruxSqliteOpenPolicy.open'),
      );
    });

    test('the typed shape that replaced it is green', () {
      // `_openSafe` as it actually is today. The rule forbids a catch that
      // cannot DISTINGUISH; it does not forbid degrading, and this store
      // legitimately degrades to "no cache this session" for all three —
      // announcing which one at its own volume. If this ever flagged, the
      // guard would be pushing people back toward the defect.
      final report = scan('''
Future<SqliteLintRunCacheService?> _openSafe(String path) async {
  try {
    return await SqliteLintRunCacheService.open(path: path);
  } on CruxSqliteException catch (error, stackTrace) {
    _diagnostics(lintCacheOpenFaultFor(error, stackTrace));
    return null;
  } on DatabaseException catch (error, stackTrace) {
    _diagnostics(LintCacheOpenFault.environment(error: error, stackTrace: stackTrace));
    return null;
  } on FileSystemException catch (error, stackTrace) {
    _diagnostics(LintCacheOpenFault.environment(error: error, stackTrace: stackTrace));
    return null;
  }
}
''');
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test(
      "a catch-all around an unrelated call is not this guard's business",
      () {
        // Both trees are full of these — settings codecs, widget error
        // boundaries, telemetry IO, engine runners, the CLI. A guard that
        // fired on them would be switched off within a week, and the one in
        // the middle here is real: `SqlTrendStore.open` swallows a failed
        // post-open reconciliation on purpose, inside the open factory itself.
        final report = scan('''
try {
  await store.reconcileInterruptedRuns();
} on Object {
  // The store is usable without the marker.
}
try {
  return jsonDecode(raw) as Map<String, Object?>;
} catch (_) {
  return const <String, Object?>{};
}
try {
  await SearchDialog.open(context);
} on Object catch (e) {
  reportUi(e);
}
''');
        expect(report.isClean, isTrue, reason: report.describe());
      },
    );

    test('prose about `on Object` at an open is prose, not code', () {
      // This guard's own subject matter is written about at length in the
      // comments beside every site it scans — including the docstring on the
      // fixed `_openSafe`, which quotes the shape it replaced. A scanner
      // that read comments would flag the explanation of why the code is
      // right, which is the most demoralising false positive there is.
      final report = scan('''
/// The catch this replaced was `on Object`, wrapped around
/// `SqliteLintRunCacheService.open`, which is the one shape the rules forbid.
///
///     try {
///       await SqliteLintRunCacheService.open(path: path);
///     } on Object {
///       return null;
///     }
const String kNote = 'try { open() } on Object { return null; }';
''');
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('an allowlist entry on a DERIVABLE store permits the catch-all', () {
      final report = scan(
        '''
try {
  await SqliteLintRunCacheService.open(path: path);
} on Object {
  return null;
}
''',
        allowlist: const [
          CruxOpenCatchAllowlistEntry(
            file: 'lib/fixture.dart',
            storeName: 'LintCrux lint cache',
            recovery: CruxDbRecovery.recreate,
            reason: 'engine output; a fresh lint run reproduces every row',
          ),
        ],
      );
      expect(report.isClean, isTrue, reason: report.describe());
      expect(report.observations.single.detail, contains('lint cache'));
    });

    test('the allowlist cannot admit a PRECIOUS store', () {
      final report = scan(
        '''
try {
  await SqliteLintRunCacheService.open(path: path);
} on Object {
  return null;
}
''',
        allowlist: const [
          CruxOpenCatchAllowlistEntry(
            file: 'lib/fixture.dart',
            storeName: 'LintCrux trend store',
            recovery: CruxDbRecovery.renameAside,
            reason: 'it was throwing and this made it stop',
          ),
        ],
      );
      expect(
        report.isClean,
        isFalse,
        reason:
            "the entry references the store's own declaration, so a store "
            'turning precious withdraws its own permission with nobody '
            'having to remember to come back and edit the list',
      );
      expect(report.findings.first.detail, contains('PRECIOUS'));
    });

    test('an allowlist entry matching nothing is red', () {
      final report = scan(
        'const x = 1;',
        allowlist: const [
          CruxOpenCatchAllowlistEntry(
            file: 'lib/gone.dart',
            storeName: 'LintCrux lint cache',
            recovery: CruxDbRecovery.recreate,
            reason: 'derivable',
          ),
        ],
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.single.detail,
        contains('matches no catch-all at an open'),
      );
    });

    test('extraOpenEntryPoints closes a gap the derivation cannot see', () {
      // The stated boundary, exercised: an open behind an INSTANCE method is
      // not derived, so a repo that grows one names it rather than
      // discovering it. SimCrux Pro needs this in the ordinary case — its
      // store factory lives in the open-core tree, which its own scan does
      // not read.
      const source = '''
try {
  await bootstrap.openStore(path);
} on Object {
  return null;
}
''';
      expect(scan(source).isClean, isTrue);
      final seeded = scan(source, extra: {'bootstrap.openStore'});
      expect(seeded.isClean, isFalse);
      expect(seeded.findings.single.detail, contains('bootstrap.openStore'));
    });

    test('the message states its own boundary', () {
      // A guard that quietly checks less than it appears to is worse than
      // one with a stated limit, so the limit is in the failure text a
      // developer actually reads — not only in the docstring.
      final report = scan('''
try {
  await SqliteLintRunCacheService.open(path: path);
} on Object {
  return null;
}
''');
      expect(
        report.describe(),
        allOf(
          contains('TEXT SCAN, NOT A CALL GRAPH'),
          contains('extraOpenEntryPoints'),
          contains(
            'crux_sqlite/README.md — "Corruption, migration failure and '
            'version skew"',
          ),
        ),
      );
    });
  });

  group('G6 — store registry', () {
    test('flags a migration list no guard was pointed at', () {
      final report = cruxAuditMigrationListRegistry(
        sources: [
          _src(
            'final List<CruxMigration> newStoreMigrations = <CruxMigration>[];',
          ),
        ],
        registeredListNames: const {'someOtherMigrations'},
        subject: 'fixture',
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.map((f) => f.detail).join(),
        allOf(contains('newStoreMigrations'), contains('someOtherMigrations')),
      );
    });

    test('a registered, declared list is green', () {
      final report = cruxAuditMigrationListRegistry(
        sources: [
          _src(
            'final List<CruxMigration> newStoreMigrations = <CruxMigration>[];',
          ),
        ],
        registeredListNames: const {'newStoreMigrations'},
        subject: 'fixture',
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });
  });

  group('G6 — data-preserving suite exists', () {
    const markers = {
      'LintCrux trend store': ['lintcruxTrendStoreMigrations'],
    };

    test('RED when no suite drives the harness over the store', () {
      final report = cruxAuditFixtureSuites(
        testSources: [
          CruxSourceFile.inline(
            'test/services/other_test.dart',
            'void main() { test("x", () {}); }',
          ),
        ],
        storeMarkers: markers,
        subject: 'fixture',
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.map((f) => f.location),
        contains('LintCrux trend store'),
      );
    });

    test('RED when the harness is called but never for this store', () {
      final report = cruxAuditFixtureSuites(
        testSources: [
          CruxSourceFile.inline(
            'test/services/cache_data_preserving_test.dart',
            'cruxMigrationFixtureCases(runner: r, '
                'fixturesByVersion: lintcruxLintCacheMigrations);',
          ),
        ],
        storeMarkers: markers,
        subject: 'fixture',
      );
      expect(
        report.isClean,
        isFalse,
        reason:
            'another store having a suite is not this store having one, and '
            'the harness only ever fails for lists it was handed',
      );
    });

    test('green when a suite drives the harness over the store', () {
      final report = cruxAuditFixtureSuites(
        testSources: [
          CruxSourceFile.inline(
            'test/services/trends/trend_data_preserving_test.dart',
            'final runner = CruxMigrationRunner(migrations: '
                'lintcruxTrendStoreMigrations);\n'
                'for (final c in cruxMigrationFixtureCases(runner: runner)) {}',
          ),
        ],
        storeMarkers: markers,
        subject: 'fixture',
      );
      expect(report.isClean, isTrue, reason: report.describe());
      expect(report.observations.single.detail, contains('trend_data'));
    });

    test('RED when nothing in the tree calls the harness at all', () {
      final report = cruxAuditFixtureSuites(
        testSources: const [],
        storeMarkers: markers,
        subject: 'fixture',
      );
      expect(report.isClean, isFalse);
      expect(
        report.findings.map((f) => f.detail).join(),
        contains('passing vacuously'),
      );
    });
  });

  group('failure messages', () {
    test('name what broke, why, and the one way to green', () {
      final report = cruxAuditDestructiveDdl(
        sources: [_src("await db.execute('DROP TABLE runs');")],
        subject: 'fixture',
      );
      final message = report.describe();
      expect(message, contains('WHAT BROKE'));
      expect(message, contains('WHY THIS RULE EXISTS'));
      expect(message, contains('THE ONE LEGITIMATE WAY TO MAKE THIS GREEN'));
      expect(message, contains(kCruxMigrationGuideRef));
      expect(
        message,
        contains('Deleting or loosening a guard is never the fix'),
      );
    });
  });

  // The package holds itself to its own rules. This is where the one
  // sanctioned delete in the suite is checked against the real file rather
  // than against a fixture of it.
  //
  // Scope: the package's RUNTIME sources. `lib/src/guards/` is excluded
  // because a scanner necessarily contains the literal text of every pattern
  // it looks for — scanning it would flag the guard for describing the rule —
  // and `lib/src/testing/` is excluded because the fixture harness's job is to
  // open a historical database directly, without HEAD's open path.
  group("crux_sqlite's own runtime lib/", () {
    late final sources = cruxDartSourcesIn(
      Directory(p.join('lib', 'src')),
      relativeTo: '.',
      excludeSegments: const ['guards', 'testing'],
    );

    test('the scan is not vacuous', () {
      expect(sources, isNotEmpty);
      expect(
        sources.map((s) => s.path),
        contains(p.join('lib', 'src', 'crux_open_policy.dart')),
      );
      expect(
        sources.map((s) => s.path),
        isNot(
          contains(p.join('lib', 'src', 'guards', 'crux_guard_report.dart')),
        ),
      );
    });

    test('G3: no unwaived destructive DDL', () {
      final report = cruxAuditDestructiveDdl(
        sources: sources,
        subject: 'crux_sqlite/lib/src',
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test(
      'G4: the ONE delete in the package is the recreate arm, with no '
      'allowlist entry',
      () {
        final report = cruxAuditDatabaseDeletes(
          sources: sources,
          allowlist: const [],
          subject: 'crux_sqlite/lib/src',
        );
        expect(report.isClean, isTrue, reason: report.describe());
        expect(
          report.observations,
          hasLength(1),
          reason:
              'exactly one sanctioned delete site exists in the suite, and it '
              'is the DERIVABLE arm of the open policy. A second one appearing '
              'here is the thing to argue about.\n${report.describe()}',
        );
        expect(
          report.observations.single.location,
          startsWith(p.join('lib', 'src', 'crux_open_policy.dart')),
        );
      },
    );

    test('G5: every options object the package builds conforms', () {
      final report = cruxAuditOpenOptions(
        sources: sources,
        subject: 'crux_sqlite/lib/src',
        // The open policy IS the sanctioned route; its own two calls to the
        // factory are what everything else goes through.
        expectedDirectOpenFiles: {
          p.join('lib', 'src', 'crux_open_policy.dart'),
        },
      );
      expect(report.isClean, isTrue, reason: report.describe());
    });

    test('G5b: the package that owns the open catches DatabaseException', () {
      // The scanner turned on its own author. `CruxSqliteOpenPolicy.open` is
      // the root every other open site in the suite reduces to, and its
      // recovery arm is the one place in the package where a wrong catch
      // would reach a user's file — so if `on Object` were ever acceptable
      // anywhere, the argument for it would be made here first.
      final report = cruxAuditOpenCatchShapes(
        sources: sources,
        subject: 'crux_sqlite/lib/src',
      );
      expect(report.isClean, isTrue, reason: report.describe());
      expect(
        cruxOpenReachingEntryPoints(sources: sources),
        isEmpty,
        reason:
            'the package reaches sqflite directly, so its opens are the ROOTS '
            'rather than derived entry points. A derived name appearing here '
            'means crux_sqlite grew a store of its own',
      );
    });
  });
}
