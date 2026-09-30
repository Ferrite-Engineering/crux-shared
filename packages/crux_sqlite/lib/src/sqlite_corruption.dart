// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:sqflite_common/sqflite.dart';

/// SQLite primary result code 11 — the database disk image is malformed.
const int _kSqliteCorrupt = 11;

/// SQLite primary result code 26 — the file is not a database (a truncated or
/// overwritten header, most often).
const int _kSqliteNotADb = 26;

/// Whether [error] means the **bytes on disk are not a readable SQLite
/// database** — and nothing else.
///
/// Deliberately narrow, and the narrowness is the whole point. `SQLITE_BUSY`
/// (5), `SQLITE_LOCKED` (6), `SQLITE_READONLY` (8) and `SQLITE_CANTOPEN` (14)
/// all describe a file that is completely fine, and every one of them used to
/// reach a handler that deleted it. A busy database is a live, healthy,
/// *working* database; it must never read as a corrupt one.
///
/// Two signals, because neither is reliable alone: `getResultCode()` returns
/// the extended code under `sqflite_common_ffi` (so the primary code is the low
/// byte), but it parses the native message and can come back null, in which
/// case the canonical SQLite corruption phrases are the fallback.
///
/// Anything that is not a `DatabaseException` is not corruption either — a
/// `FileSystemException`, a `StateError` from our own code, or one of this
/// package's typed failures all answer `false`.
bool isSqliteCorruption(Object error) {
  if (error is! DatabaseException) return false;
  final code = error.getResultCode();
  if (code != null) {
    final primary = code & 0xFF;
    if (primary == _kSqliteCorrupt || primary == _kSqliteNotADb) return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('file is not a database') ||
      text.contains('file is encrypted or is not a database') ||
      text.contains('database disk image is malformed') ||
      text.contains('not a database');
}

/// Renames the damaged database at [dbPath] aside to
/// `<dbPath>.corrupt-<timestamp>` and returns the new path, or `null` if even
/// the rename failed.
///
/// **Never deletes.** A precious store's contents cannot be rebuilt from
/// anything else on disk, and the app cannot tell "this file is garbage" from
/// "this file is fine and I have a bug" — so the worst permitted action is the
/// reversible one. The user keeps the bytes and support can ask for them.
///
/// The `-wal`, `-shm` and `-journal` sidecars move with the main file. A stale
/// WAL left beside a freshly created database of the same name is a second
/// corruption waiting to happen, because SQLite would take it to belong to the
/// new file.
///
/// [now] is injectable for tests; it is stamped in **ISO 8601 basic** form
/// (`20260820T090000Z`). The extended form's colons are illegal in a Windows
/// filename, and LintCrux ships on Windows.
String? quarantineDatabaseFile(String dbPath, {DateTime? now}) {
  final stamp = _basicIso8601Utc(now ?? DateTime.now());
  var target = '$dbPath.corrupt-$stamp';
  // Two quarantines inside the same second would collide; a suffix is cheaper
  // than losing the first one.
  for (var n = 1; File(target).existsSync(); n++) {
    target = '$dbPath.corrupt-$stamp-$n';
  }
  try {
    File(dbPath).renameSync(target);
  } on FileSystemException {
    return null;
  }
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final sidecar = File('$dbPath$suffix');
    if (!sidecar.existsSync()) continue;
    try {
      sidecar.renameSync('$target$suffix');
    } on FileSystemException {
      // Best effort. A sidecar we could not move is a nuisance, not a reason to
      // abandon a quarantine that already succeeded.
    }
  }
  return target;
}

/// `2026-08-20T09:00:00.000Z` → `20260820T090000Z`.
String _basicIso8601Utc(DateTime when) {
  final utc = when.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}'
      '${two(utc.second)}Z';
}
