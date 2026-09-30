// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

CruxMigration _noop(int version) => CruxMigration(
  version: version,
  description: 'v$version does nothing',
  apply: (_) async {},
);

CruxMigration _createTable(int version, String table) => CruxMigration(
  version: version,
  description: 'Create $table',
  apply: (db) => db.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)'),
);

CruxMigrationRunner _runner(List<CruxMigration> migrations) =>
    CruxMigrationRunner(
      storeName: 'test store',
      migrations: migrations,
      identity: CruxAppIdentity(product: 'testcrux', appVersion: '1.2.3'),
    );

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  group('the list is validated at construction, not at open', () {
    test('an empty list is rejected', () {
      // latestVersion 0 is "no version" to sqflite: onCreate never runs and
      // the store opens with no schema at all.
      expect(
        () => _runner(const []),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('at least one migration'),
          ),
        ),
      );
    });

    test('a gap in the versions is rejected', () {
      expect(
        () => _runner([_noop(1), _noop(3)]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('contiguous from 1'), contains('v3')),
          ),
        ),
      );
    });

    test('a duplicate version is rejected', () {
      expect(() => _runner([_noop(1), _noop(1)]), throwsArgumentError);
    });

    test('a list that does not start at 1 is rejected', () {
      expect(() => _runner([_noop(0), _noop(1)]), throwsArgumentError);
    });

    test('a blank description is rejected', () {
      expect(
        () => _runner([
          const CruxMigration(version: 1, description: '  ', apply: _blank),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('blank description'),
          ),
        ),
      );
    });

    test(
      'rejection is a throw, not an assert — it survives a release build',
      () {
        // The check must not be inside `assert`, which is stripped in release.
        // Nothing in this test asserts that directly; it documents why the
        // implementation throws, and the throws above are the evidence that it
        // does not rely on assertions being enabled.
        expect(() => _runner([_noop(2)]), throwsArgumentError);
      },
    );
  });

  group('the latest version is derived, never declared', () {
    test('latestVersion is the list length', () {
      expect(_runner([_noop(1)]).latestVersion, 1);
      expect(_runner([_noop(1), _noop(2), _noop(3)]).latestVersion, 3);
    });

    test('appending a migration IS the version bump', () {
      final before = _runner([_noop(1), _noop(2)]);
      final after = _runner([_noop(1), _noop(2), _noop(3)]);
      expect(after.latestVersion, before.latestVersion + 1);
    });

    test('migrationFor indexes by version, 1-based', () {
      final runner = _runner([_noop(1), _noop(2)]);
      expect(runner.migrationFor(1).version, 1);
      expect(runner.migrationFor(2).description, 'v2 does nothing');
      expect(() => runner.migrationFor(0), throwsRangeError);
      expect(() => runner.migrationFor(3), throwsRangeError);
    });

    test(
      'the migration list is frozen against mutation after construction',
      () {
        final source = [_noop(1)];
        final runner = _runner(source);
        source.add(_noop(2));
        expect(runner.latestVersion, 1, reason: 'the runner took a copy');
        expect(() => runner.migrations.add(_noop(2)), throwsUnsupportedError);
      },
    );
  });

  group('the upgrade loop', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async => db.close());

    test('runs exactly the migrations in (old, new]', () async {
      final applied = <int>[];
      final runner = _runner([
        for (var v = 1; v <= 4; v++)
          CruxMigration(
            version: v,
            description: 'v$v',
            apply: (_) async => applied.add(v),
          ),
      ]);

      await runner.upgrade(db, 1, 3);
      expect(applied, [2, 3]);
    });

    test(
      'an upgrade from 0 runs everything — a fresh install converges',
      () async {
        final applied = <int>[];
        final runner = _runner([
          for (var v = 1; v <= 3; v++)
            CruxMigration(
              version: v,
              description: 'v$v',
              apply: (_) async => applied.add(v),
            ),
        ]);

        await runner.upgrade(db, 0, runner.latestVersion);
        expect(applied, [1, 2, 3]);
      },
    );

    test('a no-op upgrade runs nothing', () async {
      final applied = <int>[];
      final runner = _runner([
        CruxMigration(
          version: 1,
          description: 'v1',
          apply: (_) async => applied.add(1),
        ),
      ]);

      await runner.upgrade(db, 1, 1);
      expect(applied, isEmpty);
    });

    test('asking for a version past the list is a caller bug', () async {
      final runner = _runner([_noop(1)]);
      await expectLater(
        runner.upgrade(db, 0, 2),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('stops at v1'),
          ),
        ),
      );
    });
  });

  group('downgrade is rejected with a typed error, never accommodated', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async => db.close());

    test('upgrade() refuses when old > new', () async {
      final runner = _runner([_noop(1), _noop(2), _noop(3)]);
      await expectLater(
        runner.upgrade(db, 3, 2),
        throwsA(
          isA<CruxSchemaVersionSkewException>()
              .having((e) => e.fileVersion, 'fileVersion', 3)
              .having((e) => e.appVersion, 'appVersion', 2)
              .having((e) => e.storeName, 'storeName', 'test store'),
        ),
      );
    });

    test('it runs no migration on the way to refusing', () async {
      final applied = <int>[];
      final runner = _runner([
        for (var v = 1; v <= 3; v++)
          CruxMigration(
            version: v,
            description: 'v$v',
            apply: (_) async => applied.add(v),
          ),
      ]);

      await expectLater(
        runner.upgrade(db, 3, 1),
        throwsA(isA<CruxSchemaVersionSkewException>()),
      );
      expect(applied, isEmpty, reason: 'nothing may be written to the file');
    });

    test('the message names both versions and says nothing was lost', () async {
      final runner = _runner([_noop(1)]);
      final error = await runner
          .upgrade(db, 4, 1, reportPath: '/tmp/trends.db')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(
        error.toString(),
        allOf(
          contains('v4'),
          contains('v1'),
          contains('/tmp/trends.db'),
          contains('no data has been lost'),
        ),
      );
    });
  });

  group('a failing migration is a bug report, not a recovery case', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async => db.close());

    test(
      'it is wrapped, naming the version and description that failed',
      () async {
        final runner = _runner([
          _createTable(1, 'alpha'),
          const CruxMigration(
            version: 2,
            description: 'Add the beta column',
            apply: _boom,
          ),
        ]);

        await expectLater(
          runner.upgrade(db, 0, 2, reportPath: '/tmp/trends.db'),
          throwsA(
            isA<CruxMigrationFailedException>()
                .having((e) => e.version, 'version', 2)
                .having(
                  (e) => e.description,
                  'description',
                  'Add the beta column',
                )
                .having((e) => e.fromVersion, 'fromVersion', 0)
                .having((e) => e.toVersion, 'toVersion', 2)
                .having((e) => e.path, 'path', '/tmp/trends.db')
                .having((e) => e.cause, 'cause', isA<StateError>()),
          ),
        );
      },
    );

    test(
      'a real SQL error is wrapped too — it does not escape as a raw '
      'DatabaseException that a naive catch would read as corruption',
      () async {
        final runner = _runner([
          _createTable(1, 'alpha'),
          // A duplicate CREATE: exactly the shape of a real migration typo.
          _createTable(2, 'alpha'),
        ]);

        await expectLater(
          runner.upgrade(db, 0, 2),
          throwsA(
            isA<CruxMigrationFailedException>().having(
              (e) => e.cause,
              'cause',
              isA<DatabaseException>(),
            ),
          ),
        );
      },
    );

    test('a migration failure is not corruption', () async {
      final runner = _runner([
        _createTable(1, 'alpha'),
        _createTable(2, 'alpha'),
      ]);
      final error = await runner
          .upgrade(db, 0, 2)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<CruxMigrationFailedException>());
      expect(
        isSqliteCorruption(error!),
        isFalse,
        reason: 'our bug must never be triaged as a damaged file',
      );
    });

    test(
      'the message says the file is unchanged and names the version',
      () async {
        final runner = _runner([
          _createTable(1, 'alpha'),
          const CruxMigration(
            version: 2,
            description: 'Add beta',
            apply: _boom,
          ),
        ]);
        final error = await runner
            .upgrade(db, 1, 2)
            .then<Object?>((_) => null, onError: (Object e) => e);
        expect(
          error.toString(),
          allOf(
            contains('migration v2'),
            contains('bug in the migration'),
            contains('unchanged at v1'),
          ),
        );
      },
    );
  });
}

Future<void> _blank(Database db) async {}

Future<void> _boom(Database db) async => throw StateError('migration bug');
