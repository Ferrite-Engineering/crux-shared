// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The one SQLite open path in the EDACrux suite.
///
/// A store supplies three things — a migration list, a data-value declaration,
/// and a path — and this package supplies everything else: the version, the
/// upgrade loop, `onCreate` and `onUpgrade` routed through the same code, an
/// `onDowngrade` that refuses, the mandatory `busy_timeout`, a `VACUUM INTO`
/// backup taken before any upgrade of a PRECIOUS file, and four
/// distinguishable typed failures where there used to be one anonymous
/// exception.
///
/// ```dart
/// final runner = CruxMigrationRunner(
///   storeName: 'LintCrux trend store',
///   identity: CruxAppIdentity(product: 'lintcrux', appVersion: '0.8.0'),
///   migrations: [
///     CruxMigration(
///       version: 1,
///       description: 'Create violation_trends and its time-axis indexes',
///       apply: (db) async => db.execute('CREATE TABLE ...'),
///     ),
///     cruxSchemaMetaMigration(version: 2),
///   ],
/// );
///
/// final policy = CruxSqliteOpenPolicy(
///   runner: runner,
///   recovery: CruxDbRecovery.renameAside, // PRECIOUS — never deleted
///   onRecovery: diagnostics.report,
/// );
///
/// final db = await policy.open(dbPath);
/// ```
///
/// That store now also gets a pre-upgrade backup, and there is no line in the
/// snippet above that asked for one. `renameAside` *means* PRECIOUS, so before
/// any upgrade the open path writes
/// `trends.db.pre-v<oldVersion>-<ISO 8601 basic UTC>.bak` with `VACUUM INTO`,
/// keeps the newest two once the upgrade lands, and refuses to migrate at all
/// if the backup could not be written. The one store in the suite that opts
/// out — `cache.db` — does so by declaring `CruxDbRecovery.recreate`, which is
/// the same declaration that already lets it be deleted.
///
/// The `cruxSchemaMetaMigration` line is the other thing worth pointing at.
/// **One shape across every Crux SQLite database** — a single-row
/// `schema_meta` and an append-only `schema_migrations` ledger, defined here
/// and written here, with no per-product variant to drift. Appending it to a
/// store's list is all a store does; the runner fills both tables from inside
/// the migration's own transaction, backfilling what an existing file's
/// history can support and leaving the rest NULL rather than inventing it.
/// That is what lets a downgrade refusal name the build that wrote the file
/// instead of only its schema number, and it is deliberately the same
/// handshake a shared team database needs — so that arrives as a port rather
/// than a second design.
///
/// **A new SQLite database anywhere in the suite opens through here** — in
/// WaveCrux and NetCrux too, neither of which has one today. If it cannot,
/// that is a bug in this package to be fixed, not a reason to hand-roll a
/// sixth open path. The rules it enforces are written down in this package's
/// README ("The migration rules"); this package is those rules made
/// executable.
///
/// Pure Dart, permanently. See `no_flutter_dependency_test.dart`.
library;

export 'src/crux_db_recovery.dart';
export 'src/crux_migration.dart';
export 'src/crux_open_policy.dart';
export 'src/crux_pre_upgrade_backup.dart';
export 'src/crux_schema_meta.dart';
export 'src/crux_sqlite_exceptions.dart';
export 'src/free_disk_space.dart';
export 'src/sqlite_corruption.dart';
