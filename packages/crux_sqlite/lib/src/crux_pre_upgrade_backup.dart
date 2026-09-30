// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_sqlite/src/crux_sqlite_exceptions.dart';
import 'package:crux_sqlite/src/free_disk_space.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqflite.dart';

/// How many pre-upgrade backups survive a successful migration.
///
/// Two, not one: the interesting failure is a migration that *succeeded* and
/// corrupted the data semantically — an `ADD COLUMN` backfilled from the wrong
/// source, a unit conversion applied twice — which nobody notices on the day it
/// ships. With N=1 the next upgrade's backup evicts the last good copy before
/// the user has looked at their charts. Two spans one release gap, which is the
/// window in which someone actually says "these numbers are wrong now".
///
/// Not larger, because these files are the same order of magnitude as the
/// database itself and this is a user's disk, not ours.
const int kCruxBackupsKept = 2;

/// Above this database size, free disk space is checked before `VACUUM INTO`
/// is attempted at all.
///
/// **256 MiB, derived from what these files actually reach.** SimCrux's default
/// retention policy (`RetentionPolicy.defaultPolicy`) caps the trend store at
/// 50 000 `test_results` rows over 30 days. A row is four UUID/name `TEXT`
/// columns, two paths, two JSON blobs and three integers — call it ~400 bytes
/// of payload — carried by five indexes over `test_results` whose `TEXT` keys
/// add roughly another 200. So ~600 bytes a row, ~30 MB at the cap, and
/// `SqlTrendStore.kVacuumMinReclaimableBytes` (8 MiB "worth a full-file
/// rewrite") corroborates a file in exactly that band. LintCrux's `trends.db`
/// is the same shape and `acknowledged_alerts.db` is three orders of magnitude
/// smaller.
///
/// 256 MiB is therefore ~8× the largest a healthy, retention-bounded Crux
/// database gets. A file above it is one where retention was set to
/// [`unlimited`] or where a CI runner's `push-trends --db` has been
/// accumulating against a team share for a very long time — both supported, and
/// both the cases where doubling the file on disk is worth one `df` first.
///
/// The threshold is a *cost* switch, not a *policy* switch: below it we skip
/// the probe, above it we run one. It never decides whether a backup is
/// required. That is decided by whether the data is precious, and the answer is
/// always yes.
const int kCruxBackupSizeGuardBytes = 256 * 1024 * 1024;

/// Multiple of the database size that must be free before `VACUUM INTO` is
/// attempted past [kCruxBackupSizeGuardBytes].
///
/// `VACUUM INTO` writes a *compacted* copy, so the output is at most the size
/// of the input and usually smaller; 1.1 covers the page-boundary rounding and
/// leaves the volume something to breathe with afterwards.
const double kCruxBackupFreeSpaceHeadroom = 1.1;

/// What the pre-upgrade backup did, told to a [CruxBackupListener].
///
/// Delivered on **both** outcomes. A backup that silently did not happen is the
/// failure mode this whole mechanism exists to remove, so the skip is reported
/// as loudly as the success — and, separately, aborts the migration.
@immutable
final class CruxBackupNotice {
  /// Creates a [CruxBackupNotice].
  const CruxBackupNotice({
    required this.storeName,
    required this.databasePath,
    required this.backupPath,
    required this.fromVersion,
    required this.toVersion,
    required this.databaseBytes,
    required this.freeBytes,
    required this.failure,
  });

  /// The store's name, as declared on its `CruxMigrationRunner`.
  final String storeName;

  /// Absolute path of the database about to be upgraded.
  final String databasePath;

  /// Absolute path of the backup, written or intended. `null` when the
  /// `VACUUM INTO` was never attempted.
  final String? backupPath;

  /// The version the file is at now, and the version it would be restored to.
  final int fromVersion;

  /// The version the upgrade is heading for.
  final int toVersion;

  /// Size of the database on disk when the decision was taken.
  final int databaseBytes;

  /// Free bytes on the target volume, or `null` when the probe was not run
  /// (the common case — see [kCruxBackupSizeGuardBytes]) or could not answer.
  final int? freeBytes;

  /// `null` when the backup was written.
  final CruxBackupFailureKind? failure;

