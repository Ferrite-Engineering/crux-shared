// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:meta/meta.dart';
import 'package:sqflite_common/sqflite.dart';

/// Name of the single-row table describing the file as a whole.
const String kCruxSchemaMetaTable = 'schema_meta';

/// Name of the append-only ledger of migrations this file has executed.
const String kCruxSchemaMigrationsTable = 'schema_migrations';

/// The `schema_meta` table, **frozen**.
///
/// This text is part of every store's shipped migration, so editing it edits
/// four migrations that have already run on users' disks — the one thing rule
/// 1 forbids. A change to the shape is a *second* factory
/// (`cruxSchemaMetaMigrationV2`) appended after this one, never an edit here.
/// `schema_meta_shape_is_frozen_test.dart` pins the exact `sqlite_master`
/// text and is the thing that will notice.
///
/// **Nullable means unknown, and it means it uniformly.** Four of the seven
/// columns can be NULL, and NULL always says the same thing: this file cannot
/// know that value. An existing install adopting the ledger has no record of
/// when it was created or which build ran its earlier migrations, and the
/// alternative to NULL is inventing a plausible answer — a creation time of
/// "now" that is years wrong, or an app version of "this one" that never
/// touched those migrations. A diagnostics surface can render "unknown"; it
/// cannot un-invent a lie.
///
/// `id INTEGER PRIMARY KEY CHECK (id = 1)` is what makes it single-row: a
/// second row is a constraint failure rather than a silent second opinion
/// about what version the file is at.
const String kCruxSchemaMetaDdl =
    '''
CREATE TABLE IF NOT EXISTS $kCruxSchemaMetaTable (
  id                         INTEGER PRIMARY KEY CHECK (id = 1),
  schema_version             INTEGER NOT NULL,
  product                    TEXT    NOT NULL,
  app_version                TEXT,
  created_at                 TEXT,
  last_migrated_at           TEXT,
  last_opened_by_app_version TEXT
)''';

/// The `schema_migrations` ledger, **frozen**. See [kCruxSchemaMetaDdl].
///
/// One row per migration this file has executed, keyed by version. A row with
/// a NULL `applied_at` ran before the file kept a ledger — it is knowable
/// *that* it ran, because the file is at a version that required it, and not
/// knowable when or by whom.
const String kCruxSchemaMigrationsDdl =
    '''
CREATE TABLE IF NOT EXISTS $kCruxSchemaMigrationsTable (
  version                INTEGER PRIMARY KEY,
  description            TEXT NOT NULL,
  applied_at             TEXT,
  applied_by_app_version TEXT
)''';

/// The description carried by [cruxSchemaMetaMigration], **frozen** — it is
/// written into the ledger row for the migration that creates the ledger.
const String kCruxSchemaMetaMigrationDescription =
    'Add schema_meta and the schema_migrations ledger — the shared shape '
    'every Crux SQLite database carries, so a version refusal can name the '
    'build that wrote the file and diagnostics can read its history';

/// Which build is writing to a Crux SQLite database.
///
/// **This package deliberately cannot source a version.** It is pure Dart,
/// permanently, so `PackageInfo.fromPlatform()` is not available to it — and
/// would be the wrong answer even if it were, because it is asynchronous and
/// absent from the headless CLIs that write two of these files. So the
/// identity is a parameter: the product supplies it at the one site where it
/// builds its [CruxMigrationRunner], from a compile-time constant of its own,
/// and this package's only job is to make forgetting impossible (the
/// constructor parameter is required) and to make "we do not know" expressible
/// ([unknown]) rather than guessed.
@immutable
final class CruxAppIdentity {
  /// Creates a [CruxAppIdentity].
  ///
  /// [product] is the stable lowercase identifier the suite already uses on
  /// the wire — `'wavecrux'`, `'netcrux'`, `'lintcrux'`, `'simcrux'` — not a
  /// display name, because it is read by machines (today a diagnostics
  /// surface and a shared team database's handshake).
  ///
  /// [appVersion] is the semantic version without a build number, or `null`
  /// when the caller genuinely cannot name it. `null` is written as SQL NULL
  /// and reads back as unknown; it is never rendered as a version.
  ///
  /// Throws [ArgumentError] on a blank [product] or a blank-but-non-null
  /// [appVersion]: an empty string in either column is a value that looks
  /// present and means nothing.
  CruxAppIdentity({required this.product, required this.appVersion}) {
    if (product.trim().isEmpty) {
      throw ArgumentError.value(
        product,
        'product',
        'schema_meta.product is NOT NULL and is read by machines. Pass the '
            "stable lowercase identifier ('simcrux', 'lintcrux'), or "
            'CruxAppIdentity.unknown if this really is an anonymous opener',
      );
    }
    if (appVersion != null && appVersion!.trim().isEmpty) {
      throw ArgumentError.value(
        appVersion,
        'appVersion',
        'an empty app version looks present and means nothing. Pass null, '
            'which is stored as SQL NULL and reads back as unknown',
      );
    }
  }

