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

CruxMigration _createRuns() => CruxMigration(
  version: 1,
  description: 'Create runs',
  apply: (db) => db.execute('CREATE TABLE runs (id INTEGER PRIMARY KEY)'),
);

CruxMigration _addLabel() => CruxMigration(
  version: 2,
  description: 'Add runs.label with a default',
  apply: (db) =>
      db.execute("ALTER TABLE runs ADD COLUMN label TEXT NOT NULL DEFAULT ''"),
);

CruxMigrationRunner _runner(List<CruxMigration> migrations) =>
    CruxMigrationRunner(
      storeName: 'test store',
      migrations: migrations,
      identity: CruxAppIdentity(product: 'testcrux', appVersion: '1.2.3'),
    );

CruxSqliteOpenPolicy _policy(
  List<CruxMigration> migrations, {
  CruxDbRecovery recovery = CruxDbRecovery.refuse,
}) => CruxSqliteOpenPolicy(runner: _runner(migrations), recovery: recovery);

Future<Set<String>> _columnsOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {for (final row in rows) row['name']! as String};
}

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crux_sqlite_open_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  String dbPath() => p.join(tmp.path, 'trends.db');

  group('the options object is total — a non-conforming one is not '
      'expressible', () {
    test('the version comes from the runner, never from the caller', () {
      final policy = _policy([_createRuns(), _addLabel()]);
      expect(policy.buildOptions(path: '/tmp/x.db').version, 2);
      expect(
        policy.buildOptions(path: '/tmp/x.db').version,
        policy.runner.latestVersion,
      );
    });

    test(
      'onCreate, onUpgrade, onDowngrade and onConfigure are all present',
      () {
        // G5's exact conformance check. There is no parameter that omits any of
        // them, which is why the guard has one legitimate way to go green:
        // open through this policy.
        final options = _policy([
          _createRuns(),
        ]).buildOptions(path: '/tmp/x.db');
        expect(options.onCreate, isNotNull);
        expect(options.onUpgrade, isNotNull);
        expect(
          options.onDowngrade,
          isNotNull,
          reason: 'omitting it stamps user_version DOWN in silence',
        );
        expect(options.onConfigure, isNotNull);
      },
    );

    test('onMigrationStart fires on both onCreate and onUpgrade', () async {
      // It is how a caller learns a failure came from INSIDE the version
      // transaction — our bug, on a file that has already rolled back — rather
      // than from the open itself. `open()` relies on it; a caller doing its
      // own open must wire it too, so it must not silently stop firing.
      final calls = <String>[];

      final created = await databaseFactory.openDatabase(
        dbPath(),
        options:
            _policy([
              _createRuns(),
            ]).buildOptions(
              path: dbPath(),
              onMigrationStart: () => calls.add('create'),
            ),
      );
      await created.close();
      expect(calls, ['create']);

      final upgraded = await databaseFactory.openDatabase(
        dbPath(),
        options: _policy([_createRuns(), _addLabel()]).buildOptions(
          path: dbPath(),
          onMigrationStart: () => calls.add('upgrade'),
        ),
      );
      addTearDown(upgraded.close);
      expect(calls, ['create', 'upgrade']);
    });

    test(
      'busy_timeout is actually in force on the opened connection',
      () async {
        final db = await _policy([_createRuns()]).open(inMemoryDatabasePath);
        addTearDown(db.close);
        final rows = await db.rawQuery('PRAGMA busy_timeout');
        expect(
          rows.single.values.single,
          kCruxSqliteBusyTimeout.inMilliseconds,
        );
        expect(kCruxSqliteBusyTimeout, const Duration(milliseconds: 5000));
      },
    );

    test(
      'foreign-key enforcement stays off — the ruling, not an oversight',
      () async {
        // A no-op inside a transaction, and sqflite runs every migration inside
        // an exclusive one, so enforcement would make the 12-step rebuild
        // impossible from inside this shared open path.
        final db = await _policy([_createRuns()]).open(inMemoryDatabasePath);
        addTearDown(db.close);
        final rows = await db.rawQuery('PRAGMA foreign_keys');
        expect(rows.single.values.single, 0);
      },
    );
  });

  group('a fresh install and an upgraded install converge', () {
    test('onCreate runs the whole list from 0', () async {
      final db = await _policy([_createRuns(), _addLabel()]).open(dbPath());
      addTearDown(db.close);
      expect(await _columnsOf(db, 'runs'), {'id', 'label'});
      expect(await db.getVersion(), 2);
    });

    test('an upgraded v1 file reaches the identical schema', () async {
      final v1 = await _policy([_createRuns()]).open(dbPath());
      await v1.insert('runs', {'id': 1});
      await v1.close();

      final v2 = await _policy([_createRuns(), _addLabel()]).open(dbPath());
      addTearDown(v2.close);
      expect(await _columnsOf(v2, 'runs'), {'id', 'label'});
      expect(await v2.getVersion(), 2);
      expect(
        await v2.query('runs'),
        [
          {'id': 1, 'label': ''},
        ],
        reason: 'the pre-existing row survives with the declared default',
      );
    });
  });

  group('downgrade is refused, and nothing is written', () {
    test(
      'an older build meeting a newer file gets a typed skew error',
      () async {
        final newer = await _policy([
          _createRuns(),
          _addLabel(),
        ]).open(dbPath());
        await newer.insert('runs', {'id': 7, 'label': 'keep me'});
        await newer.close();

        await expectLater(
          _policy([_createRuns()]).open(dbPath()),
          throwsA(
            isA<CruxSchemaVersionSkewException>()
                .having((e) => e.fileVersion, 'fileVersion', 2)
                .having((e) => e.appVersion, 'appVersion', 1)
                .having((e) => e.path, 'path', dbPath()),
          ),
        );
      },
    );

    test(
      'the refused file keeps its version, its schema and its rows',
      () async {
        final newer = await _policy([
          _createRuns(),
          _addLabel(),
        ]).open(dbPath());
        await newer.insert('runs', {'id': 7, 'label': 'keep me'});
        await newer.close();

        await _policy(
          [_createRuns()],
        ).open(dbPath()).then<void>((db) => db.close(), onError: (Object _) {});

        final reopened = await _policy([
          _createRuns(),
          _addLabel(),
        ]).open(dbPath());
        addTearDown(reopened.close);
        expect(
          await reopened.getVersion(),
          2,
          reason: 'omitting onDowngrade would have stamped this back to 1',
        );
        expect(await reopened.query('runs'), [
          {'id': 7, 'label': 'keep me'},
        ]);
      },
    );

    test('a downgrade never quarantines or deletes, whatever the recovery '
        'policy says', () async {
      final quarantined = <CruxDatabaseCorruptionException>[];
      final newer = await _policy([_createRuns(), _addLabel()]).open(dbPath());
      await newer.close();

      final older = CruxSqliteOpenPolicy(
        runner: _runner([_createRuns()]),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: quarantined.add,
      );
      await expectLater(
        older.open(dbPath()),
        throwsA(isA<CruxSchemaVersionSkewException>()),
      );
      expect(quarantined, isEmpty);
      expect(_corruptSiblings(tmp), isEmpty);
      expect(File(dbPath()).existsSync(), isTrue);
    });
  });

  group('a failing migration never reaches a recovery path — the F1 fix', () {
    test('it propagates as CruxMigrationFailedException', () async {
      final v1 = await _policy([_createRuns()]).open(dbPath());
      await v1.insert('runs', {'id': 1});
      await v1.close();

      await expectLater(
        _policy([
          _createRuns(),
          const CruxMigration(
            version: 2,
            description: 'Add the label column',
            apply: _boom,
          ),
        ]).open(dbPath()),
        throwsA(
          isA<CruxMigrationFailedException>()
              .having((e) => e.version, 'version', 2)
              .having((e) => e.fromVersion, 'fromVersion', 1),
        ),
      );
    });

    test('the file is untouched: same version, same rows, no quarantine, no '
        'delete — even under renameAside', () async {
      final v1 = await _policy([_createRuns()]).open(dbPath());
      await v1.insert('runs', {'id': 1});
      await v1.close();

      final notices = <CruxDatabaseCorruptionException>[];
      final broken = CruxSqliteOpenPolicy(
        runner: _runner([
          _createRuns(),
          const CruxMigration(
            version: 2,
            description: 'Add label',
            apply: _boom,
          ),
        ]),
        recovery: CruxDbRecovery.renameAside,
        onRecovery: notices.add,
      );

      await expectLater(
        broken.open(dbPath()),
        throwsA(isA<CruxMigrationFailedException>()),
      );

      expect(notices, isEmpty, reason: 'our bug is not the file being damaged');
      expect(_corruptSiblings(tmp), isEmpty);

      final reopened = await _policy([_createRuns()]).open(dbPath());
      addTearDown(reopened.close);
      expect(
        await reopened.getVersion(),
        1,
        reason: 'the transaction rolled back',
      );
      expect(await reopened.query('runs'), [
        {'id': 1},
      ]);
    });

    test('the same is true under recreate — a derivable store still must not '
        'wipe on OUR bug', () async {
      final v1 = await _policy([_createRuns()]).open(dbPath());
      await v1.insert('runs', {'id': 42});
      await v1.close();

      final broken = CruxSqliteOpenPolicy(
        runner: _runner([
          _createRuns(),
          const CruxMigration(
            version: 2,
            description: 'Add label',
            apply: _boom,
          ),
        ]),
        recovery: CruxDbRecovery.recreate,
        onRecovery: (_) {},
      );
      await expectLater(
        broken.open(dbPath()),
        throwsA(isA<CruxMigrationFailedException>()),
      );

      final reopened = await _policy([_createRuns()]).open(dbPath());
      addTearDown(reopened.close);
      expect(await reopened.query('runs'), [
        {'id': 42},
      ]);
    });
  });

  group('reported paths', () {
    test('a relative path is absolutised in the failure it names', () async {
      // A relative `--db` argument resolved against a CI runner's working
      // directory names nothing a user can find.
      final newer = await _policy([_createRuns(), _addLabel()]).open(dbPath());
      await newer.close();

      final relative = p.relative(dbPath(), from: Directory.current.path);
      expect(p.isAbsolute(relative), isFalse, reason: 'premise of the test');

      final error = await _policy([_createRuns()]).open(relative).then<Object?>(
        (db) async {
          await db.close();
          return null;
        },
        onError: (Object e) => e,
      );

      expect(error, isA<CruxSchemaVersionSkewException>());
      final path = (error! as CruxSqliteException).path;
      expect(p.isAbsolute(path), isTrue);
      expect(p.equals(path, dbPath()), isTrue);
    });
  });
}

List<String> _corruptSiblings(Directory dir) => dir
    .listSync()
    .map((e) => p.basename(e.path))
    .where((name) => name.contains('.corrupt-'))
    .toList();

Future<void> _boom(Database db) async => throw StateError('migration bug');
