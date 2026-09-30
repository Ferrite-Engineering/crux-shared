// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_db_recovery.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The four ways opening a Crux SQLite store can fail, as four types.
///
/// **Conflating them is the root defect this package exists to remove.** At a
/// naive catch site they arrive as one exception, and the handler that used to
/// sit there was written for one of them and ran for all of them:
///
/// * **Genuine corruption** — [CruxDatabaseCorruptionException]. The bytes on
///   disk are not a valid SQLite database. The world's fault; the data is
///   unreadable. Recover per [CruxDbRecovery].
/// * **Migration failure** — [CruxMigrationFailedException]. Our own code
///   threw. **Ours**; the data is perfectly fine, rolled back by the
///   transaction. Fail loudly and touch nothing.
/// * **Version skew** — [CruxSchemaVersionSkewException]. The file's version is
///   *higher* than this build's latest. Nobody's fault — two builds, one file;
///   nothing was written. Refuse loudly and touch nothing.
/// * **Backup refusal** — [CruxBackupFailedException]. The environment's fault
///   — a full disk, a read-only directory — and the *only* one of the four
///   that names a thing the user can go and fix. Nothing was written, because
///   the migration was never allowed to start.
///
/// A fifth thing that is none of the four: `SQLITE_BUSY`. It is a live,
/// healthy, busy database, it never becomes one of these types, and it must
/// never trigger any recovery. Reading lock contention as corruption is how
/// the original defect destroyed a user's history.
///
/// This base type is `sealed` so a **diagnostics** surface can switch over the
/// variants exhaustively and be forced to update when another is added. It is
/// **not** a catch target for recovery: `on CruxSqliteException` in a handler
/// that touches a file is the original defect wearing a better name. Catch the
/// narrowest type that can only mean the thing you are handling.
@immutable
sealed class CruxSqliteException implements Exception {
  /// Creates a [CruxSqliteException].
  const CruxSqliteException({required this.storeName, required this.path});

  /// The store's name, as declared on its `CruxMigrationRunner` — the noun a
  /// support conversation uses ("the LintCrux trend store"), not a class name.
  final String storeName;

  /// Absolute path of the database involved. Absolute because a relative
  /// `--db` argument resolved against a CI runner's working directory names
  /// nothing a user can find.
  final String path;

  /// The underlying error, when one exists.
  Object? get cause;

  /// The capture site, when available.
  StackTrace? get stackTrace;
}

/// The bytes at [path] are not a readable SQLite database.
///
/// Raised — or, when a recovery ran, *reported* — by the open policy. It
/// carries what was done about it, so a caller never has to infer the recovery
/// from the [CruxDbRecovery] it passed in:
///
/// * [CruxDbRecovery.renameAside] → delivered to the policy's recovery
///   listener with [quarantinedPath] set. Not thrown: a fresh database opened.
/// * [CruxDbRecovery.recreate] → delivered to the listener with
///   [quarantinedPath] `null`. Not thrown: a fresh database opened.
/// * [CruxDbRecovery.refuse] → **thrown**, with [quarantinedPath] `null` and
///   the file untouched.
///
/// It is emphatically not raised for a migration failure or a version skew.
/// Both leave the data perfectly intact and both propagate as their own type.
final class CruxDatabaseCorruptionException extends CruxSqliteException {
  /// Creates a [CruxDatabaseCorruptionException].
  const CruxDatabaseCorruptionException({
    required super.storeName,
    required super.path,
    required this.recovery,
    required this.quarantinedPath,
    required this.cause,
    this.stackTrace,
  });

  /// The policy that was in force, and therefore what was done to the file.
  final CruxDbRecovery recovery;

  /// Absolute path the damaged file was renamed to, or `null`.
  ///
  /// `null` means the bytes were **not** preserved under a new name, for one
  /// of three reasons that [recovery] distinguishes: [CruxDbRecovery.refuse]
  /// (nothing was attempted, the file is still in place),
  /// [CruxDbRecovery.recreate] (derivable data, the file was deleted), or
  /// [CruxDbRecovery.renameAside] where the rename itself failed — in which
  /// case the file is also still in place.
  ///
  /// It is never a path that was deleted out from under precious data. That is
  /// the one thing this package will not do.
  final String? quarantinedPath;

  /// The underlying `DatabaseException` from the failed open.
  @override
  final Object cause;

  @override
  final StackTrace? stackTrace;