  /// An opener that cannot name itself.
  ///
  /// Not a default anywhere — [CruxMigrationRunner] requires an identity
  /// precisely so that this has to be chosen. It exists for throwaway
  /// in-memory databases and for tooling that legitimately has no version.
  static final CruxAppIdentity unknown = CruxAppIdentity(
    product: 'unknown',
    appVersion: null,
  );

  /// Stable lowercase product identifier.
  final String product;

  /// Semantic version of the running build, or `null` when unknown.
  final String? appVersion;

  @override
  String toString() => 'CruxAppIdentity($product ${appVersion ?? 'unknown'})';
}

/// The migration that adds [kCruxSchemaMetaTable] and
/// [kCruxSchemaMigrationsTable] to a store, at [version].
///
/// **Appended to a store's migration list like any other migration**, which is
/// what makes it arrive on existing installs at all — and what makes its
/// arrival visible as a version bump rather than a table that silently appears.
/// It is pure DDL: the rows are written by [CruxMigrationRunner.upgrade]
/// immediately afterwards, inside the same transaction, because they need the
/// identity and the full migration list and this factory has neither.
///
/// Additive-only by construction: two `CREATE TABLE IF NOT EXISTS`, nothing
/// touched, nothing dropped.
CruxMigration cruxSchemaMetaMigration({required int version}) {
  return CruxMigration(
    version: version,
    description: kCruxSchemaMetaMigrationDescription,
    apply: (db) async {
      await db.execute(kCruxSchemaMetaDdl);
      await db.execute(kCruxSchemaMigrationsDdl);
    },
  );
}

/// One row of [kCruxSchemaMigrationsTable].
@immutable
final class CruxAppliedMigration {
  /// Creates a [CruxAppliedMigration].
  const CruxAppliedMigration({
    required this.version,
    required this.description,
    required this.appliedAt,
    required this.appliedByAppVersion,
  });

  /// The schema version this migration produced.
  final int version;

  /// The migration's own description, as it was when it ran.
  final String description;

  /// When it ran, or `null` when it predates the ledger.
  final DateTime? appliedAt;

  /// The build that ran it, or `null` when it predates the ledger.
  final String? appliedByAppVersion;

  /// Whether this row was backfilled — it records a migration that certainly
  /// ran, at a time and by a build the file never recorded.
  bool get isBackfilled => appliedAt == null && appliedByAppVersion == null;

  @override
  String toString() =>
      'CruxAppliedMigration(v$version, ${appliedAt ?? 'unknown'}, '
      '${appliedByAppVersion ?? 'unknown'})';
}

/// The single row of [kCruxSchemaMetaTable].
@immutable
final class CruxSchemaMetaRow {
  /// Creates a [CruxSchemaMetaRow].
  const CruxSchemaMetaRow({
    required this.schemaVersion,
    required this.product,
    required this.appVersion,
    required this.createdAt,
    required this.lastMigratedAt,
    required this.lastOpenedByAppVersion,
  });

  /// The schema version the file was left at by the last migration.
  ///
  /// Redundant with `PRAGMA user_version` and deliberately so: `user_version`
  /// is a bare integer any tool can stamp, this one was written by the code
  /// that actually ran the migrations, and a disagreement between them is
  /// information.
  final int schemaVersion;

  /// The product that owns the file.
  final String product;

  /// The build that last migrated it, or `null` when that build could not name
  /// itself.
  final String? appVersion;

  /// When the file was created, or `null` when it predates the ledger.
  final DateTime? createdAt;

  /// When it was last migrated, or `null` when unknown.
  final DateTime? lastMigratedAt;

