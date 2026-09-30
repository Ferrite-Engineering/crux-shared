// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_schema_meta.dart';
import 'package:crux_sqlite/src/crux_sqlite_exceptions.dart';
import 'package:meta/meta.dart';
import 'package:sqflite_common/sqflite.dart';

/// The body of one migration: everything version N−1 → N does to the schema.
///
/// Runs inside sqflite's exclusive version transaction, so it is atomic — a
/// migration that throws leaves the file exactly as it was, at its old
/// version, with all of its data. That is what makes
/// [CruxMigrationFailedException] a bug report rather than a recovery case.
typedef CruxMigrationStep = Future<void> Function(Database db);

/// One version-numbered, append-only up-migration.
///
/// **Append-only and additive-only** are the two rules that make a list of
/// these safe (README, "The migration rules"):
///
/// * A migration that has shipped is **frozen**. You add version N+1; you
///   never edit N. Every user's file is the product of the exact sequence that
///   shipped, so editing N changes what a fresh install gets while leaving
///   existing installs on the old shape — and the two diverge silently.
/// * New tables, new indexes, `ADD COLUMN` with a default, backfill `UPDATE`s.
///   No `DROP`, no `RENAME`, no destructive `DELETE`. A dropped column is a
///   column whose data no longer exists, the loss is invisible in review, and
///   the user finds out months later.
@immutable
final class CruxMigration {
  /// Creates a [CruxMigration].
  const CruxMigration({
    required this.version,
    required this.description,
    required this.apply,
  });

  /// The schema version this migration **produces**. 1-based and contiguous:
  /// the first entry in a list is v1, and it is the entry's position, not a
  /// number anyone maintains.
  final int version;

  /// What this migration does and why, in one sentence a support conversation
  /// can use.
  ///
  /// Not a comment. It is the human-readable half of the migration ledger and
  /// of every failure message this package raises, which is why an empty one
  /// is rejected by [CruxMigrationRunner]'s constructor rather than tolerated.
  final String description;

  /// The schema change itself.
  final CruxMigrationStep apply;

  @override
  String toString() => 'CruxMigration(v$version: $description)';
}

/// Owns one store's migration list and is the only thing that runs it.
///
/// **The latest version is derived, never declared.** There is no version
/// constant to bump, by design: a constant someone forgets to bump is a
/// migration that silently never runs, which is exactly what the audit found
/// in three LintCrux stores. [latestVersion] is `migrations.length`, so
/// appending an entry *is* the version bump.
///
/// Ported from SimCrux's `SqlMigrations`, which was the one of the four stores
/// already shaped correctly. The two things it adds are the contiguity check
/// and the typed failures.
final class CruxMigrationRunner {
  /// Creates a runner over [migrations], rejecting a list that cannot be a
  /// valid migration history.
  ///
  /// Throws [ArgumentError] — **not** an `assert`, because an incoherent
  /// migration list must fail in a release build too, at the first open,
  /// rather than half-migrating a user's file in the field — when the list is
  /// empty, when its versions are not contiguous from 1, or when a description
  /// is blank.
  CruxMigrationRunner({
    required this.storeName,
    required List<CruxMigration> migrations,
    required this.identity,
    DateTime Function()? now,
  }) : migrations = List<CruxMigration>.unmodifiable(migrations),
       _now = now ?? DateTime.now {
    _validate(storeName, this.migrations);
  }

  /// The store's name, as it should appear in an error a user reads — "LintCrux
  /// trend store", not `SqliteViolationTrendStore`.
  final String storeName;

  /// Which build is writing to this store, stamped into `schema_meta` and the
  /// `schema_migrations` ledger.
  ///
  /// **Required, with no default.** A defaulted identity is the F5 failure
  /// mode with better manners: every store would compile, every file would say
  /// `unknown`, and the one thing the ledger exists to answer — *which build
  /// wrote this?* — would be permanently unanswerable in a way nobody noticed.
  /// A store that genuinely has no version passes [CruxAppIdentity.unknown]
  /// and has said so out loud.
  final CruxAppIdentity identity;

  final DateTime Function() _now;

  /// The migrations, in order, frozen. Index `i` holds version `i + 1`.
  final List<CruxMigration> migrations;

  /// The schema version this build produces, **derived** from the list.
  ///
  /// This is the value that goes into `OpenDatabaseOptions.version`, and the
  /// open policy is what puts it there — a store never passes a version of its
  /// own.
  int get latestVersion => migrations.length;

  /// The migration producing [version].
  ///
  /// Throws [RangeError] for a version outside `1..latestVersion`.
  CruxMigration migrationFor(int version) {
    if (version < 1 || version > latestVersion) {
      throw RangeError.range(version, 1, latestVersion, 'version');
    }
    return migrations[version - 1];
  }

