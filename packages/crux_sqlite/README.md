# crux_sqlite

The one SQLite open path in the EDACrux suite. Pure Dart, permanently.

A store supplies three things — a migration list, a data-value declaration, and
a path. This package supplies everything else.

```dart
final runner = CruxMigrationRunner(
  storeName: 'LintCrux trend store',
  migrations: [
    CruxMigration(
      version: 1,
      description: 'Create violation_trends and its time-axis indexes',
      apply: (db) async => db.execute('CREATE TABLE violation_trends (...)'),
    ),
  ],
);

final policy = CruxSqliteOpenPolicy(
  runner: runner,
  recovery: CruxDbRecovery.renameAside, // PRECIOUS — never deleted
  onRecovery: diagnostics.report,
);

final db = await policy.open(dbPath);
```

## Why the package exists

A 2026-08-18 audit of every `sqflite` open path in SimCrux and LintCrux found
four databases, two of them holding unreconstructible user data, and four
slightly different opinions about what an exception during an open means. One of
those opinions was:

```dart
try { await openDatabase(...); } on Object { await deleteDatabase(...); }
```

It was written for a corrupt file. It also covered the migration run and the
downgrade throw — so a bug in *our own* code and a version skew both arrived at
a handler written for damaged hardware. And because that store set no
`busy_timeout`, ordinary lock contention raised an exception too. A Pro user's
entire violation history was deleted because another process held a write lock.

Every rule this package enforces is a rule that had been written down somewhere
and forgotten somewhere else. **The rule that lives in prose is the rule that
drifts; the rule that lives in a function signature does not.**

## What it enforces

| | How |
|---|---|
| The latest schema version is **derived** | `CruxMigrationRunner.latestVersion` is `migrations.length`. There is no constant to bump and therefore none to forget. |
| A fresh install and an upgraded install **converge** | `onCreate` and `onUpgrade` are routed through the same upgrade loop, from 0. |
| Migrations are **contiguous from 1** | Checked in the runner's constructor, as a throw rather than an `assert`, so a release build fails at the first open instead of half-migrating a file in the field. |
| Downgrade is a **hard, loud error** | `onDowngrade` is never omitted. Omitting it does not give you a throw — it gives you silence, and sqflite stamps `user_version` *down*. |
| `busy_timeout` is **mandatory** | 5 s on every open, not a parameter. A busy database must never read as a corrupt one. |
| Precious data is **never deleted** | `CruxDbRecovery` is an argument at the call site, not a docstring. `renameAside` cannot delete; `recreate` exists for derivable data only. |
| A recovery is **never silent** | `renameAside` and `recreate` require a recovery listener. A store with nowhere to put a notice declares `refuse` — which destroys nothing. |
| A PRECIOUS file is **backed up before any upgrade** | `VACUUM INTO` from `onConfigure`, keyed off `CruxDbRecovery.isPrecious`. A store opts in by *being precious*, not by remembering to call anything. If the backup fails, the migration does not run. |
| The four faults stay **four types** | `CruxDatabaseCorruptionException`, `CruxMigrationFailedException`, `CruxSchemaVersionSkewException`, `CruxBackupFailedException`. |

## The pre-upgrade backup

Before any upgrade of a database whose `CruxDbRecovery` says it is PRECIOUS, the
open path writes

```
trends.db.pre-v<oldVersion>-<ISO 8601 basic UTC>.bak
```

with `VACUUM INTO` — e.g. `trends.db.pre-v2-20260820T090000Z.bak`. Basic form,
because a colon is illegal in a Windows filename and LintCrux ships on Windows.

Four properties, each of which is a decision:

- **`VACUUM INTO`, never a file copy.** The bytes of a SQLite file are not the
  database. With a hot rollback journal beside it — and there is one, because
  this suite deliberately did not adopt WAL — a copy taken against an open
  connection captures pages the journal was about to undo. It opens, it queries,
  and it is subtly wrong, which is worse than having no backup because it is
  *trusted*.
