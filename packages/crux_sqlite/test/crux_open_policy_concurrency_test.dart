// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:crux_sqlite/crux_sqlite_test_support.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:test/test.dart';

/// Proves the concurrency model the package README states under "Concurrency
/// and version skew": a second opener that meets a migration mid-flight waits
/// behind `busy_timeout` and then succeeds against the fully migrated file — it
/// never sees a partial schema and it never trips any recovery/wipe path.
/// Proved once, here, against the shared open policy: every one of the four
/// Crux SQLite databases opens through this exact code, so this is the one
/// place the property needs proving.
///
/// The second connection has to be a genuinely separate native SQLite
/// connection, not a second in-process `openDatabase` call — `sqflite_common`
/// serializes those behind its own per-path Dart `Lock`
/// (`cruxOpenSecondConnectionVersion`'s doc comment has the detail), which
/// would just queue rather than exercise `SQLITE_BUSY`. So the second
/// opener runs in its own isolate.
///
/// Timing between the two connections is synchronized through a sentinel
/// file: the (test-only, never-shipped) slow migration writes it the instant
/// it has the exclusive lock, and only then does the test start the second
/// opener — so the second connection is provably attempting to open *while*
/// the first is mid-migration, not merely racing it.
void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crux_concurrency_');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
    'a second opener during a migration waits and then succeeds, and '
    'triggers no recovery path',
    () async {
      final dbPath = p.join(tmp.path, 'trends.db');
      final sentinel = File(p.join(tmp.path, 'migration-locked'));

      // Build a v1 file first, matching the live scenario: an upgrade, not
      // a fresh install, is what a concurrent opener meets in the field.
      final v1Runner = CruxMigrationRunner(
        storeName: 'concurrency test store',
        identity: CruxAppIdentity(product: 'testcrux', appVersion: '1.0.0'),
        migrations: [
          CruxMigration(
            version: 1,
            description: 'Create widgets',
            apply: (db) => db.execute(
              'CREATE TABLE widgets (id INTEGER PRIMARY KEY)',
            ),
          ),
        ],
      );
      final seed = await CruxSqliteOpenPolicy(
        runner: v1Runner,
        recovery: CruxDbRecovery.refuse,
      ).open(dbPath);
      await seed.close();

      // The v1 -> v2 runner used for the actual test: v2 deliberately holds
      // the exclusive migration transaction open for a while, so there is a
      // wide, deterministic window for the second connection to meet it.
      final slowRunner = CruxMigrationRunner(
        storeName: v1Runner.storeName,
        identity: v1Runner.identity,
        migrations: [
          v1Runner.migrations.single,
          CruxMigration(
            version: 2,
            description: 'Add widgets.label slowly, on purpose (test only)',
            apply: (db) async {
              await db.execute(
                "ALTER TABLE widgets ADD COLUMN label TEXT NOT NULL DEFAULT ''",
              );
              // Only after a real DDL statement has actually run — proving
              // the exclusive lock is held — do we signal the second
              // connection to try its luck.
              await sentinel.writeAsString('locked');
              await Future<void>.delayed(const Duration(milliseconds: 600));
            },
          ),
        ],
      );

      final notices = <CruxDatabaseCorruptionException>[];
      final policy = CruxSqliteOpenPolicy(
        runner: slowRunner,
        recovery: CruxDbRecovery.renameAside,
        onRecovery: notices.add,
      );

      final migrateFuture = policy.open(dbPath);

      // Wait for the migration to actually acquire its lock before the
      // second connection tries — otherwise this test could pass for the
      // wrong reason (the second connection simply winning a race to open
      // first, before any lock existed at all).
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!sentinel.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the test migration never signalled that it holds the lock');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // The second, genuinely independent connection — must block behind
      // busy_timeout, not fail immediately with SQLITE_BUSY.
      final secondOpenStarted = DateTime.now();
      final secondVersion = await cruxOpenSecondConnectionVersion(dbPath);
      final secondOpenElapsed = DateTime.now().difference(secondOpenStarted);

      final migrated = await migrateFuture;
      addTearDown(migrated.close);

      expect(
        secondVersion,
        2,
        reason:
            'the second connection must see the FULLY migrated file — a '
            'busy_timeout wait resolves into success against the finished '
            'schema, never a partial one',
      );
      expect(
        secondOpenElapsed,
        greaterThan(const Duration(milliseconds: 300)),
        reason:
            'this must be a genuine busy_timeout wait, not a lucky race — '
            'the migration holds its exclusive lock for ~600ms after the '
            'sentinel fires, so a second connection that opened instantly '
            'would prove nothing about waiting at all',
      );
      expect(await migrated.getVersion(), 2);
      expect(
        notices,
        isEmpty,
        reason:
            'SQLITE_BUSY from a concurrent opener is a busy, healthy '
            'database, never corruption — it must not trigger any recovery '
            'or wipe path',
      );
      expect(
        tmp
            .listSync()
            .map((e) => p.basename(e.path))
            .where((name) => name.contains('.corrupt-')),
        isEmpty,
        reason: 'nothing was quarantined',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