  /// Runs every migration in `(oldVersion, newVersion]`, in order.
  ///
  /// Shaped to be passed straight to `OpenDatabaseOptions.onUpgrade`, and
  /// called with `oldVersion: 0` for `onCreate` — routing a fresh install
  /// through the same code as an upgraded one is what makes the two converge
  /// on the same schema, and it is the single most important property of this
  /// method. Both products already did this correctly; it is preserved
  /// deliberately.
  ///
  /// Throws:
  ///
  /// * [CruxSchemaVersionSkewException] when [oldVersion] exceeds
  ///   [newVersion]. Forward-only, always, loudly. This is a second line of
  ///   defence behind the open policy's `onDowngrade`, which normally catches
  ///   the skew first.
  /// * [CruxMigrationFailedException] when a migration body throws, naming the
  ///   version that failed. The transaction rolls back; the file is untouched.
  /// * [ArgumentError] when [newVersion] exceeds [latestVersion], which can
  ///   only be a caller bug — nothing in this package can ask for a version it
  ///   has no migration for.
  ///
  /// [reportPath] overrides the path named in those errors. The open policy
  /// passes the absolutised path it resolved; the default is `db.path`, which
  /// is whatever string the database was opened with.
  ///
  /// [backupPath] is the pre-upgrade backup the open policy has just written
  /// for a PRECIOUS store, and it is threaded through so that
  /// [CruxMigrationFailedException] can name it by absolute path. A migration
  /// failure is the one moment that file matters most and the one moment
  /// nobody is going to go looking for it.
  Future<void> upgrade(
    Database db,
    int oldVersion,
    int newVersion, {
    String? reportPath,
    String? backupPath,
  }) async {
    final path = reportPath ?? db.path;
    if (oldVersion > newVersion) {
      throw CruxSchemaVersionSkewException(
        storeName: storeName,
        path: path,
        fileVersion: oldVersion,
        appVersion: newVersion,
        // Read from the file itself, not from `identity` — the point is to
        // name the build that got ahead of this one, which by definition is
        // not this one.
        fileAppVersion: (await readCruxSchemaMetaQuietly(db))?.appVersion,
        backupPath: backupPath,
      );
    }
    if (newVersion > latestVersion) {
      throw ArgumentError.value(
        newVersion,
        'newVersion',
        'the $storeName has no migration for v$newVersion — its list stops at '
            'v$latestVersion',
      );
    }
    for (final migration in migrations) {
      if (migration.version <= oldVersion || migration.version > newVersion) {
        continue;
      }
      try {
        await migration.apply(db);
      } on Object catch (error, stackTrace) {
        throw CruxMigrationFailedException(
          storeName: storeName,
          path: path,
          version: migration.version,
          description: migration.description,
          fromVersion: oldVersion,
          toVersion: newVersion,
          cause: error,
          backupPath: backupPath,
          stackTrace: stackTrace,
        );
      }
    }

    // The ledger, written HERE and only here.
    //
    // Still inside sqflite's exclusive version transaction, so it commits with
    // the schema it describes or not at all. That is the property that makes a
    // ledger worth reading: a migration that throws never reaches this line,
    // and one that throws *after* an earlier migration in the same range
    // succeeded takes the whole transaction down, including any row already
    // written. There is no state in which `schema_migrations` claims a version
    // the schema does not have.
    //
    // After the loop rather than inside it because the ledger tables may not
    // exist until one of these very migrations creates them — a store adopting
    // `cruxSchemaMetaMigration` at vN has no `schema_migrations` to write
    // v1..N−1 into until vN has run. Doing it once, at the end, is also what
    // lets an existing install have its pre-ledger history backfilled in the
    // same pass.
    await writeCruxSchemaMetaForUpgrade(
      db,
      identity: identity,
      migrations: migrations,
      oldVersion: oldVersion,
      newVersion: newVersion,
      now: _now(),
    );
  }

  static void _validate(String storeName, List<CruxMigration> migrations) {
    if (storeName.trim().isEmpty) {
      throw ArgumentError.value(
        storeName,
        'storeName',
        'a store needs a name a user can read — it appears in every failure '
            'this package raises',
      );
    }
    if (migrations.isEmpty) {
      throw ArgumentError.value(
        migrations,
        'migrations',
        'a store needs at least one migration. An empty list derives '
            'latestVersion 0, which sqflite reads as "no version", so onCreate '
            'never runs and the store opens with no schema at all',
      );
    }
    for (var i = 0; i < migrations.length; i++) {
      final expected = i + 1;
      final actual = migrations[i].version;
      if (actual != expected) {
        throw ArgumentError.value(
          migrations,
          'migrations',
          "the $storeName's migrations must be contiguous from 1: entry $i "
              'declares v$actual where v$expected was expected. The latest '
              'version is derived from this list, so a gap or a duplicate '
              'means some file somewhere never gets migrated',
        );
      }
      if (migrations[i].description.trim().isEmpty) {
        throw ArgumentError.value(
          migrations,
          'migrations',
          "the $storeName's v$expected migration has a blank description. It "
              'is read back in diagnostics and printed in failure messages, so '
              'it is not optional',
        );
      }
    }
  }
}