- **Precious means backed up.** There is no enable flag. `cache.db` is the one
  store that opts out, and it does so by declaring `CruxDbRecovery.recreate` —
  the same declaration that already lets it be deleted.
- **A failed backup aborts the migration.** Degrading to "back up if convenient,
  migrate regardless" would defeat the rule in exactly the cases it exists for.
  `CruxBackupFailedException` says which case it was and what to do about it,
  and nothing was written: sqflite reads `user_version` *after* `onConfigure`,
  so the upgrade transaction never opened.
- **Two are kept, and only after success.** Pruning runs in `onOpen`, which a
  failed migration never reaches — so a failure keeps every backup it has, and
  the error names the new one by absolute path.

A downgrading user is pointed at the same file: `CruxSchemaVersionSkewException`
names the newest `.pre-v<n>` backup when one exists, because the copy taken the
instant before the upgrade is a file the older build reads perfectly.

## Two decisions recorded here rather than left implicit

**WAL is not adopted.** `journal_mode` is per-file and persistent, so whoever
sets it decides for every future opener of that file. WAL does not work over a
network filesystem, and `push-trends --db` pointing at a team share is a
supported configuration; it would ship as a side effect of an open call rather
than as a reviewed migration; and the concurrency it buys is already covered by
`busy_timeout`. The full reasoning is on `CruxSqliteOpenPolicy`.

**Foreign-key enforcement stays off.** `PRAGMA foreign_keys` is a no-op inside a
transaction and sqflite runs every migration inside an exclusive one, so
enforcement would make the 12-step table rebuild impossible from inside this
shared open path.

## Three entry points

```dart
import 'package:crux_sqlite/crux_sqlite.dart';               // runtime
import 'package:crux_sqlite/crux_sqlite_test_support.dart';  // fixtures
import 'package:crux_sqlite/crux_sqlite_guards.dart';        // CI guards
```

The runtime barrel is what a store opens through, and it stays exactly that.
The two secondary barrels are test-only tooling, never exported from it and
never imported by a product's `lib/` — the same split, for the same reason, as
`crux_license_core.dart`. Each carries its own
`api/*.api.txt` golden, because a consumer can import it.

## The six CI guards

`crux_sqlite_guards.dart` holds the scanners; each product's `test/static/`
holds a thin test pointing them at that repo's own sources, migration lists and
manifests. **Not a workflow** — both Pro repos already run `flutter test` in CI,
so the guards ride an existing job: no new billing surface and no new
`timeout-minutes` for anybody to forget. Because the scanners are shared, a
guard written once also defends WaveCrux and NetCrux on the day either grows a
database.

| Guard | Checks | Red means |
|---|---|---|
| **G1** `cruxAuditSchemaFingerprints` | migrations 0→N applied in memory, `sqlite_master` normalised and hashed, against a checked-in manifest | a shipped migration was edited, a version vanished, or the latest version decreased |
| **G2** `cruxAuditAdditiveOnly` | the `(table, column)` set at N is a subset of the set at N+1 | a column's data no longer exists. Index churn is fine — indexes carry no data |
| **G3** `cruxAuditDestructiveDdl` | `DROP` / `RENAME` / bare `DELETE FROM` each carry `// MIGRATION-DESTRUCTIVE(<ruling>): …` | destruction with no ruling behind it, including destruction that never got a version number |
| **G4** `cruxAuditDatabaseDeletes` | no database delete outside a `case CruxDbRecovery.recreate:` arm or a waiver referencing the store's own recovery constant | the original defect being reintroduced by somebody solving a flaky open the quick way |
| **G5** `cruxAuditOpenOptions` | every hand-built `OpenDatabaseOptions` with `version:` also has `onDowngrade:` and a `busy_timeout` | a second open path, with one of the two live fuses relit |
| **G6** `cruxAuditFixtureSuites`, `cruxAuditFixtureCoverage`, `cruxAuditMigrationListRegistry` | every store has a suite driving `cruxMigrationFixtureCases` over its own list, every version in that list has a fixture, and every migration list is registered at all | a version, or a whole store, with nothing proving data survives it |