  /// Whether a usable backup now exists at [backupPath].
  bool get created => failure == null;

  @override
  String toString() {
    final size = _mib(databaseBytes);
    return switch (failure) {
      null =>
        'CruxBackupNotice: the $storeName database at `$databasePath` '
            '($size) was backed up to `$backupPath` before upgrading it from '
            'v$fromVersion to v$toVersion.',
      CruxBackupFailureKind.insufficientFreeSpace =>
        'CruxBackupNotice: the $storeName database at `$databasePath` is '
            '$size and the volume has only ${_mib(freeBytes ?? 0)} free, so '
            'the pre-upgrade backup was not attempted and the v$fromVersion → '
            'v$toVersion upgrade did not run.',
      CruxBackupFailureKind.vacuumFailed =>
        'CruxBackupNotice: backing up the $storeName database at '
            '`$databasePath` ($size) to `$backupPath` FAILED, so the '
            'v$fromVersion → v$toVersion upgrade did not run.',
    };
  }
}

/// Told what the pre-upgrade backup did.
///
/// A plain callback rather than a stream or a provider because this package is
/// pure Dart and must stay that way.
typedef CruxBackupListener = void Function(CruxBackupNotice notice);

/// Writes a `VACUUM INTO` snapshot of a PRECIOUS database immediately before
/// its schema is upgraded, and prunes the older ones once the upgrade lands.
///
/// **A store opts in by being precious, not by remembering to call this.** It
/// hangs off `CruxSqliteOpenPolicy`, which reads the store's own
/// `CruxDbRecovery` — the data-value declaration it already had to make — and
/// runs a backup for every value except `recreate`. A backup you have to
/// remember is a backup somebody will forget, and the store that forgets is
/// the one whose data nobody can get back.
///
/// ## Why `VACUUM INTO` and never a file copy
///
/// The bytes of a SQLite file are not the database. With a hot rollback journal
/// beside it — and there is one, because this suite deliberately did not adopt
/// WAL — a copy taken while a connection is open captures pages the journal was
/// about to undo. The copy opens, queries, and is subtly wrong, which is worse
/// than having no backup at all because it is *trusted*. `VACUUM INTO` asks
/// SQLite for a consistent snapshot through the same connection that holds the
/// locks. The moment before a migration is precisely the moment we cannot
/// afford to find that distinction out.
///
/// ## Where it runs
///
/// From `onConfigure`, which `sqflite_common` invokes **outside** the exclusive
/// version transaction and **before** it reads `user_version` (verified against
/// `database_mixin.dart` 2.5.11). That placement is forced, not chosen:
/// `VACUUM` cannot run inside a transaction at all, so `onUpgrade` — which
/// sqflite has already wrapped in one — is not an available hook. It is also
/// the correct placement on its own terms: the file at that instant is exactly
/// the pre-migration file.
@immutable
final class CruxPreUpgradeBackup {
  /// Creates a backup policy. Every parameter has a suite default; they exist
  /// to be injected by tests, not tuned per store.
  const CruxPreUpgradeBackup({
    this.keep = kCruxBackupsKept,
    this.sizeGuardBytes = kCruxBackupSizeGuardBytes,
    this.onBackup,
    this.freeDiskProbe = cruxFreeDiskBytes,
    this.clock,
  });

  /// How many backups survive a successful migration. See [kCruxBackupsKept].
  final int keep;

  /// Database size past which free space is probed. See
  /// [kCruxBackupSizeGuardBytes].
  final int sizeGuardBytes;

  /// Told what the backup did, on success and on failure alike.
  final CruxBackupListener? onBackup;

  /// How free disk space is measured. Injectable because a unit test cannot
  /// fill a real volume.
  final CruxFreeDiskProbe freeDiskProbe;

  /// Injectable clock for the filename stamp. Defaults to `DateTime.now`.
  final DateTime Function()? clock;

