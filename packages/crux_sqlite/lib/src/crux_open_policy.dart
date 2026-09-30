// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/crux_io.dart';
import 'package:crux_sqlite/src/crux_db_recovery.dart';
import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/crux_pre_upgrade_backup.dart';
import 'package:crux_sqlite/src/crux_schema_meta.dart';
import 'package:crux_sqlite/src/crux_sqlite_exceptions.dart';
import 'package:crux_sqlite/src/sqlite_corruption.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

/// The suite's `busy_timeout`, applied on every open, with no exceptions and
/// no per-store override.
///
/// **Mandatory, not a nicety.** Without it, a concurrent opener that meets a
/// held lock gets `SQLITE_BUSY` *immediately* — no retry, no back-off — and
/// that surfaces as a `DatabaseException` which a naive handler cannot tell
/// from a corrupt file. The worst consequence of the defect this package
/// exists to remove came from exactly that composition: no timeout, so
/// ordinary lock contention raised an exception, and the handler deleted the
/// user's history. Lock contention read as corruption.
///
/// It is not a parameter because a store does not get to decide this. Five
/// seconds is generous for every transaction any Crux store performs and short
/// enough that a genuinely stuck lock still surfaces. The mechanism cooperates:
/// sqflite runs `onConfigure` *outside* the version transaction and before the
/// version check, so the timeout is already in force when a migration's own
/// exclusive lock is attempted.
const Duration kCruxSqliteBusyTimeout = Duration(milliseconds: 5000);

/// Told what a recovery did to a database file.
///
/// Receives a [CruxDatabaseCorruptionException] describing the damaged file
/// and the action taken. It is a plain callback rather than a stream or a
/// provider because this package is pure Dart and must stay that way — the
/// host adapts it to whatever diagnostics seam it has.
typedef CruxDbRecoveryListener =
    void Function(CruxDatabaseCorruptionException notice);

/// Initialises `sqflite_common_ffi` and promotes its factory to the global
/// `databaseFactory`. Idempotent.
///
/// Here rather than copied into each store, which is where it was: two
/// products had a private `_ensureFfiInitialized` with identical bodies, and a
/// third store that forgot it would fail at its first open in a way that looks
/// nothing like the cause.
void ensureCruxSqliteFfiInitialized() {
  ffi.sqfliteFfiInit();
  databaseFactory = ffi.databaseFactoryFfi;
}

/// **The one place in the suite an `OpenDatabaseOptions` is constructed.**
///
/// A store supplies three things — a migration list (via [runner]), a
/// data-value declaration ([recovery]), and a path — and gets a correctly
/// opened database. It does not write its own `onDowngrade`, does not decide
/// its own `busy_timeout`, does not own a copy of the upgrade loop, and does
/// not catch `on Object` around an open. Every one of those was a per-store
/// opinion before this package existed, and the four opinions disagreed.
///
/// If a store cannot open through this policy, **that is a bug here to be
/// fixed**, not a reason to hand-roll a fifth open path. Working around it is
/// how the suite came to have five, one of which deleted user data.
///
/// ## Journal mode: WAL was evaluated and deliberately NOT adopted
///
/// Recorded here rather than left implicit, because `journal_mode` is per-FILE
/// and PERSISTENT: whoever sets it decides for every other opener of that file,
/// forever — including builds that predate the decision and the `sqlite3` shell
/// a support engineer runs on a user's copy. "We didn't think about it" and "we
/// thought about it and chose the default" look identical in source, so the
/// difference has to be written down.
///
/// WAL's appeal is real: `trends.db` has a genuine concurrent reader (the GUI)
/// and writer (`push-trends`), and WAL lets them proceed without blocking each
/// other. It still loses:
///
///  1. **WAL does not work on a network filesystem.** It needs the shared
///     memory the `-shm` file provides via mmap, which SMB and NFS do not
///     implement correctly; SQLite's own documentation says so. And
///     `push-trends --db` pointing at a file on a team share is a documented,
///     supported configuration. Adopting WAL would convert a working setup into
///     a hard open failure, on a file we have just finished promising never to
///     damage.
///  2. **It is not reversible per-process.** A file the GUI flips to WAL stays
///     WAL when yesterday's CLI build opens it. That is fine technically and
///     precisely wrong as a way to decide something: it would ship as a side
///     effect of an open call rather than as a migration anyone reviewed.
///  3. **The concurrency it buys is already bought.** Every transaction these
///     stores run is short — one batched insert per run, one retention delete —
///     and [kCruxSqliteBusyTimeout] covers contention between them with room to
///     spare.
///
/// Revisit if a shared-database mode ever makes contention real: that needs its
/// own ruling and a migration that sets `journal_mode` deliberately, not a
/// pragma quietly added to an open path.
///
/// ## Foreign-key enforcement stays OFF
///
/// `PRAGMA foreign_keys` is deliberately not set. It is a **no-op inside a
/// transaction**, and sqflite runs every migration inside an exclusive one — so
/// a migration that needs the 12-step table rebuild could not turn enforcement
/// off for the rebuild, which would make the rebuild impossible from inside
/// this shared open path. The existing `REFERENCES` clauses stay as
/// documentation and as the input to `PRAGMA foreign_key_check`, which a table
/// rebuild runs (README, "When additive is not enough").
final class CruxSqliteOpenPolicy {
  /// Creates an open policy.
  ///
  /// Throws [ArgumentError] when [recovery] is anything other than
  /// [CruxDbRecovery.refuse] and no [onRecovery] listener is supplied. **A
  /// silent recovery is not an available shape.** A chart that is empty because
  /// the file was quarantined looks exactly like a chart that is empty because
  /// nothing has run yet, and a cache that rebuilds itself on every launch is a
  /// bug nobody ever sees. A store with nowhere to put a notice declares
  /// [CruxDbRecovery.refuse] and destroys nothing, which is the honest answer.
  CruxSqliteOpenPolicy({
    required this.runner,
    required this.recovery,
    this.onRecovery,
    this.backup = const CruxPreUpgradeBackup(),
  }) {
    if (recovery != CruxDbRecovery.refuse && onRecovery == null) {
      throw ArgumentError.value(
        onRecovery,
        'onRecovery',
        'CruxDbRecovery.${recovery.name} moves or deletes the '
            "${runner.storeName}'s file, so it requires a recovery listener to "
            'say so. A store with no diagnostics seam declares '
            'CruxDbRecovery.refuse instead — refusing destroys nothing',
      );
    }
  }