Each returns a `CruxGuardReport` whose `describe()` states **what broke, why the
rule exists, and the one legitimate way to make it green** — written for a
reader who has never heard of the audit that produced these rules. A host test
does `expect(report.isClean, isTrue, reason: report.describe())`, which is what
keeps this package free of any test framework.

**A guard never seen red is not a guard.** Every scanner here is proved against
hand-written violating sources (`CruxSourceFile.inline`) before it is trusted
against a real `lib/`, and the package holds itself to G3, G4 and G5 as well —
including the one sanctioned delete in the entire suite, the `recreate` arm of
the open policy, which qualifies structurally and needs no allowlist entry.

## The migration rules

The guards below enforce these rules, and every guard failure points here. Where
a store's behaviour and this section disagree, this section wins and the store
is the bug — which is why the machinery lives in one package rather than in
each store's memory. **Deleting or loosening a guard is never the fix**: if a
rule is wrong, it is edited here first and the guard follows.

### Rule 1 — append-only

**A migration that has shipped is frozen. You add version N+1; you never edit
version N.** Every user's file is the product of the exact sequence that
shipped. Editing N changes what a fresh install gets while every existing
install keeps the old shape, and the two diverge silently. It also invalidates
every historical fixture, because a vN fixture is built by running migrations
0→N, which is the historical schema only while N is frozen. Enforced by G1.

### Rule 2 — additive-only

**New tables, new indexes, `ALTER TABLE … ADD COLUMN` with a default, backfill
`UPDATE`s. No `DROP TABLE`, no `DROP COLUMN`, no `RENAME`, no destructive
`DELETE`** — unless waived in the source by a marker adjacent to the statement:

```dart
// MIGRATION-DESTRUCTIVE(<ruling>): <why, and what backs the data up>
```

A dropped or renamed column is a column whose data no longer exists; there is
no undo, the diff shows one line of SQL, and the user finds out months later.
An unmarked destructive statement is red, and so is a marker naming no ruling.
Index churn is allowed — indexes carry no data. Enforced by G2 and G3.

### Rule 3 — forward-only

**Downgrade is a hard, loud error in every store. Nothing migrates downwards
and nothing wipes a file to make a downgrade succeed.** An older build cannot
know what a newer schema means, and deleting the file so the old build can
start fresh turns a recoverable inconvenience into permanent loss — for a user
who did nothing wrong, such as a CI runner on last month's build opening the
file the desktop app already upgraded. The refusal names the pre-upgrade
backup (rule 4) when one exists.

Omitting `onDowngrade` does **not** give you a throw: sqflite skips the version
callbacks and stamps `user_version` down anyway, so the next new-build launch
re-runs a migration against a schema that already has it, on every open, with
no recovery path. Enforced by G5.

### Rule 4 — backup-first

**`VACUUM INTO` before any upgrade of a PRECIOUS database, and if the backup
fails the migration does not run.** See "The pre-upgrade backup" above for
the naming, the pruning and why a file copy is not a backup.

### Rule 5 — precious data is never deleted

**Not on corruption, not on a version mismatch, not ever.** The app cannot
tell "this file is garbage" from "this file is fine and I have a bug", so it
takes the reversible action: rename aside to
`<db>.corrupt-<ISO 8601 basic UTC>`, open fresh, keep the bytes, and tell the
user through the product's diagnostics seam — an empty chart after a
quarantine must not look like an empty chart after no runs. The only delete in
the suite is the `recreate` arm of `CruxSqliteOpenPolicy`, for derivable data.
Enforced by G4.

## Adding a migration

1. **Append the migration to the list.** Never touch an existing entry
   (rule 1). Versions are contiguous from 1.
2. **Do not bump a version constant.** There is none: the latest version is
   derived from the list, because a constant someone forgets to bump is a
   migration that silently never runs.
3. **Keep the description honest.** It is written into the
   `schema_migrations` ledger and shown in diagnostics, so say what the
   migration does in one sentence a support conversation can use.
