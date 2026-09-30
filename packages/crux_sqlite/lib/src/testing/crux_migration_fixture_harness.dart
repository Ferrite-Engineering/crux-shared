// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_sqlite/src/crux_db_recovery.dart';
import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/crux_open_policy.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

/// Seeds raw rows into a database frozen at exactly [version]'s schema.
///
/// **Raw SQL only** — `db.execute` / `db.rawInsert` / `db.insert` against
/// table and column names spelled out by hand, never a repository class. A
/// repository only ever knows the *current* schema, so seeding through one
/// would make the fixture drift forward with the code instead of staying
/// frozen at [version] — the entire property this harness exists to protect.
/// Because migrations are append-only and additive-only, running the
/// migration list from 0 to [version] alone *is* the historical schema by
/// definition, which is why this is sound, and it stops being sound the day
/// someone edits a shipped migration (README, rule 1 and "Adding a
/// migration", step 5).
typedef CruxFixtureSeed = Future<void> Function(Database db, int version);

/// Asserts what upgrading a [version] fixture to HEAD must have preserved.
///
/// Receives the fully migrated [migrated] — opened through the real
/// production [CruxSqliteOpenPolicy], not a bare `openDatabase` — the
/// historical [version] the fixture started from, and [dbPath] so the
/// assertion can additionally open the product's own repository class on the
/// same file and prove the round trip through it: the data reading back
/// correctly through the API a user actually exercises.
///
/// Expected to check, at minimum: row counts unchanged; the *values* of
/// every pre-existing column unchanged field by field (not just counted);
/// new columns holding their declared default or their backfilled value;
/// and every index the head schema declares present.
typedef CruxFixtureAssert =
    Future<void> Function(Database migrated, int version, String dbPath);

/// One store's complete data-preserving coverage for one historical version:
/// what to seed there, and what must still be true after upgrading to HEAD.
@immutable
final class CruxMigrationFixture {
  /// Creates a [CruxMigrationFixture].
  const CruxMigrationFixture({
    required this.seed,
    required this.assertAfterUpgrade,
  });

  /// Populates the vN fixture, in raw SQL.
  final CruxFixtureSeed seed;

  /// Checks what survived the upgrade to HEAD.
  final CruxFixtureAssert assertAfterUpgrade;
}

/// One data-preserving-migration test, ready to hand to a test framework —
/// `test(case.name, case.run)` in `package:test` or `package:flutter_test`
/// alike.
///
/// A plain data class rather than this package calling `test()` itself:
/// `crux_sqlite` is pure Dart and stays that way even in its test-support
/// surface (this library is exported from its own secondary barrel,
/// `crux_sqlite_test_support.dart`, precisely so it never has to choose a
/// test framework), and three of the four databases this harness covers are
/// exercised from `flutter_test` files. [run] reports failure the same way
/// every test framework in the suite already treats an uncaught exception
/// from a test body — by throwing — so nothing here needs `test`,
/// `flutter_test`, or `expect`.
@immutable
final class CruxMigrationFixtureCase {
  /// Creates a [CruxMigrationFixtureCase].
  const CruxMigrationFixtureCase({required this.name, required this.run});

  /// A name suitable for `test(name, run)`.
  final String name;

  /// Runs the case. Throws on any violated property, including a missing
  /// fixture for this version.
  final Future<void> Function() run;
}

/// Builds one [CruxMigrationFixtureCase] per version in [runner]'s migration
/// list — the loop every store's data-preserving suite shares, so that
/// appending a migration automatically adds its own coverage requirement
/// rather than leaving four copy-pasted per-version tests to keep in sync.
///
/// For each version 1..[CruxMigrationRunner.latestVersion]:
///
///  1. Builds the historical vN fixture by running [runner] alone from 0 to
///     N, bypassing the open policy entirely — nothing about HEAD (no
///     backup, no `schema_meta` open-stamp) leaks into what is supposed to
///     be a frozen historical file.
///  2. Hands that database to the registered [CruxMigrationFixture.seed] for
///     that version.
///  3. Reopens the same file through the real production
///     [CruxSqliteOpenPolicy] — the exact path a user's upgrade takes,
///     backup included — up to [CruxMigrationRunner.latestVersion].
///  4. Hands the migrated database to
///     [CruxMigrationFixture.assertAfterUpgrade].
///
/// **A version with no entry in [fixturesByVersion] still gets a case** —
/// one that throws the instant it runs, naming the missing version. That is
/// what makes "shipped a migration, forgot the fixture" a red test rather
/// than a suite that silently stopped growing (guard G6).
///
/// [recovery] and [onRecovery] must match what the store actually opens
/// with — the same values passed to the store's own `CruxSqliteOpenPolicy` —
/// so the fixture proves the path a user's file really takes, not a
/// friendlier stand-in for it.
List<CruxMigrationFixtureCase> cruxMigrationFixtureCases({
  required CruxMigrationRunner runner,
  required CruxDbRecovery recovery,
  required Map<int, CruxMigrationFixture> fixturesByVersion,
  CruxDbRecoveryListener? onRecovery,
}) {
  return <CruxMigrationFixtureCase>[
    for (var version = 1; version <= runner.latestVersion; version++)
      CruxMigrationFixtureCase(
        name:
            '${runner.storeName}: v$version fixture survives the upgrade to '
            'HEAD (v${runner.latestVersion})',
        run: () => _runFixtureCase(
          runner: runner,
          recovery: recovery,
          onRecovery: onRecovery,
          version: version,
          fixture: fixturesByVersion[version],
        ),
      ),
  ];
}

Future<void> _runFixtureCase({
  required CruxMigrationRunner runner,
  required CruxDbRecovery recovery,
  required CruxDbRecoveryListener? onRecovery,
  required int version,
  required CruxMigrationFixture? fixture,
}) async {
  if (fixture == null) {
    throw StateError(
      'no data-preserving fixture registered for schema v$version of '
      '${runner.storeName} (latest is v${runner.latestVersion}). Every '
      'shipped version needs one — see '
      '$kCruxMigrationGuideRef, "Adding a migration", step 5. Add '
      'fixturesByVersion[$version] rather than leave this version unproven.',
    );
  }

  final tmp = await Directory.systemTemp.createTemp(
    'crux_fixture_v${version}_',
  );
  try {
    final dbPath = p.join(tmp.path, 'fixture.db');

    // 1 & 2: the historical file, built by the runner ALONE — no backup, no
    // schema_meta open-stamp, nothing HEAD's open path would add that the
    // shipped version itself did not produce.
    final built = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA busy_timeout = 5000'),
        onCreate: (db, v) => runner.upgrade(db, 0, v, reportPath: dbPath),
      ),
    );
    try {
      await fixture.seed(built, version);
    } finally {
      await built.close();
    }

    // 3: the real production open path — backup, ledger, recovery policy,
    // all of it, exactly as a user's upgrade experiences it.
    final policy = CruxSqliteOpenPolicy(
      runner: runner,
      recovery: recovery,
      onRecovery: onRecovery,
    );
    final migrated = await policy.open(dbPath);
    try {
      final reached = await migrated.getVersion();
      if (reached != runner.latestVersion) {
        throw StateError(
          'v$version fixture opened but reached v$reached, not HEAD '
          '(v${runner.latestVersion}) for ${runner.storeName}',
        );
      }
      // 4.
      await fixture.assertAfterUpgrade(migrated, version, dbPath);
    } finally {
      await migrated.close();
    }
  } finally {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  }
}
