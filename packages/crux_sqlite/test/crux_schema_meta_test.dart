// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:test/test.dart';

/// A three-migration store, of which v3 is the shared `schema_meta` shape —
/// the same arrangement all four real stores end up in.
List<CruxMigration> _migrations({bool withSchemaMeta = true}) =>
    <CruxMigration>[
      CruxMigration(
        version: 1,
        description: 'Create runs',
        apply: (db) =>
            db.execute('CREATE TABLE runs (id INTEGER PRIMARY KEY, note TEXT)'),
      ),
      CruxMigration(
        version: 2,
        description: 'Index runs(note)',
        apply: (db) => db.execute('CREATE INDEX idx_runs_note ON runs(note)'),
      ),
      if (withSchemaMeta) cruxSchemaMetaMigration(version: 3),
    ];

CruxMigrationRunner _runner({
  List<CruxMigration>? migrations,
  String appVersion = '0.8.0',
  DateTime? now,
}) => CruxMigrationRunner(
  storeName: 'test store',
  migrations: migrations ?? _migrations(),
  identity: CruxAppIdentity(product: 'testcrux', appVersion: appVersion),
  now: now == null ? null : () => now,
);

CruxSqliteOpenPolicy _policy({
  List<CruxMigration>? migrations,
  String appVersion = '0.8.0',
  DateTime? now,
}) => CruxSqliteOpenPolicy(
  runner: _runner(migrations: migrations, appVersion: appVersion, now: now),
  recovery: CruxDbRecovery.refuse,
);