  /// The build that opened it most recently, or `null` when unknown.
  final String? lastOpenedByAppVersion;

  @override
  String toString() =>
      'CruxSchemaMetaRow(v$schemaVersion, $product, '
      '${appVersion ?? 'unknown'})';
}

/// What a file says about itself: [kCruxSchemaMetaTable] plus the tail of
/// [kCruxSchemaMigrationsTable].
@immutable
final class CruxSchemaHistory {
  /// Creates a [CruxSchemaHistory].
  const CruxSchemaHistory({required this.meta, required this.ledger});

  /// A file that carries no `schema_meta` at all.
  ///
  /// **Not an error and not an empty database.** It is what a pre-ledger file
  /// looks like to a build that already knows about the ledger, which is every
  /// file in the field on the day the ledger ships and, during a staggered
  /// rollout, for as long as one machine has not launched the new build. A
  /// reader that treats absence as a failure would be broken for exactly the
  /// population it was written to help.
  static const CruxSchemaHistory absent = CruxSchemaHistory(
    meta: null,
    ledger: <CruxAppliedMigration>[],
  );

  /// The file's own description of itself, or `null` when it has none.
  final CruxSchemaMetaRow? meta;

  /// Ledger rows, **newest version first**.
  final List<CruxAppliedMigration> ledger;

  /// Whether this file records anything at all.
  bool get isPresent => meta != null;

  @override
  String toString() =>
      'CruxSchemaHistory(${meta ?? 'absent'}, ${ledger.length} ledger rows)';
}

/// Reads [kCruxSchemaMetaTable] and the newest [ledgerLimit] ledger rows.
///
/// Returns [CruxSchemaHistory.absent] when the tables are not there. Pass a
/// negative [ledgerLimit] for the whole ledger.
///
/// Never throws for a file that simply predates the ledger — that is the
/// entire contract. It will still propagate a genuine `DatabaseException`
/// from a broken file, because swallowing that would be a diagnostics surface
/// quietly reporting "no history" about a database that is on fire.
Future<CruxSchemaHistory> readCruxSchemaHistory(
  Database db, {
  int ledgerLimit = 5,
}) async {
  if (!await cruxSchemaMetaTablesExist(db)) return CruxSchemaHistory.absent;

  final metaRows = await db.rawQuery(
    'SELECT schema_version, product, app_version, created_at, '
    'last_migrated_at, last_opened_by_app_version '
    'FROM $kCruxSchemaMetaTable WHERE id = 1',
  );
  if (metaRows.isEmpty) return CruxSchemaHistory.absent;
  final row = metaRows.first;

  final limit = ledgerLimit < 0 ? '' : ' LIMIT $ledgerLimit';
  final ledgerRows = await db.rawQuery(
    'SELECT version, description, applied_at, applied_by_app_version '
    'FROM $kCruxSchemaMigrationsTable ORDER BY version DESC$limit',
  );

  return CruxSchemaHistory(
    meta: CruxSchemaMetaRow(
      schemaVersion: row['schema_version']! as int,
      product: row['product']! as String,
      appVersion: row['app_version'] as String?,
      createdAt: _parseTimestamp(row['created_at'] as String?),
      lastMigratedAt: _parseTimestamp(row['last_migrated_at'] as String?),
      lastOpenedByAppVersion: row['last_opened_by_app_version'] as String?,
    ),
    ledger: <CruxAppliedMigration>[
      for (final r in ledgerRows)
        CruxAppliedMigration(
          version: r['version']! as int,
          description: r['description']! as String,
          appliedAt: _parseTimestamp(r['applied_at'] as String?),
          appliedByAppVersion: r['applied_by_app_version'] as String?,
        ),
    ],
  );
}

/// Reads just the [kCruxSchemaMetaTable] row, tolerating **everything**.
///
/// Returns `null` on absence, on an empty table, and on any error at all —
/// unlike [readCruxSchemaHistory], which lets a genuine fault through. The
/// difference is the caller: this one exists to enrich an error message that
/// is already being raised (a downgrade refusal naming the build that wrote
/// the file), and a diagnostic read that throws there would replace a precise,
/// actionable refusal with whatever went wrong while decorating it.
Future<CruxSchemaMetaRow?> readCruxSchemaMetaQuietly(Database db) async {
  try {
    final history = await readCruxSchemaHistory(db, ledgerLimit: 0);
    return history.meta;
  } on Object catch (_) {
    return null;
  }
}

