// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:sqflite_common/sqflite.dart';

/// Why [openForeignSqliteReadOnly] refused a file.
enum CruxForeignDatabaseRefusal {
  /// There is no file at the path.
  missing,

  /// The path names something other than a regular file.
  notAFile,

  /// A non-empty `-wal` file sits beside the database: transactions the
  /// writer committed are still in it, and a read of the main file alone
  /// would miss them.
  notCheckpointed,
}

/// A foreign SQLite file that [openForeignSqliteReadOnly] would not open.
///
/// Not a `CruxSqliteException`: those describe the suite's own stores, which
/// a migration list and a recovery declaration govern, and this file has
/// neither.
final class CruxForeignDatabaseException implements Exception {
  /// Creates the exception.
  const CruxForeignDatabaseException({
    required this.refusal,
    required this.path,
  });

  /// Why the file was refused.
  final CruxForeignDatabaseRefusal refusal;

  /// The absolute path that was asked for.
  final String path;

  @override
  String toString() => switch (refusal) {
    CruxForeignDatabaseRefusal.missing =>
      'CruxForeignDatabaseException: no database at $path',
    CruxForeignDatabaseRefusal.notAFile =>
      'CruxForeignDatabaseException: $path is not a file',
    CruxForeignDatabaseRefusal.notCheckpointed =>
      'CruxForeignDatabaseException: $path has a write-ahead log its writer '
          'has not checkpointed; read it after the writer has closed it',
  };
}

/// Opens a SQLite file another tool wrote, to read it and nothing else.
///
/// This is the suite's only open of a database it does not own (a formal
/// engine's `status.sqlite`, say). It runs no migration, writes no
/// `schema_meta`, sets no `user_version` and takes no backup: the file's
/// schema belongs to the tool that wrote it, and stamping it would change a
/// file the user's own tooling reads.
///
/// **Opened immutable** (an SQLite URI with `immutable=1`, read-only). A
/// plain read-only open of a WAL-mode file still creates or writes its
/// `-shm` shared-memory file, and on a read-only directory fails outright;
/// immutable opens neither the `-shm` nor the `-wal`, takes no lock, and
/// writes nothing anywhere. The price is SQLite's own: it assumes nothing
/// changes the file while it is open. So:
///
/// - open it only once the writer has exited, and close it promptly;
/// - a non-empty `-wal` beside the file means the writer left committed
///   transactions there (it was killed, or never checkpointed), which an
///   immutable read would silently miss: that file is refused with
///   [CruxForeignDatabaseRefusal.notCheckpointed] rather than read as if
///   complete.
///
/// [path] is made absolute against the working directory; symlinks are left
/// for SQLite to follow. Containment is the caller's: check the path against
/// the directory it is allowed to come from (`isPathWithin` in `crux_io`)
/// before calling.
///
/// Throws [CruxForeignDatabaseException] for the refusals above, and the
/// factory's `DatabaseException` when the bytes are not a SQLite database.
/// Never deletes, renames or repairs anything.
///
/// [factory] defaults to the global `databaseFactory` (see
/// `ensureCruxSqliteFfiInitialized`).
Future<Database> openForeignSqliteReadOnly(
  String path, {
  DatabaseFactory? factory,
}) async {
  final absolute = canonicalizePath(path, resolveSymlinks: false);
  final type = FileSystemEntity.typeSync(absolute);
  if (type == FileSystemEntityType.notFound) {
    throw CruxForeignDatabaseException(
      refusal: CruxForeignDatabaseRefusal.missing,
      path: absolute,
    );
  }
  if (type != FileSystemEntityType.file) {
    throw CruxForeignDatabaseException(
      refusal: CruxForeignDatabaseRefusal.notAFile,
      path: absolute,
    );
  }
  final wal = File('$absolute-wal');
  if (wal.existsSync() && wal.lengthSync() > 0) {
    throw CruxForeignDatabaseException(
      refusal: CruxForeignDatabaseRefusal.notCheckpointed,
      path: absolute,
    );
  }
  final resolved = factory ?? databaseFactory;
  return await resolved.openDatabase(
    foreignSqliteUri(absolute, windows: Platform.isWindows),
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
}

/// The SQLite URI [openForeignSqliteReadOnly] opens for the absolute path
/// [absolute]: `file:` with the path percent-encoded, `mode=ro` and
/// `immutable=1`.
///
/// Pure, so the Windows form (`file:///C:/...`) is testable on every host.
String foreignSqliteUri(String absolute, {required bool windows}) {
  final file = Uri.file(absolute, windows: windows);
  return file
      .replace(queryParameters: const {'mode': 'ro', 'immutable': '1'})
      .toString();
}