final DateTime _fixedNow = DateTime.utc(2026, 8, 20, 9, 14, 32, 512);

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crux_schema_meta_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String dbPath() => p.join(dir.path, 'trends.db');

  group('a fresh install stamps both tables', () {
    test(
      'schema_meta describes the file and every column is knowable',
      () async {
        final db = await _policy(now: _fixedNow).open(dbPath());
        addTearDown(db.close);

        final history = await readCruxSchemaHistory(db);
        final meta = history.meta!;
        expect(meta.schemaVersion, 3);
        expect(meta.product, 'testcrux');
        expect(meta.appVersion, '0.8.0');
        expect(
          meta.createdAt,
          _fixedNow,
          reason:
              'a file created right now has a knowable creation date — this is '
              'the ONE case where created_at is not null',
        );
        expect(meta.lastMigratedAt, _fixedNow);
        expect(meta.lastOpenedByAppVersion, '0.8.0');
      },
    );

    test(
      'every migration is ledgered with a real time and a real build',
      () async {
        final db = await _policy(now: _fixedNow).open(dbPath());
        addTearDown(db.close);

        final history = await readCruxSchemaHistory(db, ledgerLimit: -1);
        expect(history.ledger.map((r) => r.version), <int>[3, 2, 1]);
        expect(
          history.ledger.every((r) => r.appliedAt == _fixedNow),
          isTrue,
          reason: 'a fresh install watched all three run',
        );
        expect(
          history.ledger.every((r) => r.appliedByAppVersion == '0.8.0'),
          isTrue,
        );
        expect(
          history.ledger.any((r) => r.isBackfilled),
          isFalse,
          reason: 'nothing about a fresh file is unknown',
        );
      },
    );

    test("the ledger carries each migration's own description", () async {
      final db = await _policy(now: _fixedNow).open(dbPath());
      addTearDown(db.close);

      final history = await readCruxSchemaHistory(db, ledgerLimit: -1);
      expect(
        history.ledger.map((r) => r.description),
        containsAll(<String>['Create runs', 'Index runs(note)']),
        reason:
            'the description field is not a comment — this is the diagnostics '
            'tooling it was always for',
      );
    });

    test(
      'schema_meta is single-row by constraint, not by convention',
      () async {
        final db = await _policy(now: _fixedNow).open(dbPath());
        addTearDown(db.close);

        await expectLater(
          db.rawInsert(
            'INSERT INTO $kCruxSchemaMetaTable (id, schema_version, product) '
            'VALUES (2, 3, ?)',
            <Object?>['testcrux'],
          ),
          throwsA(isA<DatabaseException>()),
          reason:
              'a second row would be a second opinion about what version the '
              'file is at',
        );
      },
    );
  });

  group('an existing file gains them on upgrade, with honest unknowns', () {
    // Builds a real v2 file through the production open path, then reopens it
    // with the v3 (schema_meta) migration appended — exactly what a user's
    // trends.db does on the day this ships.
    Future<Database> upgradedFromV2() async {
      final old = await _policy(
        migrations: _migrations(withSchemaMeta: false),
      ).open(dbPath());
      await old.insert('runs', <String, Object?>{'id': 1, 'note': 'history'});
      await old.close();
      return await _policy(now: _fixedNow).open(dbPath());
    }

    test('created_at is NULL — not knowable, and not invented', () async {
      final db = await upgradedFromV2();
      addTearDown(db.close);

      final meta = (await readCruxSchemaHistory(db)).meta!;
      expect(
        meta.createdAt,
        isNull,
        reason:
            'the day the file adopted the ledger is a different fact from the '
            'day it was created, and writing the first into the second column '
            'would be a lie that reads as data',
      );
      expect(meta.schemaVersion, 3);
      expect(meta.lastMigratedAt, _fixedNow);
      expect(meta.appVersion, '0.8.0');
    });

    test(
      'pre-ledger migrations are recorded as run, by nobody, at no time',
      () async {
        final db = await upgradedFromV2();
        addTearDown(db.close);

        final ledger = (await readCruxSchemaHistory(
          db,
          ledgerLimit: -1,
        )).ledger;
        expect(ledger.map((r) => r.version), <int>[3, 2, 1]);

        final v1 = ledger.firstWhere((r) => r.version == 1);
        final v2 = ledger.firstWhere((r) => r.version == 2);
        expect(v1.isBackfilled, isTrue);
        expect(v2.isBackfilled, isTrue);
        expect(
          v1.description,
          'Create runs',
          reason:
              'the description IS knowable — migrations are frozen, so the '
              'list still holds the text that ran',
        );

        final v3 = ledger.firstWhere((r) => r.version == 3);
        expect(v3.isBackfilled, isFalse);
        expect(v3.appliedAt, _fixedNow);
        expect(v3.appliedByAppVersion, '0.8.0');
      },
    );

    test('the data is untouched by the schema_meta migration', () async {
      final db = await upgradedFromV2();
      addTearDown(db.close);

      final rows = await db.query('runs');
      expect(rows, hasLength(1));
      expect(rows.single['note'], 'history');
    });

    test(
      'a later upgrade keeps the history the file already recorded',
      () async {
        final first = await upgradedFromV2();
        await first.close();

        final later = DateTime.utc(2026, 12, 25);
        final v4 = <CruxMigration>[
          ..._migrations(),
          CruxMigration(
            version: 4,
            description: 'Add runs.extra',
            apply: (db) =>
                db.execute("ALTER TABLE runs ADD COLUMN extra TEXT DEFAULT ''"),
          ),
        ];
        final db = await _policy(
          migrations: v4,
          appVersion: '0.9.0',
          now: later,
        ).open(dbPath());
        addTearDown(db.close);

        final ledger = (await readCruxSchemaHistory(
          db,
          ledgerLimit: -1,
        )).ledger;
        final v3 = ledger.firstWhere((r) => r.version == 3);
        expect(
          v3.appliedByAppVersion,
          '0.8.0',
          reason:
              'INSERT OR IGNORE — a ledger row is a historical record, not a '
              'field the next migration gets to overwrite',
        );
        expect(v3.appliedAt, _fixedNow);
        expect(ledger.firstWhere((r) => r.version == 4).appliedAt, later);
        expect((await readCruxSchemaHistory(db)).meta!.appVersion, '0.9.0');
      },
    );
  });

  group('the ledger cannot disagree with the schema', () {
    test('a failed migration rolls its ledger row back too', () async {
      final first = await _policy(now: _fixedNow).open(dbPath());
      await first.close();

      final broken = <CruxMigration>[
        ..._migrations(),
        CruxMigration(
          version: 4,
          description: 'A migration with a typo in it',
          apply: (db) => db.execute('ALTER TABLE runs ADD COLUMN'),
        ),
      ];
      await expectLater(
        _policy(migrations: broken, appVersion: '0.9.0').open(dbPath()),
        throwsA(isA<CruxMigrationFailedException>()),
      );

      // Reopen at the version the file is actually still at.
      final db = await _policy(now: _fixedNow).open(dbPath());
      addTearDown(db.close);
      final history = await readCruxSchemaHistory(db, ledgerLimit: -1);
      expect(
        history.ledger.map((r) => r.version),
        <int>[3, 2, 1],
        reason:
            'v4 never happened, so the ledger must not claim it did — the '
            'ledger is written inside the migration transaction precisely so '
            'that a rollback takes it with it',
      );
      expect(history.meta!.schemaVersion, 3);
      expect(
        history.meta!.appVersion,
        '0.8.0',
        reason: 'the build that failed to migrate did not migrate',
      );
    });

    test(
      'a migration that fails partway through leaves no partial ledger',
      () async {
        final first = await _policy(
          migrations: _migrations(withSchemaMeta: false),
        ).open(dbPath());
        await first.close();

        // v3 (schema_meta) succeeds, v4 throws — one transaction, both undone.
        final broken = <CruxMigration>[
          ..._migrations(),
          CruxMigration(
            version: 4,
            description: 'A migration with a typo in it',
            apply: (db) => db.execute('ALTER TABLE runs ADD COLUMN'),
          ),
        ];
        await expectLater(
          _policy(migrations: broken).open(dbPath()),
          throwsA(isA<CruxMigrationFailedException>()),
        );

        final db = await _policy(
          migrations: _migrations(withSchemaMeta: false),
        ).open(dbPath());
        addTearDown(db.close);
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          <Object?>[kCruxSchemaMetaTable],
        );
        expect(
          tables,
          isEmpty,
          reason:
              'the schema_meta tables were created inside the same transaction '
              'that then rolled back',
        );
      },
    );
  });

  group('the downgrade refusal names the build that wrote the file', () {
    test('the message carries the app version, not only the number', () async {
      final newer = await _policy(appVersion: '0.9.0').open(dbPath());
      await newer.close();

      final older = _policy(migrations: _migrations(withSchemaMeta: false));
      Object? caught;
      try {
        await older.open(dbPath());
      } on CruxSchemaVersionSkewException catch (e) {
        caught = e;
      }

      final skew = caught! as CruxSchemaVersionSkewException;
      expect(skew.fileVersion, 3);
      expect(skew.appVersion, 2);
      expect(skew.fileAppVersion, '0.9.0');
      expect(
        skew.toString(),
        contains('version 0.9.0'),
        reason:
            'a schema number is not something a user can act on; the build '
            'that wrote the file is',
      );
    });

    test('a pre-ledger file still refuses, with the bare numbers', () async {
      final newer = await _policy(
        migrations: _migrations(withSchemaMeta: false),
      ).open(dbPath());
      await newer.close();

      final older = CruxSqliteOpenPolicy(
        runner: _runner(migrations: <CruxMigration>[_migrations().first]),
        recovery: CruxDbRecovery.refuse,
      );
      await expectLater(
        older.open(dbPath()),
        throwsA(
          isA<CruxSchemaVersionSkewException>()
              .having((e) => e.fileAppVersion, 'fileAppVersion', isNull)
              .having(
                (e) => e.toString(),
                'message',
                contains('written by a newer build'),
              ),
        ),
      );
    });

    test('the refusal modifies nothing, including the open stamp', () async {
      final newer = await _policy(appVersion: '0.9.0').open(dbPath());
      await newer.close();
      final before = File(dbPath()).lastModifiedSync();

      await expectLater(
        _policy(migrations: _migrations(withSchemaMeta: false)).open(dbPath()),
        throwsA(isA<CruxSchemaVersionSkewException>()),
      );

      final db = await _policy(appVersion: '0.9.0').open(dbPath());
      addTearDown(db.close);
      expect(
        (await readCruxSchemaHistory(db)).meta!.lastOpenedByAppVersion,
        '0.9.0',
        reason:
            'the refusing build must not have stamped itself into a file it '
            'declined to understand',
      );
      expect(File(dbPath()).lastModifiedSync(), before);
    });
  });

  group('last_opened_by_app_version', () {
    test('a plain open with no migration still records the opener', () async {
      final first = await _policy(now: _fixedNow).open(dbPath());
      await first.close();

      final second = await _policy(appVersion: '0.9.0').open(dbPath());
      addTearDown(second.close);

      final meta = (await readCruxSchemaHistory(second)).meta!;
      expect(meta.lastOpenedByAppVersion, '0.9.0');
      expect(
        meta.appVersion,
        '0.8.0',
        reason:
            'app_version is the build that last MIGRATED; 0.9.0 only opened '
            'it, and conflating the two is how a ledger stops being evidence',
      );
      expect(meta.lastMigratedAt, _fixedNow);
    });

    test('there is no onOpen on the options object', () {
      final options = _policy().buildOptions(path: dbPath());
      expect(
        options.onOpen,
        isNull,
        reason:
            "a non-null onOpen adds an await to sqflite_common's open "
            'sequence, which deadlocked six LintCrux Pro widget tests under '
            "flutter_test's fake-async zone. The open stamp goes in "
            'onConfigure, which is already non-null for busy_timeout',
      );
      expect(options.onConfigure, isNotNull);
    });
  });

  group('reading tolerates a file that predates the ledger', () {
    test('absence is a state, not an error', () async {
      final db = await _policy(
        migrations: _migrations(withSchemaMeta: false),
      ).open(dbPath());
      addTearDown(db.close);

      final history = await readCruxSchemaHistory(db);
      expect(history.isPresent, isFalse);
      expect(history.meta, isNull);
      expect(history.ledger, isEmpty);
      expect(await readCruxSchemaMetaQuietly(db), isNull);
    });

    test(
      'a store with no schema_meta migration still opens and migrates',
      () async {
        final db = await _policy(
          migrations: _migrations(withSchemaMeta: false),
        ).open(dbPath());
        addTearDown(db.close);
        expect(await db.getVersion(), 2);
      },
    );
  });

  group('CruxAppIdentity', () {
    test('rejects a blank product', () {
      expect(
        () => CruxAppIdentity(product: '  ', appVersion: '1.0.0'),
        throwsArgumentError,
      );
    });

    test('rejects an empty app version, which looks present and is not', () {
      expect(
        () => CruxAppIdentity(product: 'testcrux', appVersion: ''),
        throwsArgumentError,
      );
    });

    test('unknown is expressible on purpose', () async {
      final policy = CruxSqliteOpenPolicy(
        runner: CruxMigrationRunner(
          storeName: 'test store',
          migrations: _migrations(),
          identity: CruxAppIdentity.unknown,
          now: () => _fixedNow,
        ),
        recovery: CruxDbRecovery.refuse,
      );
      final db = await policy.open(dbPath());
      addTearDown(db.close);

      final meta = (await readCruxSchemaHistory(db)).meta!;
      expect(meta.product, 'unknown');
      expect(
        meta.appVersion,
        isNull,
        reason: 'null, not the string "unknown" — SQL already has a NULL',
      );
    });
  });

  group('the shape is frozen', () {
    test('schema_meta and schema_migrations have exactly this DDL', () async {
      final db = await _policy(now: _fixedNow).open(dbPath());
      addTearDown(db.close);

      final rows = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
        'AND name IN (?, ?) ORDER BY name',
        <Object?>[kCruxSchemaMetaTable, kCruxSchemaMigrationsTable],
      );
      final dumped = <String, String>{
        for (final r in rows)
          r['name']! as String: (r['sql']! as String).replaceAll(
            RegExp(r'\s+'),
            ' ',
          ),
      };

      expect(
        dumped[kCruxSchemaMetaTable],
        'CREATE TABLE schema_meta ( id INTEGER PRIMARY KEY CHECK (id = 1), '
        'schema_version INTEGER NOT NULL, product TEXT NOT NULL, '
        'app_version TEXT, created_at TEXT, last_migrated_at TEXT, '
        'last_opened_by_app_version TEXT )',
        reason:
            'this text is part of four already-shipped migrations. Changing '
            'it edits them, which rule 1 forbids. A new shape is a second '
            'factory appended after this one',
      );
      expect(
        dumped[kCruxSchemaMigrationsTable],
        'CREATE TABLE schema_migrations ( version INTEGER PRIMARY KEY, '
        'description TEXT NOT NULL, applied_at TEXT, '
        'applied_by_app_version TEXT )',
      );
    });

    test(
      'timestamps are ISO 8601 extended UTC, and sort as they read',
      () async {
        final db = await _policy(now: _fixedNow).open(dbPath());
        addTearDown(db.close);

        final raw = await db.rawQuery(
          'SELECT last_migrated_at FROM $kCruxSchemaMetaTable WHERE id = 1',
        );
        expect(raw.single['last_migrated_at'], '2026-08-20T09:14:32.512Z');
        expect(
          formatCruxSchemaTimestamp(DateTime.utc(2026)).compareTo(
            formatCruxSchemaTimestamp(DateTime.utc(2027)),
          ),
          isNegative,
          reason:
              'lexicographic order is chronological order — which is why the '
              'column is text and not an epoch integer',
        );
      },
    );
  });

  group('the fraction is fixed-width, which is what makes the text sort', () {
    // The same instant as [_fixedNow] plus 697 microseconds — the shape a real
    // `DateTime.now()` has almost always and a hand-written fixture never has.
    // Measured in the field on 2026-08-21: `2026-08-21T01:16:08.376697Z`.
    final nowWithMicroseconds = DateTime.utc(
      2026,
      8,
      20,
      9,
      14,
      32,
      512,
      697,
    );

    test('a stored column is milliseconds, whatever the clock has', () async {
      final db = await _policy(now: nowWithMicroseconds).open(dbPath());
      addTearDown(db.close);

      final meta = await db.rawQuery(
        'SELECT created_at, last_migrated_at FROM $kCruxSchemaMetaTable '
        'WHERE id = 1',
      );
      expect(
        meta.single['last_migrated_at'],
        '2026-08-20T09:14:32.512Z',
        reason:
            'toIso8601String() widens the fraction to six digits the moment '
            'the microsecond component is non-zero, and a mixed-width '
            'fraction does not sort as text',
      );
      expect(meta.single['created_at'], '2026-08-20T09:14:32.512Z');

      final ledger = await db.rawQuery(
        'SELECT applied_at FROM $kCruxSchemaMigrationsTable WHERE version = 3',
      );
      expect(ledger.single['applied_at'], '2026-08-20T09:14:32.512Z');
    });

    test('every stamp is the same width, so compareTo is chronological', () {
      final instants = <DateTime>[
        DateTime.utc(2026, 8, 20, 9, 14, 32, 512),
        DateTime.utc(2026, 8, 20, 9, 14, 32, 512, 1),
        DateTime.utc(2026, 8, 20, 9, 14, 32, 513),
        DateTime.utc(2026, 8, 20, 9, 14, 33),
        DateTime.utc(2027),
      ];
      final stamps = instants.map(formatCruxSchemaTimestamp).toList();

      expect(
        stamps.map((s) => s.length).toSet(),
        hasLength(1),
        reason:
            'a fixed-width fraction is the entire reason this column sorts as '
            'text. Mix three- and six-digit fractions and .512Z sorts AFTER '
            '.512001Z',
      );
      expect(
        stamps,
        List<String>.of(stamps)..sort(),
        reason:
            'sorted as text is sorted as time — the property the extended '
            'form was chosen for over the basic form the filenames use',
      );
    });

    test('the shape is exactly yyyy-MM-ddTHH:mm:ss.sssZ, always UTC', () {
      final shape = RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      );
      expect(formatCruxSchemaTimestamp(nowWithMicroseconds), matches(shape));
      expect(formatCruxSchemaTimestamp(DateTime.utc(2027)), matches(shape));
      expect(
        formatCruxSchemaTimestamp(
          DateTime.parse('2026-08-20T11:14:32.512697+02:00'),
        ),
        '2026-08-20T09:14:32.512Z',
        reason:
            'a local-time column is a column that lies when the user '
            'travels, so the offset is resolved before it is stored',
      );
    });

    test('a stamp round-trips through the reader, truncated', () async {
      final db = await _policy(now: nowWithMicroseconds).open(dbPath());
      addTearDown(db.close);

      final history = await readCruxSchemaHistory(db);
      expect(
        history.meta!.lastMigratedAt,
        DateTime.utc(2026, 8, 20, 9, 14, 32, 512),
        reason:
            'what was stored is what reads back — the sub-millisecond '
            'part is gone, deliberately, not rounded to something else',
      );
    });

    test('a six-digit fraction already on disk still reads back', () async {
      final db = await _policy(now: _fixedNow).open(dbPath());
      addTearDown(db.close);

      // What a pre-fix build wrote. Nothing rewrites these rows, so the
      // reader has to keep accepting them.
      await db.rawUpdate(
        'UPDATE $kCruxSchemaMetaTable SET last_migrated_at = ? WHERE id = 1',
        <Object?>['2026-08-21T01:16:08.376697Z'],
      );

      final history = await readCruxSchemaHistory(db);
      expect(
        history.meta!.lastMigratedAt,
        DateTime.utc(2026, 8, 21, 1, 16, 8, 376, 697),
        reason:
            'DateTime.parse accepts both widths, which is why the fix needs no '
            'migration that rewrites history',
      );
    });
  });
}