/// Whether both ledger tables exist in [db].
///
/// The absence check every read and every write goes through, so "tolerates a
/// pre-ledger file" is one implementation rather than five remembered ones.
Future<bool> cruxSchemaMetaTablesExist(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?)",
    <Object?>[kCruxSchemaMetaTable, kCruxSchemaMigrationsTable],
  );
  return rows.length == 2;
}

/// Writes the ledger and the `schema_meta` row for an upgrade that has just
/// run, **from inside the migration's own transaction**.
///
/// Called by [CruxMigrationRunner.upgrade] after the last migration in the
/// range returns and before it hands control back to sqflite — so it is inside
/// the exclusive version transaction, and a migration that throws takes its
/// ledger row down with it. That ordering is the whole reason the ledger is
/// worth having: **a ledger that can disagree with the schema is worse than no
/// ledger**, because it is believed.
///
/// Silently returns when the tables are not there, which is the case for a
/// store that has not appended [cruxSchemaMetaMigration] yet.
///
/// What an existing install gets, and what it deliberately does not:
///
/// * Versions at or below [oldVersion] are ledgered with NULL `applied_at` and
///   NULL `applied_by_app_version`. They certainly ran — the file is at
///   [oldVersion], which required them — and nothing on disk records when or
///   by which build. `INSERT OR IGNORE`, so a file that already ledgered them
///   properly keeps its real values.
/// * Versions in `(oldVersion, newVersion]` are ledgered with [now] and the
///   running build. Those we watched.
/// * `created_at` is [now] only when [oldVersion] is 0, i.e. this really is a
///   fresh file. On an upgrade it stays NULL forever: the file's real creation
///   date is not knowable, and "the day it adopted the ledger" is a different
///   fact wearing the same column's name.
Future<void> writeCruxSchemaMetaForUpgrade(
  Database db, {
  required CruxAppIdentity identity,
  required List<CruxMigration> migrations,
  required int oldVersion,
  required int newVersion,
  required DateTime now,
}) async {
  if (!await cruxSchemaMetaTablesExist(db)) return;
  final at = formatCruxSchemaTimestamp(now);

  for (final migration in migrations) {
    if (migration.version > newVersion) break;
    if (migration.version <= oldVersion) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO $kCruxSchemaMigrationsTable '
        '(version, description, applied_at, applied_by_app_version) '
        'VALUES (?, ?, NULL, NULL)',
        <Object?>[migration.version, migration.description],
      );
    } else {
      await db.rawInsert(
        'INSERT OR REPLACE INTO $kCruxSchemaMigrationsTable '
        '(version, description, applied_at, applied_by_app_version) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[
          migration.version,
          migration.description,
          at,
          identity.appVersion,
        ],
      );
    }
  }

  final existing = await db.rawQuery(
    'SELECT id FROM $kCruxSchemaMetaTable WHERE id = 1',
  );
  if (existing.isEmpty) {
    // NULL on an upgrade: an existing file's real creation date is not
    // knowable, and "the day it adopted the ledger" is a different fact
    // wearing this column's name.
    final createdAt = oldVersion == 0 ? at : null;
    await db.rawInsert(
      'INSERT INTO $kCruxSchemaMetaTable (id, schema_version, product, '
      'app_version, created_at, last_migrated_at, last_opened_by_app_version) '
      'VALUES (1, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        newVersion,
        identity.product,
        identity.appVersion,
        createdAt,
        at,
        identity.appVersion,
      ],
    );
  } else {
    await db.rawUpdate(
      'UPDATE $kCruxSchemaMetaTable SET schema_version = ?, product = ?, '
      'app_version = ?, last_migrated_at = ?, last_opened_by_app_version = ? '
      'WHERE id = 1',
      <Object?>[
        newVersion,
        identity.product,
        identity.appVersion,
        at,
        identity.appVersion,
      ],
    );
  }
}

