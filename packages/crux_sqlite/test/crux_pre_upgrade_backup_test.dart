// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:test/test.dart';

/// v1: one table with one row, so every assertion below can prove the *data*
/// survived rather than only that a file exists.
CruxMigration _createRuns() => CruxMigration(
  version: 1,
  description: 'Create runs',
  apply: (db) async {
    await db.execute('CREATE TABLE runs (id INTEGER PRIMARY KEY, note TEXT)');
    await db.execute("INSERT INTO runs (id, note) VALUES (1, 'kept')");
  },
);

CruxMigration _addLabel() => CruxMigration(
  version: 2,
  description: 'Add runs.label with a default',
  apply: (db) =>
      db.execute("ALTER TABLE runs ADD COLUMN label TEXT NOT NULL DEFAULT ''"),
);

CruxMigration _addOwner() => CruxMigration(
  version: 3,
  description: 'Add runs.owner with a default',
  apply: (db) =>
      db.execute("ALTER TABLE runs ADD COLUMN owner TEXT NOT NULL DEFAULT ''"),
);

CruxMigration _throwing(int version) => CruxMigration(
  version: version,
  description: 'A migration with a typo in it',
  apply: (db) => db.execute('ALTER TABLE runs ADD COLUMN'),
);

CruxSqliteOpenPolicy _policy(
  List<CruxMigration> migrations, {
  CruxDbRecovery recovery = CruxDbRecovery.refuse,
  CruxPreUpgradeBackup backup = const CruxPreUpgradeBackup(),
  CruxDbRecoveryListener? onRecovery,
}) => CruxSqliteOpenPolicy(
  runner: CruxMigrationRunner(
    storeName: 'test store',
    migrations: migrations,
    identity: CruxAppIdentity(product: 'testcrux', appVersion: '1.2.3'),
  ),
  recovery: recovery,
  onRecovery: onRecovery,
  backup: backup,
);

/// A clock that returns a distinct, increasing second on every call, so
/// successive backups sort deterministically without a real delay.
DateTime Function() _tickingClock({int startSecond = 0}) {
  var tick = startSecond;
  return () => DateTime.utc(2026, 8, 20, 9, 0, tick++);
}

