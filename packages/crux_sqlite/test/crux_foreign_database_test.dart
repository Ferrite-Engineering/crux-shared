// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_sqlite/crux_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(ensureCruxSqliteFfiInitialized);

  late Directory temp;
  late String dbPath;

  /// Writes a WAL-mode database the way a foreign tool would, and closes it
  /// so the log is checkpointed and removed.
  Future<void> writeForeign() async {
    final db = await databaseFactory.openDatabase(dbPath);
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.execute('CREATE TABLE task_status (name TEXT, status TEXT)');
    await db.insert('task_status', {'name': 'prove', 'status': 'PASS'});
    await db.insert('task_status', {'name': 'cover', 'status': 'FAIL'});
    await db.close();
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('crux_sqlite_foreign_');
    dbPath = p.join(temp.path, 'status.sqlite');
    await writeForeign();
  });

  tearDown(() {
    if (temp.existsSync()) {
      for (final e in temp.listSync(recursive: true)) {
        if (e is File) _makeWritable(e.path);
      }
      _makeWritable(temp.path);
      temp.deleteSync(recursive: true);
    }
  });

  test('reads the rows the tool wrote', () async {
    final db = await openForeignSqliteReadOnly(dbPath);
    addTearDown(db.close);
    final rows = await db.query('task_status', orderBy: 'name');
    expect(rows, [
      {'name': 'cover', 'status': 'FAIL'},
      {'name': 'prove', 'status': 'PASS'},
    ]);
  });

  test('writes nothing: no -shm, no -wal, the bytes and version unchanged, '
      'no schema_meta', () async {
    expect(File('$dbPath-wal').existsSync(), isFalse);
    final before = File(dbPath).readAsBytesSync();
    final modified = File(dbPath).lastModifiedSync();

    final db = await openForeignSqliteReadOnly(dbPath);
    final journal = await db.rawQuery('PRAGMA journal_mode');
    final version = await db.getVersion();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    await db.query('task_status');
    await db.close();

    expect(version, 0);
    expect(tables.map((r) => r['name']), ['task_status']);
    // Read immutable, the file is not consulted for its WAL state.
    expect(journal, isNotEmpty);
    expect(File('$dbPath-shm').existsSync(), isFalse);
    expect(File('$dbPath-wal').existsSync(), isFalse);
    expect(File(dbPath).readAsBytesSync(), before);
    expect(File(dbPath).lastModifiedSync(), modified);
    expect(
      temp.listSync().map((e) => p.basename(e.path)),
      ['status.sqlite'],
    );
  });

  test('control: a plain read-only open of the same file does write', () async {
    // Why the immutable URI: without it, reading a WAL-mode file creates
    // the shared-memory file beside it, so "read-only" still writes.
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await db.query('task_status');
    final shm = File('$dbPath-shm').existsSync();
    await db.close();
    expect(shm, isTrue);
  });

  test('opens a file in a directory it cannot write', () async {
    if (Platform.isWindows) return;
    _makeReadOnly(temp.path);
    final db = await openForeignSqliteReadOnly(dbPath);
    addTearDown(db.close);
    expect(await db.query('task_status'), hasLength(2));
  });

  test('refuses every write', () async {
    final db = await openForeignSqliteReadOnly(dbPath);
    addTearDown(db.close);
    await expectLater(
      db.execute('CREATE TABLE x (a)'),
      throwsA(isA<DatabaseException>()),
    );
    await expectLater(
      db.insert('task_status', {'name': 'x', 'status': 'y'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a missing file is refused, and nothing is created', () async {
    final missing = p.join(temp.path, 'absent.sqlite');
    await expectLater(
      openForeignSqliteReadOnly(missing),
      throwsA(
        isA<CruxForeignDatabaseException>().having(
          (e) => e.refusal,
          'refusal',
          CruxForeignDatabaseRefusal.missing,
        ),
      ),
    );
    expect(File(missing).existsSync(), isFalse);
  });

  test('a directory is refused', () async {
    await expectLater(
      openForeignSqliteReadOnly(temp.path),
      throwsA(
        isA<CruxForeignDatabaseException>().having(
          (e) => e.refusal,
          'refusal',
          CruxForeignDatabaseRefusal.notAFile,
        ),
      ),
    );
  });

  test('a file whose writer left an unflushed log is refused', () async {
    File('$dbPath-wal').writeAsBytesSync([1, 2, 3]);
    await expectLater(
      openForeignSqliteReadOnly(dbPath),
      throwsA(
        isA<CruxForeignDatabaseException>()
            .having(
              (e) => e.refusal,
              'refusal',
              CruxForeignDatabaseRefusal.notCheckpointed,
            )
            .having((e) => e.toString(), 'message', contains('checkpoint')),
      ),
    );
  });

  test('an empty log left behind is not a refusal', () async {
    File('$dbPath-wal').writeAsBytesSync(const []);
    final db = await openForeignSqliteReadOnly(dbPath);
    addTearDown(db.close);
    expect(await db.query('task_status'), hasLength(2));
  });

  test('bytes that are not a database fail as a DatabaseException and are '
      'left alone', () async {
    final junk = p.join(temp.path, 'junk.sqlite');
    File(junk).writeAsStringSync('not a database at all, not even close');
    final before = File(junk).readAsBytesSync();
    Future<void> read() async {
      final db = await openForeignSqliteReadOnly(junk);
      try {
        await db.rawQuery('SELECT * FROM sqlite_master');
      } finally {
        await db.close();
      }
    }

    await expectLater(read(), throwsA(isA<DatabaseException>()));
    expect(File(junk).readAsBytesSync(), before);
  });

  test('a path with spaces and a percent sign opens', () async {
    final odd = Directory(p.join(temp.path, 'a dir %20 #x'))..createSync();
    final copy = p.join(odd.path, 'status.sqlite');
    File(dbPath).copySync(copy);
    final db = await openForeignSqliteReadOnly(copy);
    addTearDown(db.close);
    expect(await db.query('task_status'), hasLength(2));
  });

  group('foreignSqliteUri', () {
    test('POSIX: percent-encoded, read-only, immutable', () {
      expect(
        foreignSqliteUri('/runs/a b/status.sqlite', windows: false),
        'file:///runs/a%20b/status.sqlite?mode=ro&immutable=1',
      );
    });

    test('Windows: a drive path becomes file:///C:/...', () {
      expect(
        foreignSqliteUri(r'C:\runs\status.sqlite', windows: true),
        'file:///C:/runs/status.sqlite?mode=ro&immutable=1',
      );
    });

    test('a ? or # in the path cannot become a query', () {
      final uri = foreignSqliteUri(
        '/runs/x?mode=rw#y/s.sqlite',
        windows: false,
      );
      expect(uri, startsWith('file:///runs/x%3Fmode=rw%23y/s.sqlite?'));
      expect(Uri.parse(uri).queryParameters, {'mode': 'ro', 'immutable': '1'});
    });
  });
}

void _makeReadOnly(String path) {
  Process.runSync('chmod', ['a-w', path]);
}

void _makeWritable(String path) {
  if (Platform.isWindows) return;
  Process.runSync('chmod', ['u+w', path]);
}