  @override
  String toString() {
    final outcome = switch (recovery) {
      CruxDbRecovery.renameAside when quarantinedPath != null =>
        'it was moved aside to `$quarantinedPath` and a fresh database was '
            'opened in its place',
      CruxDbRecovery.renameAside =>
        'moving it aside FAILED, so it is still in place and a fresh database '
            'was opened over it',
      CruxDbRecovery.recreate =>
        'its contents are derivable, so it was deleted and recreated',
      CruxDbRecovery.refuse =>
        'the store refuses to open it; it has not been modified, and every '
            'byte is still there',
    };
    return 'CruxDatabaseCorruptionException: the $storeName database at '
        '`$path` is not a readable SQLite database — $outcome ($cause).';
  }
}

/// One of our own migrations threw. **This is a bug report, not a recovery
/// case.**
///
/// sqflite runs the version callbacks in one exclusive transaction, so the
/// file is already rolled back: it sits at [fromVersion] with its old schema
/// and all of its data. Nothing about it needs fixing and nothing may touch
/// it. The correct response is to fail loudly and name [version] — the
/// migration that threw — so the fix lands in the right place.
///
/// The distinction this type exists to draw: a corrupt file is the world's
/// fault and recovering from it is defensible; a broken migration is *ours*,
/// and "recovering" from it means deleting perfectly good data because our
/// code had a typo.
final class CruxMigrationFailedException extends CruxSqliteException {
  /// Creates a [CruxMigrationFailedException].
  const CruxMigrationFailedException({
    required super.storeName,
    required super.path,
    required this.version,
    required this.description,
    required this.fromVersion,
    required this.toVersion,
    required this.cause,
    this.backupPath,
    this.stackTrace,
  });

  /// The version of the migration that threw.
  final int version;

  /// That migration's description, so the error names what was being attempted
  /// rather than only a number.
  final String description;

  /// The version the file was at when the upgrade began — and, because the
  /// transaction rolled back, the version it is still at.
  final int fromVersion;

  /// The version the upgrade was heading for.
  final int toVersion;

  /// Absolute path of the pre-upgrade backup taken moments before, when the
  /// store is PRECIOUS and one was written.
  ///
  /// **Nothing was pruned.** A failed migration keeps every backup it has: the
  /// older copies predate whatever change broke, which is exactly what a
  /// bisecting support conversation needs. Naming this file by absolute path is
  /// the difference between "your upgrade failed" and "your upgrade failed and
  /// here is the copy of your data taken one second earlier".
  final String? backupPath;

  /// The error the migration threw.
  @override
  final Object cause;

  @override
  final StackTrace? stackTrace;

  @override
  String toString() {
    final backup = backupPath == null
        ? ''
        : ' A pre-upgrade backup is at `$backupPath` and has not been pruned.';
    return 'CruxMigrationFailedException: migration v$version ($description) '
        'of the $storeName failed while upgrading `$path` from v$fromVersion '
        'to v$toVersion. This is a bug in the migration, not a problem with '
        'the file: the upgrade ran in a transaction, so the database is '
        'unchanged at v$fromVersion with all of its data ($cause).$backup';
  }
}

/// The file at [path] was written by a newer build than this one.
///
/// Nobody's fault — two builds, one file. It happens for real: LintCrux's
/// `push-trends --db` points a CI runner's Pro build at the same `trends.db`
/// the desktop app owns, and the two are not upgraded on the same day.
///
/// The only honest response is a refusal. An older build cannot know what a
/// newer schema means, and the tempting fix — delete the file so this build
/// can create a fresh one — converts a recoverable inconvenience into
/// permanent data loss in the exact situation where the user did nothing
/// wrong. Nothing has been written to the file when this is raised.
///
/// A refusal on its own is honest but unhelpful, so this one carries a way
/// out: [backupPath]. The user who downgraded is, almost by definition, the
/// user who upgraded — and the upgrade took a snapshot of the file at the
/// version they are now back on.
final class CruxSchemaVersionSkewException extends CruxSqliteException {
  /// Creates a [CruxSchemaVersionSkewException].
  const CruxSchemaVersionSkewException({
    required super.storeName,
    required super.path,
    required this.fileVersion,
    required this.appVersion,
    this.fileAppVersion,
    this.backupPath,
    this.cause,
    this.stackTrace,
  });

  /// The schema version stamped in the file.
  final int fileVersion;

  /// The latest version this build knows how to produce, derived from its
  /// migration list.
  final int appVersion;

  /// The **build** that wrote the file, read from its `schema_meta` row, or
  /// `null` when the file predates `schema_meta` or could not be read.
  ///
  /// This is what turns a refusal into an instruction. "This file is at v4 and
  /// I only understand v3" tells a user nothing they can act on: there is no
  /// way from a schema number to a download link, and the number is an
  /// implementation detail they have never seen. "It was written by SimCrux
  /// 0.9.0" names the thing they have to go and launch — and, in the case this
  /// exception was written for, tells a CI runner's log exactly which desktop
  /// build got ahead of it.
  ///
  /// `null` on a file older than the ledger, which is the one population that
  /// still gets the bare numbers. Every file the ledger has touched can answer.
  final String? fileAppVersion;