  /// Backs up [dbPath] if — and only if — opening it is about to run an
  /// upgrade.
  ///
  /// Returns the absolute path of the backup, or `null` when none was needed:
  /// a fresh file (`user_version` 0, which is `onCreate`, and an empty file is
  /// not worth a snapshot), an already-current file, an in-memory database, or
  /// a path with nothing at it yet.
  ///
  /// Throws [CruxBackupFailedException] when a backup *was* needed and could
  /// not be written. The caller must not swallow it: sqflite has not opened the
  /// version transaction at this point, so throwing here is what stops the
  /// migration.
  ///
  /// [db] must be the connection sqflite is opening, in `onConfigure`.
  Future<String?> beforeUpgrade(
    DatabaseExecutor db, {
    required String storeName,
    required String dbPath,
    required int newVersion,
  }) async {
    if (dbPath == inMemoryDatabasePath) return null;
    final oldVersion = await _readUserVersion(db);
    // 0 is `onCreate` — there is no prior schema and no data to lose. A file
    // already at or above `newVersion` is not being upgraded; the >= case is a
    // downgrade, which refuses without ever touching the file and is pointed
    // at whatever earlier backup already exists.
    if (oldVersion <= 0 || oldVersion >= newVersion) return null;

    final file = File(dbPath);
    if (!file.existsSync()) return null;
    final databaseBytes = file.lengthSync();

    // The size guard. Below the threshold — where every retention-bounded Crux
    // database lives — no volume probe runs at all and this costs one `stat`.
    int? freeBytes;
    if (databaseBytes > sizeGuardBytes) {
      freeBytes = freeDiskProbe(p.dirname(dbPath));
      // `null` is "unknown", not "zero": we proceed and let the write be the
      // judge, because a probe that could not answer is not evidence of a full
      // disk.
      if (freeBytes != null &&
          freeBytes < databaseBytes * kCruxBackupFreeSpaceHeadroom) {
        throw _fail(
          storeName: storeName,
          dbPath: dbPath,
          kind: CruxBackupFailureKind.insufficientFreeSpace,
          backupPath: null,
          oldVersion: oldVersion,
          newVersion: newVersion,
          databaseBytes: databaseBytes,
          freeBytes: freeBytes,
        );
      }
    }

    final target = _freeTargetPath(dbPath, oldVersion);
    try {
      // Bound parameter, not string interpolation: a Windows path is full of
      // backslashes and a project directory can contain an apostrophe, and
      // neither should be this code's problem.
      await db.execute('VACUUM INTO ?', <Object?>[target]);
    } on Object catch (error, stackTrace) {
      // A failed `VACUUM INTO` can leave a partial output file. It is ours — we
      // proved the name was unused a line ago — and leaving it behind would
      // make the *next* open think a backup exists. Removing it touches no
      // user data; nothing in this method ever touches the database itself.
      _deleteQuietly(target);
      throw _fail(
        storeName: storeName,
        dbPath: dbPath,
        kind: CruxBackupFailureKind.vacuumFailed,
        backupPath: target,
        oldVersion: oldVersion,
        newVersion: newVersion,
        databaseBytes: databaseBytes,
        freeBytes: freeBytes,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    onBackup?.call(
      CruxBackupNotice(
        storeName: storeName,
        databasePath: dbPath,
        backupPath: target,
        fromVersion: oldVersion,
        toVersion: newVersion,
        databaseBytes: databaseBytes,
        freeBytes: freeBytes,
        failure: null,
      ),
    );
    return target;
  }

  /// Deletes all but the newest [keep] backups of [dbPath].
  ///
  /// **Only ever called after an upgrade has succeeded.** A failed migration
  /// prunes nothing: the older copies are the ones from before whatever change
  /// broke, and they are exactly what a bisecting support conversation needs.
  ///
  /// Deletes `.bak` files and nothing else. It cannot reach a `.db`, which is
  /// what keeps it on the right side of guard G4.
  void pruneAfterSuccessfulUpgrade(String dbPath) {
    backupsFor(dbPath).skip(keep).forEach(_deleteQuietly);
  }

  /// Every existing backup of [dbPath], newest first, as absolute paths.
  ///
  /// Ordered by the stamp in the filename rather than by mtime: the name is
  /// what a user reads and a support engineer quotes, and a file copied off a
  /// machine keeps its name while losing its mtime.
  static List<String> backupsFor(String dbPath) {
    final dir = Directory(p.dirname(dbPath));
    if (!dir.existsSync()) return const <String>[];
    final pattern = RegExp(
      '^${RegExp.escape(p.basename(dbPath))}'
      r'\.pre-v(\d+)-(\d{8}T\d{6}Z)(?:-(\d+))?\.bak$',
    );
    final found = <({String path, String stamp, int seq})>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final match = pattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;
      found.add((
        path: entity.path,
        stamp: match.group(2)!,
        seq: int.tryParse(match.group(3) ?? '0') ?? 0,
      ));
    }
    found.sort((a, b) {
      final byStamp = b.stamp.compareTo(a.stamp);
      if (byStamp != 0) return byStamp;
      final bySeq = b.seq.compareTo(a.seq);
      return bySeq != 0 ? bySeq : b.path.compareTo(a.path);
    });
    return <String>[for (final entry in found) entry.path];
  }

  /// The newest backup of [dbPath], or `null` when there is none.
  ///
  /// This is what a downgrade error names. A user who installed an older build
  /// over an upgraded file cannot open it — and does not have to, because the
  /// copy taken the instant before that upgrade is sitting next to it.
  static String? latestBackupFor(String dbPath) {
    final all = backupsFor(dbPath);
    return all.isEmpty ? null : all.first;
  }

  /// The backup filename for [dbPath] at [oldVersion], stamped at [now].
  ///
  /// `<db>.pre-v<oldVersion>-<ISO 8601 basic UTC>.bak`, e.g.
  /// `trends.db.pre-v2-20260820T090000Z.bak`. **Basic** form, matching
  /// `quarantineDatabaseFile`: the extended form's colons are illegal in a
  /// Windows filename and LintCrux ships on Windows.
  ///
  /// The version is the one to restore *to*, which is the number a user has —
  /// they know which build they are going back to, not what date they upgraded.
  static String backupPathFor(
    String dbPath, {
    required int oldVersion,
    DateTime? now,
  }) =>
      '$dbPath.pre-v$oldVersion-${_basicIso8601Utc(now ?? DateTime.now())}'
      '.bak';

  String _freeTargetPath(String dbPath, int oldVersion) {
    final base = backupPathFor(dbPath, oldVersion: oldVersion, now: _now());
    // `VACUUM INTO` refuses an existing output file, and two upgrades inside
    // one second is reachable in a test suite and on a fast machine opening
    // several stores at once. A suffix is cheaper than an aborted migration.
    if (!File(base).existsSync()) return base;
    final stem = base.substring(0, base.length - '.bak'.length);
    for (var n = 1; ; n++) {
      final candidate = '$stem-$n.bak';
      if (!File(candidate).existsSync()) return candidate;
    }
  }

  DateTime _now() => (clock ?? DateTime.now)();

  CruxBackupFailedException _fail({
    required String storeName,
    required String dbPath,
    required CruxBackupFailureKind kind,
    required String? backupPath,
    required int oldVersion,
    required int newVersion,
    required int databaseBytes,
    required int? freeBytes,
    Object? cause,
    StackTrace? stackTrace,
  }) {
    onBackup?.call(
      CruxBackupNotice(
        storeName: storeName,
        databasePath: dbPath,
        backupPath: backupPath,
        fromVersion: oldVersion,
        toVersion: newVersion,
        databaseBytes: databaseBytes,
        freeBytes: freeBytes,
        failure: kind,
      ),
    );
    return CruxBackupFailedException(
      storeName: storeName,
      path: dbPath,
      kind: kind,
      backupPath: backupPath,
      fromVersion: oldVersion,
      toVersion: newVersion,
      databaseBytes: databaseBytes,
      freeBytes: freeBytes,
      cause: cause,
      stackTrace: stackTrace,
    );
  }

  static Future<int> _readUserVersion(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    final value = rows.first.values.first;
    return value is int ? value : 0;
  }

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Best effort. A leftover we could not remove is a nuisance, never a
      // reason to fail an operation that otherwise succeeded.
    }
  }
}

/// `2026-08-20T09:00:00.000Z` → `20260820T090000Z`.
String _basicIso8601Utc(DateTime when) {
  final utc = when.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}'
      '${two(utc.second)}Z';
}

String _mib(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