List<String> _backupNames(String dbPath) => <String>[
  for (final path in CruxPreUpgradeBackup.backupsFor(dbPath)) p.basename(path),
];

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crux_sqlite_backup_');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  String dbPath() => p.join(tmp.path, 'trends.db');

  /// Creates a database at `dbPath()` sitting at version [version].
  Future<void> seed(int version, {CruxPreUpgradeBackup? backup}) async {
    final migrations = <CruxMigration>[
      _createRuns(),
      _addLabel(),
      _addOwner(),
    ].take(version).toList();
    final db = await _policy(
      migrations,
      backup: backup ?? const CruxPreUpgradeBackup(),
    ).open(dbPath());
    await db.close();
  }

  group('a PRECIOUS store is backed up before an upgrade, without asking', () {
    test('the backup lands before the migration runs', () async {
      await seed(1);
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: _tickingClock()),
      ).open(dbPath());
      await db.close();

      expect(_backupNames(dbPath()), <String>[
        'trends.db.pre-v1-20260820T090000Z.bak',
      ]);
    });

    test('the backup is the file as it was BEFORE the upgrade', () async {
      await seed(1);
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: _tickingClock()),
      ).open(dbPath());
      await db.close();

      // The live file gained `label`; the backup must not have.
      final backupPath = CruxPreUpgradeBackup.latestBackupFor(dbPath())!;
      final backup = await databaseFactory.openDatabase(backupPath);
      final columns = await backup.rawQuery('PRAGMA table_info(runs)');
      final names = {for (final row in columns) row['name']};
      final rows = await backup.rawQuery('SELECT note FROM runs');
      await backup.close();

      expect(names, <String>{'id', 'note'});
      expect(names, isNot(contains('label')));
      expect(rows.single['note'], 'kept');

      final version = await databaseFactory.openDatabase(backupPath).then((
        db,
      ) async {
        final v = await db.rawQuery('PRAGMA user_version');
        await db.close();
        return v.first.values.first;
      });
      expect(version, 1, reason: 'the snapshot is stamped at the OLD version');
    });

    test('no backup is written when the version has not moved', () async {
      await seed(2, backup: CruxPreUpgradeBackup(clock: _tickingClock()));
      expect(_backupNames(dbPath()), isEmpty);

      // Reopen at the same version — twice, to catch a naive "back up on
      // every open".
      for (var i = 0; i < 2; i++) {
        final db = await _policy(
          [_createRuns(), _addLabel()],
          backup: CruxPreUpgradeBackup(clock: _tickingClock()),
        ).open(dbPath());
        await db.close();
      }
      expect(_backupNames(dbPath()), isEmpty);
    });

    test('a fresh create is not backed up — there is nothing there', () async {
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: _tickingClock()),
      ).open(dbPath());
      await db.close();
      expect(_backupNames(dbPath()), isEmpty);
    });

    test('an in-memory database is not backed up', () async {
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: _tickingClock()),
      ).open(inMemoryDatabasePath);
      await db.close();
      expect(tmp.listSync(), isEmpty);
    });

    test('a DERIVABLE store is never backed up', () async {
      await seed(1);
      final db = await _policy(
        [_createRuns(), _addLabel()],
        recovery: CruxDbRecovery.recreate,
        onRecovery: (_) {},
        backup: CruxPreUpgradeBackup(clock: _tickingClock()),
      ).open(dbPath());
      await db.close();

      expect(
        _backupNames(dbPath()),
        isEmpty,
        reason: 'cache.db is derivable; backing it up is wasted disk',
      );
    });

    test('being precious is what opts a store in, not a flag', () {
      final precious = _policy([_createRuns()]);
      final derivable = _policy(
        [_createRuns()],
        recovery: CruxDbRecovery.recreate,
        onRecovery: (_) {},
      );
      expect(precious.backsUpBeforeUpgrade, isTrue);
      expect(derivable.backsUpBeforeUpgrade, isFalse);
      expect(CruxDbRecovery.renameAside.isPrecious, isTrue);
      expect(CruxDbRecovery.refuse.isPrecious, isTrue);
      expect(CruxDbRecovery.recreate.isPrecious, isFalse);
    });

    test('the store built the backup path it declares it did', () {
      expect(
        CruxPreUpgradeBackup.backupPathFor(
          '/tmp/trends.db',
          oldVersion: 2,
          now: DateTime.utc(2026, 8, 20, 9),
        ),
        '/tmp/trends.db.pre-v2-20260820T090000Z.bak',
        reason: 'ISO 8601 BASIC — a colon is illegal in a Windows filename',
      );
    });
  });

  group('a failed migration leaves the original AND the backup intact', () {
    test('the data survives, the backup survives, and it is named', () async {
      await seed(1);
      Object? caught;
      try {
        await _policy(
          [_createRuns(), _throwing(2)],
          backup: CruxPreUpgradeBackup(clock: _tickingClock()),
        ).open(dbPath());
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<CruxMigrationFailedException>());
      final failure = caught! as CruxMigrationFailedException;

      final backupPath = CruxPreUpgradeBackup.latestBackupFor(dbPath());
      expect(backupPath, isNotNull);
      expect(File(backupPath!).existsSync(), isTrue);
      expect(
        failure.backupPath,
        backupPath,
        reason: 'the error must name the backup by absolute path',
      );
      expect(p.isAbsolute(failure.backupPath!), isTrue);
      expect(failure.toString(), contains(backupPath));

      // The original is untouched, at v1, with its row.
      final db = await databaseFactory.openDatabase(dbPath());
      final version = await db.rawQuery('PRAGMA user_version');
      final rows = await db.rawQuery('SELECT note FROM runs');
      await db.close();
      expect(version.first.values.first, 1);
      expect(rows.single['note'], 'kept');
    });

    test('a failed migration prunes nothing, however many backups', () async {
      // Three successful upgrades' worth of backups, then a failure.
      final clock = _tickingClock();
      await seed(1);
      for (final target in <List<CruxMigration>>[
        [_createRuns(), _addLabel()],
        [_createRuns(), _addLabel(), _addOwner()],
      ]) {
        final db = await _policy(
          target,
          backup: CruxPreUpgradeBackup(keep: 99, clock: clock),
        ).open(dbPath());
        await db.close();
      }
      final before = _backupNames(dbPath());
      expect(before, hasLength(2));

      await expectLater(
        _policy(
          [_createRuns(), _addLabel(), _addOwner(), _throwing(4)],
          backup: CruxPreUpgradeBackup(keep: 1, clock: clock),
        ).open(dbPath()),
        throwsA(isA<CruxMigrationFailedException>()),
      );

      expect(
        _backupNames(dbPath()),
        hasLength(3),
        reason: 'keep:1 would have pruned to one had the migration succeeded',
      );
      expect(_backupNames(dbPath()), containsAll(before));
    });
  });

  group('a successful migration prunes to exactly N', () {
    test('the newest kCruxBackupsKept survive and the rest do not', () async {
      final clock = _tickingClock();
      await seed(1);

      // Three upgrades in a row, each taking one backup.
      final ladder = <List<CruxMigration>>[
        [_createRuns(), _addLabel()],
        [_createRuns(), _addLabel(), _addOwner()],
      ];
      for (final migrations in ladder) {
        final db = await _policy(
          migrations,
          backup: CruxPreUpgradeBackup(clock: clock),
        ).open(dbPath());
        await db.close();
      }

      expect(_backupNames(dbPath()), <String>[
        'trends.db.pre-v2-20260820T090001Z.bak',
        'trends.db.pre-v1-20260820T090000Z.bak',
      ]);
      expect(kCruxBackupsKept, 2);
    });

    test('keep:1 leaves exactly the newest one', () async {
      final clock = _tickingClock();
      await seed(1);
      for (final migrations in <List<CruxMigration>>[
        [_createRuns(), _addLabel()],
        [_createRuns(), _addLabel(), _addOwner()],
      ]) {
        final db = await _policy(
          migrations,
          backup: CruxPreUpgradeBackup(keep: 1, clock: clock),
        ).open(dbPath());
        await db.close();
      }
      expect(_backupNames(dbPath()), <String>[
        'trends.db.pre-v2-20260820T090001Z.bak',
      ]);
    });

    test('an ordinary same-version open prunes nothing', () async {
      final clock = _tickingClock();
      await seed(1);
      final upgraded = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: clock),
      ).open(dbPath());
      await upgraded.close();
      // Plant an extra, older backup by hand so a pruning open would be
      // visible: keep:1 plus the one above would leave one file.
      File(
        p.join(tmp.path, 'trends.db.pre-v1-20260101T000000Z.bak'),
      ).writeAsStringSync('older');

      final reopened = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(keep: 1, clock: clock),
      ).open(dbPath());
      await reopened.close();

      expect(
        _backupNames(dbPath()),
        hasLength(2),
        reason: 'no upgrade ran, so nothing may be pruned',
      );
    });
  });

  group('a backup that cannot be written aborts the migration', () {
    test(
      'a read-only directory stops the upgrade and says why',
      () async {
        await seed(1);
        final notices = <CruxBackupNotice>[];
        final mode = Process.runSync('chmod', <String>['555', tmp.path]);
        expect(mode.exitCode, 0, reason: 'chmod is needed to stage this');
        addTearDown(
          () => Process.runSync('chmod', <String>['755', tmp.path]),
        );

        Object? caught;
        try {
          await _policy(
            [_createRuns(), _addLabel()],
            backup: CruxPreUpgradeBackup(
              clock: _tickingClock(),
              onBackup: notices.add,
            ),
          ).open(dbPath());
        } on Object catch (error) {
          caught = error;
        }

        expect(caught, isA<CruxBackupFailedException>());
        final failure = caught! as CruxBackupFailedException;
        expect(failure.kind, CruxBackupFailureKind.vacuumFailed);
        expect(failure.fromVersion, 1);
        expect(failure.toVersion, 2);
        expect(failure.toString(), contains('did NOT run'));
        expect(failure.toString(), contains('untouched at v1'));
        expect(notices.single.created, isFalse);

        Process.runSync('chmod', <String>['755', tmp.path]);

        // And the migration really did not run.
        final db = await databaseFactory.openDatabase(dbPath());
        final version = await db.rawQuery('PRAGMA user_version');
        final columns = await db.rawQuery('PRAGMA table_info(runs)');
        await db.close();
        expect(version.first.values.first, 1);
        expect({for (final c in columns) c['name']}, isNot(contains('label')));
      },
      onPlatform: const {'windows': Skip('chmod is POSIX')},
    );

    test('too little free disk aborts before VACUUM is attempted', () async {
      await seed(1);
      final notices = <CruxBackupNotice>[];

      Object? caught;
      try {
        await _policy(
          [_createRuns(), _addLabel()],
          backup: CruxPreUpgradeBackup(
            // Guard at 0 bytes so this small database trips the threshold, and
            // a probe that reports a nearly full volume.
            sizeGuardBytes: 0,
            freeDiskProbe: (_) => 16,
            clock: _tickingClock(),
            onBackup: notices.add,
          ),
        ).open(dbPath());
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<CruxBackupFailedException>());
      final failure = caught! as CruxBackupFailedException;
      expect(failure.kind, CruxBackupFailureKind.insufficientFreeSpace);
      expect(failure.freeBytes, 16);
      expect(failure.databaseBytes, greaterThan(16));
      expect(failure.backupPath, isNull);
      expect(
        notices.single.failure,
        CruxBackupFailureKind.insufficientFreeSpace,
      );
      expect(notices.single.toString(), contains('did not run'));

      expect(
        _backupNames(dbPath()),
        isEmpty,
        reason: 'VACUUM INTO was never attempted, so no partial file',
      );
      final db = await databaseFactory.openDatabase(dbPath());
      final version = await db.rawQuery('PRAGMA user_version');
      await db.close();
      expect(version.first.values.first, 1);
    });

    test('an unmeasurable volume is not treated as a full one', () async {
      await seed(1);
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(
          sizeGuardBytes: 0,
          freeDiskProbe: (_) => null,
          clock: _tickingClock(),
        ),
      ).open(dbPath());
      await db.close();
      expect(_backupNames(dbPath()), hasLength(1));
    });

    test(
      'an unmeasurable volume is still not a way past the backup',
      () async {
        // `null` from the probe means "proceed and let the write be the
        // judge". This is the judge: the probe cannot say, the backup cannot
        // be written, and the migration does not run. A probe that fails is
        // never a migration without a backup.
        await seed(1);
        final mode = Process.runSync('chmod', <String>['555', tmp.path]);
        expect(mode.exitCode, 0, reason: 'chmod is needed to stage this');
        addTearDown(
          () => Process.runSync('chmod', <String>['755', tmp.path]),
        );

        var probed = false;
        Object? caught;
        try {
          await _policy(
            [_createRuns(), _addLabel()],
            backup: CruxPreUpgradeBackup(
              sizeGuardBytes: 0,
              freeDiskProbe: (_) {
                probed = true;
                return null;
              },
              clock: _tickingClock(),
            ),
          ).open(dbPath());
        } on Object catch (error) {
          caught = error;
        }

        expect(probed, isTrue, reason: 'past the guard, so the probe ran');
        expect(caught, isA<CruxBackupFailedException>());
        final failure = caught! as CruxBackupFailedException;
        expect(failure.kind, CruxBackupFailureKind.vacuumFailed);
        expect(failure.freeBytes, isNull);

        Process.runSync('chmod', <String>['755', tmp.path]);
        final db = await databaseFactory.openDatabase(dbPath());
        final version = await db.rawQuery('PRAGMA user_version');
        await db.close();
        expect(version.first.values.first, 1, reason: 'the upgrade never ran');
      },
      onPlatform: const {'windows': Skip('chmod is POSIX')},
    );

    test('the size guard does not probe below the threshold', () async {
      await seed(1);
      var probed = false;
      final db = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(
          freeDiskProbe: (_) {
            probed = true;
            return 0;
          },
          clock: _tickingClock(),
        ),
      ).open(dbPath());
      await db.close();
      expect(probed, isFalse);
      expect(_backupNames(dbPath()), hasLength(1));
    });
  });

  group('a downgrade is pointed at the backup', () {
    test('the refusal names an existing backup by absolute path', () async {
      final clock = _tickingClock();
      await seed(1);
      // Upgrade v1 → v2, which leaves a `.pre-v1` backup.
      final upgraded = await _policy(
        [_createRuns(), _addLabel()],
        backup: CruxPreUpgradeBackup(clock: clock),
      ).open(dbPath());
      await upgraded.close();
      final backupPath = CruxPreUpgradeBackup.latestBackupFor(dbPath())!;

      // Now the older build opens the same file.
      Object? caught;
      try {
        await _policy(
          [_createRuns()],
          backup: CruxPreUpgradeBackup(clock: clock),
        ).open(dbPath());
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isA<CruxSchemaVersionSkewException>());
      final skew = caught! as CruxSchemaVersionSkewException;
      expect(skew.backupPath, backupPath);
      expect(skew.toString(), contains(backupPath));
      expect(skew.toString(), contains('pre-upgrade backup'));
      expect(File(backupPath).existsSync(), isTrue);
    });

    test('with no backup on disk the refusal still stands, silently', () async {
      await seed(2);
      Object? caught;
      try {
        await _policy([_createRuns()]).open(dbPath());
      } on Object catch (error) {
        caught = error;
      }
      final skew = caught! as CruxSchemaVersionSkewException;
      expect(skew.backupPath, isNull);
      expect(skew.toString(), isNot(contains('.bak')));
      expect(skew.toString(), contains('no data has been lost'));
    });
  });

  group('the backup index', () {
    test("reads only this database's backups, newest first", () {
      final other = p.join(tmp.path, 'cache.db');
      for (final name in <String>[
        'trends.db.pre-v1-20260101T000000Z.bak',
        'trends.db.pre-v2-20260301T000000Z.bak',
        'trends.db.pre-v2-20260301T000000Z-1.bak',
        'trends.db.corrupt-20260101T000000Z',
        'trends.db',
        'cache.db.pre-v1-20260401T000000Z.bak',
        'notes.txt',
      ]) {
        File(p.join(tmp.path, name)).writeAsStringSync('x');
      }

      expect(_backupNames(dbPath()), <String>[
        'trends.db.pre-v2-20260301T000000Z-1.bak',
        'trends.db.pre-v2-20260301T000000Z.bak',
        'trends.db.pre-v1-20260101T000000Z.bak',
      ]);
      expect(_backupNames(other), <String>[
        'cache.db.pre-v1-20260401T000000Z.bak',
      ]);
    });

    test('a missing directory is empty, not an exception', () {
      expect(
        CruxPreUpgradeBackup.backupsFor('/no/such/dir/trends.db'),
        isEmpty,
      );
      expect(
        CruxPreUpgradeBackup.latestBackupFor('/no/such/dir/trends.db'),
        isNull,
      );
    });

    test('two backups in the same second do not collide', () async {
      // The realistic collision: a broken migration is retried straight away.
      // Both attempts back up the same version, and `VACUUM INTO` refuses an
      // output file that already exists — so without the suffix the second
      // attempt would fail on the backup rather than on the real bug, and the
      // first attempt's snapshot would be the one reported.
      await seed(1);
      final frozen = DateTime.utc(2026, 8, 20, 9);
      final failures = <CruxMigrationFailedException>[];
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await _policy(
            [_createRuns(), _throwing(2)],
            backup: CruxPreUpgradeBackup(keep: 99, clock: () => frozen),
          ).open(dbPath());
        } on CruxMigrationFailedException catch (error) {
          failures.add(error);
        }
      }

      expect(failures, hasLength(2));
      expect(_backupNames(dbPath()), <String>[
        'trends.db.pre-v1-20260820T090000Z-1.bak',
        'trends.db.pre-v1-20260820T090000Z.bak',
      ]);
      expect(
        failures.map((f) => p.basename(f.backupPath!)),
        <String>[
          'trends.db.pre-v1-20260820T090000Z.bak',
          'trends.db.pre-v1-20260820T090000Z-1.bak',
        ],
        reason: 'each attempt names its own snapshot, not the other one',
      );
    });
  });
}