/// Records that [identity] opened a file that needed no migration.
///
/// **Runs from `onConfigure`, which is why it does not deadlock.** The
/// textbook hook for "after the database is open" is `onOpen`, and it is
/// unusable here: passing a non-null `onOpen` adds an `await` to
/// `sqflite_common`'s open sequence, and under `flutter_test`'s fake-async
/// zone that reorders the open against a previous test's still-pending
/// `close()` on the shared path-keyed lock — six LintCrux Pro widget tests
/// deadlocked on it. `onConfigure` is already non-null on every Crux open (it
/// sets `busy_timeout`), so this adds no `await` that was not already there.
///
/// **It writes only when the file is already at [latestVersion]**, and that
/// restriction is doing real work rather than saving a write:
///
/// * Below it, a migration is about to run and will set the same column inside
///   its transaction. Writing here as well would put a write *outside* that
///   transaction, so a migration that then failed would leave the file
///   modified — contradicting, by one column, the promise
///   `CruxMigrationFailedException` and `CruxBackupFailedException` both make
///   that the file is exactly as it was.
/// * Above it the file is from the future and is about to be refused.
///   "Nothing has been modified" has to be true of the refusal too, including
///   of a build old enough not to understand what it is looking at.
///
/// So every open stamps exactly once: here, or inside the migration.
Future<void> writeCruxSchemaMetaForOpen(
  Database db, {
  required CruxAppIdentity identity,
  required int latestVersion,
}) async {
  final fileVersion = await readCruxUserVersion(db);
  if (fileVersion != latestVersion) return;
  if (!await cruxSchemaMetaTablesExist(db)) return;
  await db.rawUpdate(
    'UPDATE $kCruxSchemaMetaTable SET last_opened_by_app_version = ? '
    'WHERE id = 1',
    <Object?>[identity.appVersion],
  );
}

/// Reads `PRAGMA user_version`, the schema version sqflite itself stamps.
///
/// 0 for a file that has never been migrated, which is also what a
/// brand-new empty file reports.
Future<int> readCruxUserVersion(Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  if (rows.isEmpty) return 0;
  final value = rows.first.values.first;
  return value is int ? value : 0;
}

/// Formats [when] for a `schema_meta` or `schema_migrations` timestamp column.
///
/// **ISO 8601 extended form, UTC, exactly three fractional digits** —
/// `2026-08-20T09:14:32.512Z`. Deliberately *not* the basic form the backup and
/// quarantine filenames use: that one is basic because a colon is illegal in a
/// Windows filename and LintCrux ships on Windows, a constraint a column value
/// does not have. What a column wants instead is to sort lexicographically in
/// the same order it sorts chronologically, to be readable in a `sqlite3` shell
/// during a support call, and to round-trip through `DateTime.parse` without a
/// custom reader. Extended form is the only one of the two that gives all
/// three.
///
/// **The truncation to milliseconds is the load-bearing part, not a detail.**
/// `toIso8601String()` alone widens the fraction to six digits the moment the
/// microsecond component is non-zero, which is nearly every real
/// `DateTime.now()` — so a column filled by it carries mixed three- and
/// six-digit fractions, and mixed widths do not sort as text: `.512Z` sorts
/// *after* `.512001Z`. That sort is the entire reason the extended form was
/// chosen over the basic one, so the claim has to be made true rather than
/// merely written down. Truncation, not rounding: the stamp never names an
/// instant that had not happened yet.
///
/// Two writes inside the same millisecond therefore produce the same stamp.
/// That is fine here and would not be fine everywhere: these columns answer
/// "roughly when did this run" for a support conversation, and the ledger is
/// keyed by `version`, never by time. (The one remaining way the width can
/// move is a clock outside years 0001–9999, where `toIso8601String()` switches
/// to a signed six-digit year. A machine that far off is not producing a
/// timestamp worth sorting.)
///
/// **Rows written before this truncation landed keep their six-digit
/// fractions, deliberately.** Rewriting them would mean a migration that edits
/// historical ledger rows — destructive-ish, waiver-requiring, and pointless:
/// [_parseTimestamp] goes through `DateTime.parse`, which accepts both widths,
/// so every such row still reads back exactly. Nothing in the suite sorts these
/// columns as text (`readCruxSchemaHistory` orders by `version`), and the
/// ledger shipped in no release before the fix. The invariant is "every stamp
/// this function writes is fixed-width", which is the one a shared team
/// database can port.
///
/// Always UTC. A local-time column is a column that lies when the user
/// travels.
String formatCruxSchemaTimestamp(DateTime when) {
  final utc = when.toUtc();
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  ).toIso8601String();
}

DateTime? _parseTimestamp(String? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