  /// Absolute path of the newest pre-upgrade backup sitting next to [path],
  /// when one exists.
  ///
  /// **This is the answer to a downgrade.** An older build cannot read a newer
  /// file and never will — but the copy taken the instant before the upgrade
  /// that produced it is a file this build *can* read, and it is right there.
  /// The message names it so the user does not have to know the naming scheme.
  final String? backupPath;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  String toString() {
    final writer = fileAppVersion == null
        ? 'It was written by a newer build.'
        : 'It was written by version $fileAppVersion.';
    final that = fileAppVersion == null
        ? 'that build'
        : 'version $fileAppVersion';
    final wayOut = backupPath == null
        ? 'Open it with $that, or point this one at a different file.'
        : 'Open it with $that, or point this one at the pre-upgrade '
              'backup taken before the file was raised to v$fileVersion: '
              '`$backupPath`.';
    return 'CruxSchemaVersionSkewException: the $storeName database at `$path` '
        'is at schema v$fileVersion, but this build only knows up to '
        'v$appVersion. $writer $wayOut Nothing has '
        'been modified and no data has been lost.';
  }
}

/// Why a pre-upgrade backup did not happen.
///
/// Both values abort the migration. Neither is a "degrade and carry on" — see
/// [CruxBackupFailedException].
enum CruxBackupFailureKind {
  /// The database is past `kCruxBackupSizeGuardBytes` and the volume does not
  /// have `kCruxBackupFreeSpaceHeadroom` × its size free. The `VACUUM INTO`
  /// was never attempted, so no partial file was written and no time was spent
  /// discovering by hand what one `df` already knew.
  insufficientFreeSpace,

  /// `VACUUM INTO` itself failed — a read-only directory, a vanished network
  /// volume, a disk that filled between the check and the write.
  vacuumFailed,
}

/// The pre-upgrade backup of a PRECIOUS database could not be written, so
/// **the migration did not run**.
///
/// This is the loud half of the guide's rule 4, and the loudness is the point.
/// Degrading to "back up if convenient, migrate regardless" would defeat the
/// rule in exactly the three cases it exists for — a full disk, a read-only
/// directory, a network volume that went away — because those are precisely
/// the cases where a migration is most likely to go wrong and least likely to
/// be survivable. An unbacked-up migration of unreconstructible data is the
/// scenario the whole exercise exists to prevent.
///
/// Nothing has been written to the database when this is raised.
/// `sqflite_common` reads `user_version` *after* `onConfigure`, which is where
/// the backup runs, so the exclusive upgrade transaction never opened: the file
/// is still at [fromVersion] with every row it had.
///
/// It is the one failure in this family that names something the user can act
/// on, so its message says what to do rather than only what happened.
final class CruxBackupFailedException extends CruxSqliteException {
  /// Creates a [CruxBackupFailedException].
  const CruxBackupFailedException({
    required super.storeName,
    required super.path,
    required this.kind,
    required this.backupPath,
    required this.fromVersion,
    required this.toVersion,
    required this.databaseBytes,
    required this.freeBytes,
    this.cause,
    this.stackTrace,
  });

  /// Why the backup did not happen.
  final CruxBackupFailureKind kind;

  /// Absolute path the backup would have been written to, or `null` when the
  /// `VACUUM INTO` was never attempted.
  final String? backupPath;

  /// The version the file is still at, because nothing ran.
  final int fromVersion;

  /// The version the upgrade was heading for.
  final int toVersion;

  /// Size of the database on disk, in bytes.
  final int databaseBytes;

  /// Free bytes on the target volume, or `null` when it was not probed or
  /// could not be determined.
  final int? freeBytes;

  @override
  final Object? cause;

  @override
  final StackTrace? stackTrace;

  @override
  String toString() {
    final why = switch (kind) {
      CruxBackupFailureKind.insufficientFreeSpace =>
        'the database is ${_mib(databaseBytes)} and `${p.dirname(path)}` has '
            'only ${_mib(freeBytes ?? 0)} free, which is not enough room for a '
            'copy of it',
      CruxBackupFailureKind.vacuumFailed =>
        'writing `$backupPath` failed ($cause)',
    };
    return 'CruxBackupFailedException: the $storeName database at `$path` '
        'could not be backed up before upgrading it from v$fromVersion to '
        'v$toVersion — $why. The upgrade did NOT run: the file is untouched at '
        'v$fromVersion with all of its data. Free some space, or make the '
        'directory writable, then reopen. Precious data is never migrated '
        'without a backup.';
  }
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