  /// The store's migration list, and the only source of its schema version.
  final CruxMigrationRunner runner;

  /// What this store's contents are worth: see [CruxDbRecovery].
  final CruxDbRecovery recovery;

  /// Told whenever a recovery moved or deleted the file. Required unless
  /// [recovery] is [CruxDbRecovery.refuse].
  final CruxDbRecoveryListener? onRecovery;

  /// The pre-upgrade backup mechanism, applied automatically to every store
  /// whose [recovery] says its data is PRECIOUS.
  ///
  /// **Not an opt-in.** There is no `backupsEnabled` flag and no way for a
  /// store to pass a no-op: [CruxDbRecovery.isPrecious] decides, from the
  /// data-value declaration the store already had to make. Supplying a value
  /// here tunes *how* — a listener for diagnostics, an injected clock and free
  /// space probe for tests — never *whether*.
  final CruxPreUpgradeBackup backup;

  /// Whether opening this store takes a `VACUUM INTO` snapshot before any
  /// upgrade. Equivalent to `recovery.isPrecious`, restated at this level
  /// because this is where a reader looks for it.
  bool get backsUpBeforeUpgrade => recovery.isPrecious;

  /// Builds the options for opening [path].
  ///
  /// **Total by construction.** There is no parameter that omits
  /// `onDowngrade`, none that omits the `busy_timeout`, and none that supplies
  /// a version independent of the migration list — so a non-conforming options
  /// object is not expressible, and the retry inside [open] cannot silently
  /// differ from the first attempt the way a hand-rolled second options object
  /// did.
  ///
  /// [onMigrationStart] fires at the top of both `onCreate` and `onUpgrade`,
  /// before any migration runs. It is how a caller learns that a failure came
  /// from *inside* the version transaction — which makes it our bug, on a file
  /// that has already rolled back — rather than from the open itself. [open]
  /// uses it for exactly that; a caller doing its own open must, too.
  OpenDatabaseOptions buildOptions({
    required String path,
    void Function()? onMigrationStart,
  }) {
    // Set in `onConfigure` and read by everything after it. Local to this one
    // options object, so two concurrent opens of two stores cannot see each
    // other's backup.
    String? backupPath;

    return OpenDatabaseOptions(
      // Derived from the migration list. There is no version constant to bump
      // and therefore none to forget.
      version: runner.latestVersion,
      onConfigure: (db) async {
        await db.execute(
          'PRAGMA busy_timeout = ${kCruxSqliteBusyTimeout.inMilliseconds}',
        );
        // The pre-upgrade backup, and the only place it can go.
        //
        // `sqflite_common` calls `onConfigure` OUTSIDE the exclusive version
        // transaction and BEFORE it reads `user_version` (database_mixin.dart
        // 2.5.11, verified). Both halves matter: `VACUUM` cannot run inside a
        // transaction at all, so `onUpgrade` — already wrapped in one — is not
        // an available hook, and the file at this instant is exactly the
        // pre-migration file.
        //
        // A throw from here aborts the open before the upgrade transaction is
        // ever opened, which is precisely rule 4's "if the backup fails, the
        // migration does not run". `CruxBackupFailedException` is deliberately
        // NOT a `DatabaseException`, so it sails past the corruption catch in
        // `open()` rather than being mistaken for a damaged file.
        if (recovery.isPrecious) {
          backupPath = await backup.beforeUpgrade(
            db,
            storeName: runner.storeName,
            dbPath: path,
            newVersion: runner.latestVersion,
          );
        }
        // The `last_opened_by_app_version` stamp, and the reason there is no
        // `onOpen` on this options object.
        //
        // `onConfigure` is already non-null on every Crux open (the
        // `busy_timeout` above), so writing here adds no `await` to
        // `sqflite_common`'s open sequence. `onOpen` would: a non-null
        // `onOpen` was measured reordering the open against a previous test's
        // pending `close()` under `flutter_test`'s fake-async zone and
        // deadlocking six LintCrux Pro widget tests on the sixth `:memory:`
        // open.
        //
        // AFTER the backup, deliberately. The snapshot has to be the file as
        // it was before this process touched it; a backup containing our own
        // open stamp is a backup of a file that never existed.
        //
        // `writeCruxSchemaMetaForOpen` writes only when the file is already at
        // the latest version — so it never precedes a migration whose failure
        // is documented as leaving the file untouched, and never modifies a
        // file this build is about to refuse as too new.
        await writeCruxSchemaMetaForOpen(
          db,
          identity: runner.identity,
          latestVersion: runner.latestVersion,
        );
      },
      onCreate: (db, version) async {
        onMigrationStart?.call();
        // A fresh install runs the same code as an upgraded one, from 0. This
        // is what makes the two converge on one schema, and it is the single
        // most important line in this file.
        await runner.upgrade(db, 0, version, reportPath: path);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        onMigrationStart?.call();
        await runner.upgrade(
          db,
          oldVersion,
          newVersion,
          reportPath: path,
          backupPath: backupPath,
        );
        // Pruning happens HERE — after every migration in the range has
        // succeeded, and nowhere else.
        //
        // A migration that throws never reaches this line, so a failed upgrade
        // keeps every backup it has: the older copies predate whatever change
        // broke, which is exactly what a bisecting support conversation needs.
        // That is the property that matters and it holds exactly.
        //
        // `onOpen` would be the textbook answer — it runs after the
        // transaction commits — but it is deliberately not used. Passing a
        // non-null `onOpen` adds an `await` to `sqflite_common`'s open
        // sequence, and in `flutter_test`'s fake-async zone that reorders the
        // open against a previous test's still-pending `close()`, which share
        // a path-keyed lock; LintCrux Pro's alerts-banner widget tests
        // deadlocked on the sixth `:memory:` open. Not a bug in this package,
        // but not one worth handing to every consumer either.
        //
        // What we give up is the window between the last migration returning
        // and sqflite's own `setVersion` committing. A failure there rolls the
        // upgrade back with one older backup already pruned — and still leaves
        // `keep` snapshots on disk, including the one taken moments ago. The
        // database is untouched at its old version throughout. That is a
        // strictly smaller cost than the deadlock.
        if (backupPath != null) backup.pruneAfterSuccessfulUpgrade(path);
      },
      // Never omitted. Omitting `onDowngrade` does not give you a throw — it
      // gives you silence: sqflite skips the version callbacks and calls
      // `setVersion` anyway, stamping `user_version` DOWN. The next new-build
      // launch then re-runs a migration against a schema that already has it,
      // permanently, with no recovery path. A missing `onDowngrade` is a live
      // fuse, not a missing nicety.
      //
      // The refusal names a backup when one is on disk. A downgrading user
      // cannot open a newer file and never will — but the snapshot taken the
      // instant before the upgrade that produced it is one this build reads
      // perfectly, and it is sitting in the same directory.
      //
      // It also names the BUILD, not only the number. `schema_meta` is read
      // off the file before the throw — the refusal is the one moment the
      // ledger has to earn its place, because "v4 versus v3" is a fact the
      // user cannot act on and "written by version 0.9.0" is the name of the
      // thing they have to go and launch. Reading is quiet by design: a
      // diagnostic lookup that threw here would replace a precise refusal with
      // whatever went wrong while decorating it.
      onDowngrade: (db, oldVersion, newVersion) async {
        final meta = await readCruxSchemaMetaQuietly(db);
        throw CruxSchemaVersionSkewException(
          storeName: runner.storeName,
          path: path,
          fileVersion: oldVersion,
          appVersion: newVersion,
          fileAppVersion: meta?.appVersion,
          backupPath: recovery.isPrecious
              ? CruxPreUpgradeBackup.latestBackupFor(path)
              : null,
        );
      },
    );
  }

