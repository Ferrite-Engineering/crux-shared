// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:sqflite_common/sqflite.dart';

/// Column names of [table], via `PRAGMA table_info`.
///
/// A fixture assertion's usual first check: that a new column exists (and,
/// separately, via a row query, that it carries the declared default or
/// backfilled value — this only proves the shape).
Future<Set<String>> cruxColumnNamesOf(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return {for (final row in rows) row['name']! as String};
}

/// Index names declared in [db] — on [table] only, when given, or every
/// index in the file otherwise — from `sqlite_master`.
///
/// What guard G1 fingerprints and what a data-preserving fixture must show
/// survived the upgrade: "every index the head schema declares is present"
/// (README, "Adding a migration", step 5).
Future<Set<String>> cruxIndexNamesOf(Database db, {String? table}) async {
  final rows = table == null
      ? await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index'",
        )
      : await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND "
          'tbl_name = ?',
          <Object?>[table],
        );
  return {for (final row in rows) row['name']! as String};
}
