// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/crux_open_policy.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:sqflite_common/sqflite.dart';

/// The schema a store's migration list actually produces at one version.
///
/// Built by *running* the migrations, never by reading them: what a migration
/// says it does and what SQLite ends up with are different things, and only
/// the second one is what a user's file contains. This is the shared input to
/// guard G1 (the fingerprint is frozen) and guard G2 (the table and column
/// sets only ever grow).
@immutable
final class CruxSchemaSnapshot {
  /// Creates a [CruxSchemaSnapshot].
  const CruxSchemaSnapshot({
    required this.version,
    required this.normalisedDdl,
    required this.columnsByTable,
    required this.indexes,
  });

  /// The schema version this snapshot describes.
  final int version;

  /// Every `sqlite_master` entry the migrations produced, normalised and
  /// sorted: `<type> <name> ON <tbl_name> :: <sql>`, with runs of whitespace
  /// collapsed to one space and any trailing semicolon removed.
  ///
  /// Normalisation is what stops a reformat of a `CREATE TABLE` string from
  /// reading as a schema change. Sorting by name is what stops the order
  /// migrations happened to run in from mattering. Internal `sqlite_*` objects
  /// are excluded — they are SQLite's bookkeeping, not our schema.
  final List<String> normalisedDdl;

  /// Column names per table, which is what G2 requires to only ever grow.
  final Map<String, Set<String>> columnsByTable;

  /// Index names. Tracked for the fingerprint but **not** required to grow:
  /// an index carries no data, so dropping one costs a query plan and never a
  /// user's history.
  final Set<String> indexes;

  /// Table names at this version.
  Set<String> get tables => columnsByTable.keys.toSet();

  /// SHA-256 of [normalisedDdl], hex, lower case — the value a manifest line
  /// holds.
  String get fingerprint =>
      sha256.convert(utf8.encode(normalisedDdl.join('\n'))).toString();
}

/// Runs [runner]'s migrations 0 → N in memory for every N from 1 to
/// [CruxMigrationRunner.latestVersion] and snapshots the resulting schema.
///
/// In memory, and one fresh database per version: nothing on disk is touched,
/// nothing carries over between versions, and a snapshot of vN is exactly what
/// a user installing the vN build for the first time would have got. That last
/// property is what makes it sound to compare a snapshot taken today against a
/// fingerprint frozen a year ago — and it holds only while migrations are
/// append-only, which is the very thing G1 is checking.
///
/// [factory] defaults to the global `databaseFactory`; call
/// [ensureCruxSqliteFfiInitialized] first in a pure-Dart test.
Future<List<CruxSchemaSnapshot>> cruxSchemaSnapshotsOf(
  CruxMigrationRunner runner, {
  DatabaseFactory? factory,
}) async {
  final resolved = factory ?? databaseFactory;
  final out = <CruxSchemaSnapshot>[];
  for (var version = 1; version <= runner.latestVersion; version++) {
    final db = await resolved.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute(
          'PRAGMA busy_timeout = ${kCruxSqliteBusyTimeout.inMilliseconds}',
        ),
        // The same routing production uses: a fresh database is built by
        // running the migration list from 0, so this is the historical schema
        // by construction rather than by a second description of it.
        onCreate: (db, v) => runner.upgrade(db, 0, v, reportPath: ':memory:'),
        // Unreachable here — a fresh in-memory database has no version to be
        // ahead of ours. Present because an `OpenDatabaseOptions` carrying a
        // `version:` and no `onDowngrade:` is precisely the shape guard G5
        // exists to reject, and a guard that exempts itself is not a rule.
        onDowngrade: (db, oldVersion, newVersion) async => throw StateError(
          'a fresh in-memory schema snapshot cannot be downgraded '
          '(v$oldVersion -> v$newVersion)',
        ),
      ),
    );
    try {
      out.add(await _snapshot(db, version));
    } finally {
      await db.close();
    }
  }
  return out;
}

Future<CruxSchemaSnapshot> _snapshot(Database db, int version) async {
  final rows = await db.rawQuery(
    'SELECT type, name, tbl_name, sql FROM sqlite_master '
    // `sql IS NOT NULL` drops the implicit indexes SQLite creates for
    // PRIMARY KEY / UNIQUE, which are already implied by the table's own DDL;
    // the `sqlite_` prefix test drops SQLite's internal bookkeeping objects
    // (`sqlite_sequence`, the autoindexes). Neither is our schema, and both
    // would make a fingerprint depend on SQLite's version rather than on ours.
    "WHERE sql IS NOT NULL AND substr(name, 1, 7) <> 'sqlite_'",
  );

  final ddl = <String>[];
  final tables = <String>[];
  final indexes = <String>{};
  for (final row in rows) {
    final type = row['type']! as String;
    final name = row['name']! as String;
    final tbl = row['tbl_name']! as String;
    final sql = _normaliseSql(row['sql']! as String);
    ddl.add('$type $name ON $tbl :: $sql');
    if (type == 'table') tables.add(name);
    if (type == 'index') indexes.add(name);
  }
  ddl.sort();

  final columnsByTable = <String, Set<String>>{};
  for (final table in tables..sort()) {
    final info = await db.rawQuery('PRAGMA table_info("$table")');
    columnsByTable[table] = {for (final c in info) c['name']! as String};
  }

  return CruxSchemaSnapshot(
    version: version,
    normalisedDdl: List<String>.unmodifiable(ddl),
    columnsByTable: Map<String, Set<String>>.unmodifiable(columnsByTable),
    indexes: Set<String>.unmodifiable(indexes),
  );
}

/// Collapses whitespace and strips a trailing semicolon, so that reindenting a
/// `CREATE TABLE` literal is not a schema change and adding a column is.
///
/// Spacing around `(`, `)` and `,` is normalised as well as collapsed, and
/// that is load-bearing rather than fussy. A schema written across aligned
/// columns and the same schema on one line differ by more than runs of
/// whitespace — they differ in whether there is a space after the opening
/// paren — and if the fingerprint noticed, a formatter run would turn G1 red
/// with no way to fix it except editing a manifest line, which is precisely
/// the action G1 exists to forbid. A guard whose only remedy is the forbidden
/// move teaches people to make it.
///
/// Quoted literals are left exactly as they are: a `DEFAULT '(a, b)'` means
/// what it says.
String _normaliseSql(String sql) {
  final collapsed = _collapseOutsideQuotes(sql);
  return collapsed.endsWith(';')
      ? collapsed.substring(0, collapsed.length - 1).trimRight()
      : collapsed;
}

String _collapseOutsideQuotes(String sql) {
  final out = StringBuffer();
  var i = 0;
  final plain = StringBuffer();
  void flushPlain() {
    if (plain.isEmpty) return;
    out.write(
      plain
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\s*([(),])\s*'), r'$1'),
    );
    plain.clear();
  }

  while (i < sql.length) {
    final c = sql[i];
    if (c == "'" || c == '"') {
      flushPlain();
      final end = _endOfQuoted(sql, i);
      out.write(sql.substring(i, end));
      i = end;
      continue;
    }
    plain.write(c);
    i++;
  }
  flushPlain();
  return out.toString().trim();
}

/// The index just past the quoted span starting at [start].
int _endOfQuoted(String sql, int start) {
  final quote = sql[start];
  var i = start + 1;
  while (i < sql.length) {
    if (sql[i] == quote) {
      // SQL escapes a quote by doubling it.
      if (i + 1 < sql.length && sql[i + 1] == quote) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return sql.length;
}