4. **Add the frozen fingerprint to the manifest** — one new line for the new
   version (`cruxRenderSchemaManifest` prints it). If an *existing* line has to
   change, a shipped migration was edited; go back to step 1.
5. **Add a data-preserving fixture for the previous version.** Build a
   populated v(N−1) database by running migrations 0→N−1 and inserting rows
   with **raw SQL held in the test** — never through today's repository API,
   which only knows the current schema. Open it at HEAD through the real
   `CruxSqliteOpenPolicy` and assert that the upgrade succeeded, row counts and
   every pre-existing value are unchanged, new columns hold their default or
   backfill, every index the head schema declares is present, and the data
   reads back through the repository API. `cruxMigrationFixtureCases` is that
   loop.
6. **Add a changelog line** when the change is visible in any way, including
   "your history is preserved across this upgrade".

The model migration is an `ADD COLUMN … NOT NULL DEFAULT <safe value>` followed
by an idempotent backfill `UPDATE`: the default is chosen so that "the backfill
did not run" is survivable, and nothing is dropped.

## When additive is not enough

A wrong column type, a wrong `PRIMARY KEY`, a `NOT NULL` over existing NULLs or a
changed `CHECK` cannot be altered in place, and the answer is SQLite's 12-step
table rebuild — only when the additive path cannot express the change at all,
never to tidy up or reclaim space. Carrying a superseded column forever is the
normal, correct outcome of rule 2.

Inside the migration: record the text of every index, trigger and view on the
table; `CREATE TABLE new_X` with the corrected definition; `INSERT INTO new_X
(…) SELECT … FROM X` with the columns enumerated on both sides (never
`SELECT *`); `DROP TABLE X`; `ALTER TABLE new_X RENAME TO X`; recreate the
indexes, triggers and views; run `PRAGMA foreign_key_check` and fail the
migration on a single row. The `DROP` and the `RENAME` each carry the rule-2
waiver naming the ruling that permitted the rebuild. A rebuild copies data, and
a correct execution of an incorrect copy commits a well-formed, wrong table —
which is why rule 4's backup matters most here.

## Concurrency and version skew

**`busy_timeout` is mandatory on every open** — 5 s, set from `onConfigure`,
which sqflite runs outside the version transaction. Without it a second opener
that meets a held lock gets `SQLITE_BUSY` immediately, and at a naive catch
site a busy database is indistinguishable from a corrupt one.

A migration runs in one exclusive transaction, so a second process opening
mid-migration waits within its timeout and then sees the fully migrated file,
never a partial one. If it times out, that is a busy database: retry or report,
never recover. A migration that throws rolls back atomically, leaving the file
at its old version with all its data.

**Version skew** is two builds and one file: the file's version is higher than
this build's latest. The answer is rule 3 — refuse, naming both versions, the
app version that last wrote the file (from `schema_meta`), and the backup.

## Corruption, migration failure and version skew

Three different faults that arrive at a naive catch site as one exception.

| | Genuine corruption | Migration failure | Version skew |
|---|---|---|---|
| What happened | The bytes are not a valid SQLite database | Our migration code threw | The file is newer than this build |
| The data | Unreadable | Untouched — the transaction rolled back | Untouched |
| Correct response | Rename aside, open fresh, tell the user | Fail loudly, touch nothing, name the backup | Refuse loudly, name both versions and the backup |
| Never | Delete | Delete, retry, fall back to a fresh file | Delete, downgrade, wipe |

So **`on Object` never wraps an open**: it is a catch that cannot distinguish
anything, at the one site where the distinction decides whether a user keeps
their data. Catch the narrowest type that can only mean the fault you handle —
the sealed `CruxSqliteException` family exists for that — keep the migration
run out of any recovery `try`, and treat `SQLITE_BUSY` as none of the three.
A DERIVABLE store may still degrade to "no cache this session", provided each
fault class is caught by its own type and reported; anything unrecognised
propagates. Enforced by G5b.