  /// Opens (or creates) the database at [path], applying [recovery] if — and
  /// only if — the bytes on disk turn out not to be a SQLite database.
  ///
  /// [path] is absolutised against the working directory before anything
  /// touches it, so a relative `--db` argument names one file rather than
  /// three. Pass `inMemoryDatabasePath` (sqflite's `:memory:`) for a throwaway
  /// database; no recovery path can apply to one, so corruption there
  /// propagates untouched.
  ///
  /// [factory] defaults to the global `databaseFactory`; call
  /// [ensureCruxSqliteFfiInitialized] once at startup, or pass a factory
  /// explicitly.
  ///
  /// Three faults, three outcomes:
  ///
  /// * **A migration failure** propagates as [CruxMigrationFailedException].
  ///   Our bug; the file is already rolled back with all of its data, and no
  ///   recovery path may touch it.
  /// * **A version skew** propagates as [CruxSchemaVersionSkewException]. An
  ///   older build refuses a newer file; it never wipes one to make itself able
  ///   to open it.
  /// * **Genuine corruption** is handled per [recovery] — and nothing else is.
  ///   `SQLITE_BUSY`, `SQLITE_LOCKED`, `SQLITE_READONLY` and `SQLITE_CANTOPEN`
  ///   describe a file that is fine and propagate untouched.
  Future<Database> open(String path, {DatabaseFactory? factory}) async {
    final resolved = factory ?? databaseFactory;
    final isInMemory = path == inMemoryDatabasePath;
    // Absolutised ONCE, and then used for everything: the open, the
    // quarantine, the delete, and every path this package reports.
    //
    // Not cosmetic. A relative path means three different files to three
    // different pieces of machinery — `sqflite_common_ffi` resolves it against
    // its own databases directory under `.dart_tool/`, `dart:io` resolves it
    // against the process working directory, and the user meant the one they
    // typed. A quarantine that renames a different file than the one that
    // failed to open is a data-loss bug wearing a path bug's clothes.
    //
    // Symlinks are deliberately left unresolved: this names the file the user
    // asked for, not its target.
    final dbPath = isInMemory
        ? path
        : canonicalizePath(path, resolveSymlinks: false);

    // Set at the top of onCreate/onUpgrade, read in the catch below. Once a
    // migration has begun, any failure is OUR failure and not the file's, and
    // no recovery path may touch the file. The runner's typed failures cover
    // most of that; this covers what the runner never sees, including sqflite's
    // own `setVersion` inside the same transaction.
    var migrationAttempted = false;
    OpenDatabaseOptions options() => buildOptions(
      path: dbPath,
      onMigrationStart: () => migrationAttempted = true,
    );

    try {
      return await resolved.openDatabase(dbPath, options: options());
    } on DatabaseException catch (error, stackTrace) {
      if (migrationAttempted || isInMemory || !isSqliteCorruption(error)) {
        rethrow;
      }

      // Exhaustive over the enum, so adding a fourth data-value policy is a
      // compile error here rather than a silently unhandled case.
      final String? quarantinedPath;
      switch (recovery) {
        case CruxDbRecovery.refuse:
          throw CruxDatabaseCorruptionException(
            storeName: runner.storeName,
            path: dbPath,
            recovery: recovery,
            quarantinedPath: null,
            cause: error,
            stackTrace: stackTrace,
          );
        case CruxDbRecovery.renameAside:
          quarantinedPath = quarantineDatabaseFile(dbPath);
        case CruxDbRecovery.recreate:
          // The one sanctioned delete in this package, reachable only from a
          // store that declared its contents DERIVABLE at the call site.
          await resolved.deleteDatabase(dbPath);
          quarantinedPath = null;
      }

      // Told BEFORE the reopen, deliberately. What happened to the file is
      // true whether or not a fresh database then opens successfully, and a
      // reopen that fails on a full disk must not also swallow the news that
      // the user's database was moved aside.
      onRecovery!(
        CruxDatabaseCorruptionException(
          storeName: runner.storeName,
          path: dbPath,
          recovery: recovery,
          quarantinedPath: quarantinedPath,
          cause: error,
          stackTrace: stackTrace,
        ),
      );

      // The same options closure as the first attempt — not a second, similar
      // one. A hand-rolled retry is how `onDowngrade` came to be dropped from a
      // reopened database, leaving it silently able to be stamped backwards.
      migrationAttempted = false;
      return await resolved.openDatabase(dbPath, options: options());
    }
  }
}
