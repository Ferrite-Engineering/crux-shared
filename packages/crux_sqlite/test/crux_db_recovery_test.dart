// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

CruxMigrationRunner _runner() => CruxMigrationRunner(
  storeName: 'test store',
  identity: CruxAppIdentity(product: 'testcrux', appVersion: '1.2.3'),
  migrations: [
    CruxMigration(
      version: 1,
      description: 'Create runs',
      apply: (db) => db.execute('CREATE TABLE runs (id INTEGER PRIMARY KEY)'),
    ),
    CruxMigration(
      version: 2,
      description: 'Index runs(id)',
      apply: (db) => db.execute('CREATE INDEX idx_runs_id ON runs(id)'),
    ),
  ],
);

/// The bytes of a file that is emphatically not a SQLite database.
const String _garbage = 'this is not a database, it is a text file\n';

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crux_sqlite_recovery_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  String dbPath() => p.join(tmp.path, 'trends.db');

  void writeCorruptFile() {
    File(dbPath()).writeAsStringSync(_garbage * 128);
  }

  List<File> corruptSiblings() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => p.basename(f.path).contains('.corrupt-'))
      .toList();

  group('a recovery that moves or deletes the file requires somewhere to say '
      'so', () {
    test('renameAside without a listener is rejected at construction', () {
      expect(
        () => CruxSqliteOpenPolicy(
          runner: _runner(),
          recovery: CruxDbRecovery.renameAside,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('recovery listener'), contains('refuse')),
          ),
        ),
      );
    });

    test('recreate without a listener is rejected too', () {
      expect(
        () => CruxSqliteOpenPolicy(
          runner: _runner(),
          recovery: CruxDbRecovery.recreate,
        ),
        throwsArgumentError,
      );
    });

    test('refuse needs no listener — it is the shape for a store with no '
        'diagnostics seam', () {
      expect(
        CruxSqliteOpenPolicy(
          runner: _runner(),
          recovery: CruxDbRecovery.refuse,
        ).recovery,
        CruxDbRecovery.refuse,
      );
    });
  });

  group('CruxDbRecovery.renameAside — PRECIOUS', () {
    test('the damaged bytes are preserved under a new name and a fresh '
        'database opens in their place', () async {
      writeCorruptFile();
      final original = File(dbPath()).readAsBytesSync();

      final notices = <CruxDatabaseCorruptionException>[];
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: notices.add,
      ).open(dbPath());
      addTearDown(db.close);

      final quarantined = corruptSiblings();
      expect(quarantined, hasLength(1));
      expect(
        quarantined.single.readAsBytesSync(),
        original,
        reason: 'every byte the user had is still on disk',
      );
      expect(await db.getVersion(), 2);
      expect(await db.query('runs'), isEmpty);
    });

    test('the quarantine stamp is ISO 8601 BASIC — colons are illegal in a '
        'Windows filename', () async {
      writeCorruptFile();
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: (_) {},
      ).open(dbPath());
      addTearDown(db.close);

      final name = p.basename(corruptSiblings().single.path);
      expect(name, matches(RegExp(r'^trends\.db\.corrupt-\d{8}T\d{6}Z$')));
      expect(name, isNot(contains(':')));
    });

    test('a second quarantine in the same second does not overwrite the '
        'first', () {
      File(dbPath()).writeAsStringSync('one');
      final first = quarantineDatabaseFile(
        dbPath(),
        now: DateTime.utc(2026, 8, 20, 9),
      );
      File(dbPath()).writeAsStringSync('two');
      final second = quarantineDatabaseFile(
        dbPath(),
        now: DateTime.utc(2026, 8, 20, 9),
      );

      expect(first, endsWith('trends.db.corrupt-20260820T090000Z'));
      expect(second, endsWith('trends.db.corrupt-20260820T090000Z-1'));
      expect(File(first!).readAsStringSync(), 'one');
      expect(File(second!).readAsStringSync(), 'two');
    });

    test('the -wal, -shm and -journal sidecars move with the main file', () {
      File(dbPath()).writeAsStringSync('main');
      for (final suffix in const ['-wal', '-shm', '-journal']) {
        File('${dbPath()}$suffix').writeAsStringSync(suffix);
      }

      final target = quarantineDatabaseFile(dbPath())!;

      for (final suffix in const ['-wal', '-shm', '-journal']) {
        expect(
          File('${dbPath()}$suffix').existsSync(),
          isFalse,
          reason:
              'a stale $suffix beside a fresh database of the same name is '
              'a second corruption waiting to happen',
        );
        expect(File('$target$suffix').readAsStringSync(), suffix);
      }
    });

    test('quarantineDatabaseFile returns null rather than throwing when the '
        'rename fails', () {
      expect(quarantineDatabaseFile(p.join(tmp.path, 'absent.db')), isNull);
    });

    test('the listener is told what happened, with both paths', () async {
      writeCorruptFile();
      final notices = <CruxDatabaseCorruptionException>[];
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: notices.add,
      ).open(dbPath());
      addTearDown(db.close);

      final notice = notices.single;
      expect(notice.recovery, CruxDbRecovery.renameAside);
      expect(notice.path, dbPath());
      expect(notice.quarantinedPath, corruptSiblings().single.path);
      expect(notice.cause, isA<DatabaseException>());
      expect(notice.storeName, 'test store');
      expect(notice.toString(), contains('moved aside'));
    });

    test('the reopened database is a fully migrated one, not a bare open — '
        'the retry uses the same options as the first attempt', () async {
      writeCorruptFile();
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: (_) {},
      ).open(dbPath());
      addTearDown(db.close);

      // If the retry had been a second, hand-rolled options object, this is
      // where the difference would show: a version but no onCreate, or a
      // version and no onDowngrade.
      expect(await db.getVersion(), 2);
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_runs_id'",
      );
      expect(indexes, hasLength(1));
    });

    test('the recovered file still refuses a downgrade — onDowngrade did not '
        'go missing on the retry', () async {
      writeCorruptFile();
      final recovered = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: (_) {},
      ).open(dbPath());
      await recovered.close();

      final older = CruxSqliteOpenPolicy(
        runner: CruxMigrationRunner(
          storeName: 'test store',
          identity: CruxAppIdentity(product: 'testcrux', appVersion: '0.1.0'),
          migrations: [_runner().migrationFor(1)],
        ),
        recovery: CruxDbRecovery.refuse,
      );
      await expectLater(
        older.open(dbPath()),
        throwsA(isA<CruxSchemaVersionSkewException>()),
      );

      final reopened = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.refuse,
      ).open(dbPath());
      addTearDown(reopened.close);
      expect(await reopened.getVersion(), 2);
    });
  });

  group('CruxDbRecovery.recreate — DERIVABLE', () {
    test('the file is replaced and the listener is told, with no quarantine '
        'path', () async {
      writeCorruptFile();
      final notices = <CruxDatabaseCorruptionException>[];
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.recreate,
        onRecovery: notices.add,
      ).open(dbPath());
      addTearDown(db.close);

      expect(await db.getVersion(), 2);
      expect(corruptSiblings(), isEmpty);
      expect(notices.single.recovery, CruxDbRecovery.recreate);
      expect(notices.single.quarantinedPath, isNull);
      expect(notices.single.toString(), contains('derivable'));
    });
  });

  group('CruxDbRecovery.refuse — PRECIOUS, with nowhere to say so', () {
    test('it throws the typed corruption and destroys nothing', () async {
      writeCorruptFile();
      final before = File(dbPath()).readAsBytesSync();

      await expectLater(
        CruxSqliteOpenPolicy(
          runner: _runner(),
          recovery: CruxDbRecovery.refuse,
        ).open(dbPath()),
        throwsA(
          isA<CruxDatabaseCorruptionException>()
              .having((e) => e.recovery, 'recovery', CruxDbRecovery.refuse)
              .having((e) => e.quarantinedPath, 'quarantinedPath', isNull)
              .having((e) => e.path, 'path', dbPath()),
        ),
      );

      expect(File(dbPath()).readAsBytesSync(), before);
      expect(corruptSiblings(), isEmpty);
    });

    test('the message says the bytes are still there', () async {
      writeCorruptFile();
      final error =
          await CruxSqliteOpenPolicy(
            runner: _runner(),
            recovery: CruxDbRecovery.refuse,
          ).open(dbPath()).then<Object?>((db) async {
            await db.close();
            return null;
          }, onError: (Object e) => e);

      expect(error.toString(), contains('every byte is still there'));
    });
  });

  group('an open failure that is NOT corruption triggers no recovery at '
      'all', () {
    // The heart of the whole package. `SQLITE_CANTOPEN` — like `SQLITE_BUSY`,
    // `SQLITE_LOCKED` and `SQLITE_READONLY` — is a `DatabaseException` raised
    // about a file that is completely fine. Every one of them used to reach a
    // handler that deleted it, and lock contention read as corruption is how a
    // Pro user lost their entire violation history.
    //
    // A directory standing where the database should be produces
    // `SQLITE_CANTOPEN` reliably on every platform, without needing two
    // processes to race for a lock.
    String unopenablePath() {
      final path = p.join(tmp.path, 'in-the-way.db');
      Directory(path).createSync();
      return path;
    }

    test('under renameAside it propagates untouched, with no quarantine and '
        'no notice', () async {
      final notices = <CruxDatabaseCorruptionException>[];
      final policy = CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: notices.add,
      );

      final error = await policy.open(unopenablePath()).then<Object?>(
        (db) async {
          await db.close();
          return null;
        },
        onError: (Object e) => e,
      );

      expect(error, isA<DatabaseException>());
      expect(
        error,
        isNot(isA<CruxSqliteException>()),
        reason: 'it is not one of the three faults; it is a busy/absent file',
      );
      expect(isSqliteCorruption(error!), isFalse);
      expect(notices, isEmpty);
      expect(corruptSiblings(), isEmpty);
    });

    test('under recreate nothing is deleted either', () async {
      final policy = CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.recreate,
        onRecovery: (_) => fail('a healthy file must trigger no recovery'),
      );
      await expectLater(
        policy.open(unopenablePath()),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a healthy database next door is left alone while an unopenable '
        'sibling fails', () async {
      // Belt and braces on the quarantine target: a recovery that fired here
      // would rename the wrong file.
      final good = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.refuse,
      ).open(dbPath());
      await good.insert('runs', {'id': 1});
      await good.close();

      await expectLater(
        CruxSqliteOpenPolicy(
          runner: _runner(),
          recovery: CruxDbRecovery.renameAside,
          onRecovery: (_) => fail('no recovery may run'),
        ).open(unopenablePath()),
        throwsA(isA<DatabaseException>()),
      );

      final reopened = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.refuse,
      ).open(dbPath());
      addTearDown(reopened.close);
      expect(await reopened.query('runs'), [
        {'id': 1},
      ]);
      expect(corruptSiblings(), isEmpty);
    });
  });

  group('an in-memory database has nothing to recover', () {
    test('no recovery path applies to it', () async {
      final db = await CruxSqliteOpenPolicy(
        runner: _runner(),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: (_) => fail('an in-memory database cannot be quarantined'),
      ).open(inMemoryDatabasePath);
      addTearDown(db.close);
      expect(await db.getVersion(), 2);
    });
  });
}
