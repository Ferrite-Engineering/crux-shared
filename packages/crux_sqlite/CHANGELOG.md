# Changelog

## Unreleased

- **The Windows free-space probe runs `fsutil` by absolute path.** A bare
  name is searched for in the launching process's current directory before
  `PATH`, so an `fsutil.exe` in the directory a product was launched from
  could have answered the pre-migration space check. It is now resolved with
  `crux_io`'s `requireSpawnExecutableForHost`, and when nothing on `PATH`
  answers to it the probe reports "unknown" rather than spawning a bare name.
  The POSIX `df` probe is unchanged: `execvp` never searches the current
  directory.

- **The free-space probe no longer reports another column as free space.**
  `cruxFreeDiskBytes` read `df -k -P` by position, so a filesystem whose name
  holds a space — a network share (`//nas/Team Share`), a FUSE mount — shifted
  the columns and the **Used** figure (or the total) came back as free: a
  confident answer many times too large, which is the one answer that waves a
  `VACUUM INTO` through on a volume that cannot hold it. The row is now found
  by its capacity column. On Windows the first "free bytes" line of
  `fsutil volume diskfree` is the volume's, not the caller's; under a quota
  the probe now takes the smallest such line. And a digit-group separator
  missing from a fixed list (`76'787'392'512`, or a narrow no-break space)
  read as 76 bytes and refused the migration on a healthy volume; every
  non-digit before the size suffix is dropped instead. Output neither parser
  recognises is `null`, which the caller already treats as "let the backup
  write be the judge". The parsers are in `src/free_disk_space_parse.dart`,
  unexported, and tested against real output shapes.

## 0.4.1

- **The migration rules are written down in this package's README**, under
  "The migration rules", "Adding a migration", "When additive is not enough",
  "Concurrency and version skew" and "Corruption, migration failure and version
  skew". `kCruxMigrationGuideRef` is now
  `crux-shared/packages/crux_sqlite/README.md`, as a consuming product's
  checkout reaches it, and each guard's `guideSection` names a rule number and
  those section titles instead of the numbering of a document readers could not
  open. A guard failure reads `The rule, and the reasoning behind it:
  crux-shared/packages/crux_sqlite/README.md — rule 2; "When additive is not
  enough"`.
- `cruxRenderSchemaManifest` writes `# The rule: <kCruxMigrationGuideRef>,
  rule 1.` in the manifest header. Comment lines are not parsed, so an existing
  manifest keeps its fingerprints; regenerate it, or edit that one header line,
  to pick up the new pointer.

## 0.4.0

- **G5b `cruxAuditOpenCatchShapes`** — the half of G5 that reads the *catch*
  rather than the open. No `catch (e)` and no `on Object catch` may wrap a call
  that reaches a database open, because that one handler is where genuine
  corruption, a migration failure of ours, and a version skew between two
  builds all arrive as the same object — and only the first of the three is a
  case where the data is actually gone. An extension of G5 rather than a
  seventh guard: G5 asks whether an open is *built* safely, G5b asks whether
  its failure is *read* safely, and both work off the same inventory of what
  counts as an open.
  - **It knows what reaches an open by deriving it, not by a hand-list.**
    `cruxOpenReachingEntryPoints` starts from `openDatabase(...)` and from
    `<policy>.open(...)` — the same receiver heuristic `cruxAuditOpenOptions`
    uses — and then promotes any `static` method or `factory` constructor whose
    body reaches one of those into an entry point of its own, matched at call
    sites as `Class.method(...)`, repeating until the set stops growing (at
    most `kCruxOpenReachRounds`). A new store's `open` factory is therefore
    covered the day it is written, with nobody remembering to list it. That
    matters because the violation this guard was built for was never a catch
    around `openDatabase`: it was a catch around
    `SqliteLintRunCacheService.open`, one step downstream of a
    policy-conforming open, which is exactly why G5 could not see it and why it
    survived every earlier review.
  - **Its boundary is stated in the failure message, not only in the
    docstring.** It is a text scan, not a call graph: an open reached only
    through an instance method, a function-typed field, a tear-off, a top-level
    function, or a class in a package outside the scanned sources is not
    derived. `extraOpenEntryPoints` is how a repo closes that gap deliberately
    instead of discovering it — SimCrux Pro needs it in the ordinary case,
    because its store factory lives in the open-core tree its own scan does not
    read. A guard that quietly checks less than it appears to is worse than one
    with a boundary.
  - **`CruxOpenCatchAllowlistEntry`** carries the store's own `CruxDbRecovery`
    constant rather than a copy of its value, exactly as
    `CruxDeleteAllowlistEntry` does, and is honoured only when that constant is
    `recreate` — so a store turning PRECIOUS withdraws its own permission with
    nobody having to come back and edit the list. An entry matching nothing is
    red. The allowlist is empty in all three product repos and is meant to stay
    that way: even the suite's one DERIVABLE store degrades through typed
    catches.
  - Comments and string literals are blanked before any scanning, with offsets
    preserved, so a `try {` in a doc comment and the paragraph explaining why
    `on Object` is forbidden are not read as code. This guard's subject matter
    is written about at length in the comments beside every site it scans, and
    flagging the explanation of why the code is right is the most demoralising
    false positive there is.
  - Proved red against the real repositories, not only fixtures: the historical
    `on Object { return null; }` in LintCrux Pro's `_openSafe` and an
    injected catch-all around `SqlTrendStore.open` in SimCrux. Quiet across all
    eight product trees — both Pro overlays and all four open cores, including
    WaveCrux's and NetCrux's, which have no database at all yet.

## 0.3.0

- **`crux_sqlite_guards.dart`**, a third entry point (after
  `crux_sqlite_test_support.dart`, on the same
  `crux_license_core.dart` / `crux_projects_io.dart` precedent): the six CI
  guards that make a data-destroying schema change fail a build instead of
  failing a user. The scanners are shared here; what lives in each product is a
  thin test under `test/static/` pointing them at that repo's own sources,
  migration lists and manifests. **Not a new workflow** — both Pro repos
  already run `flutter test` in CI, so the guards ride an existing job and add
  no billing surface and no `timeout-minutes` to forget. Because they are
  shared, a guard written once also defends WaveCrux and NetCrux on the day
  either grows a database.
  - **G1 `cruxAuditSchemaFingerprints`** — applies the migrations 0→N in memory
    for each N (`cruxSchemaSnapshotsOf`), dumps `sqlite_master` normalised and
    hashed, and compares against a checked-in `CruxSchemaManifest`. Editing a
    shipped migration changes an old fingerprint and goes red; adding version
    N+1 needs one new manifest line and nothing else. A version that
    disappears, or a latest version that decreases, is red.
  - **G2 `cruxAuditAdditiveOnly`** — the `(table, column)` set at version N is a
    subset of the set at N+1. Works off the produced schema, so a column lost
    through a table rebuild is caught with no `DROP COLUMN` anywhere in the
    source. Index churn is allowed; indexes carry no data.
  - **G3 `cruxAuditDestructiveDdl`** — `DROP TABLE`, `DROP COLUMN`, `RENAME TO`,
    `RENAME COLUMN` and bare `DELETE FROM` must each carry an adjacent
    `// MIGRATION-DESTRUCTIVE(<ruling>): <why, and what backs the data up>`.
    A marker naming no ruling, or carrying no rationale, is still red. Catches
    what G2 cannot see because it never got a version number.
  - **G4 `cruxAuditDatabaseDeletes`** — no `deleteDatabase()` and no
    `File.delete()`/`deleteSync()` on a `.db` path (a call whose argument list
    is empty or only `recursive:`, which is `FileSystemEntity.delete`'s
    signature — sqflite's ROW delete `Database.delete(table, {where})` takes a
    positional table name and is explicitly permitted), unless the site is attributable to a store
    whose recovery is `recreate`. Two ways: structurally (inside a
    `case CruxDbRecovery.recreate:` arm — how this package's own one sanctioned
    delete qualifies, with no allowlist entry), or by a `CruxDeleteAllowlistEntry`
    that **references the store's own `CruxDbRecovery` constant**, so a store
    turning PRECIOUS withdraws its own waiver. A waiver matching nothing is red.
  - **G5 `cruxAuditOpenOptions`** — every hand-built `OpenDatabaseOptions`
    passing `version:` must also pass `onDowngrade:` and set `busy_timeout` via
    `onConfigure:`. Also inventories direct `openDatabase` calls that bypass
    `CruxSqliteOpenPolicy.open`, against a pinned set, so a new bypass is a
    review conversation rather than a discovery.
  - **G6 `cruxAuditFixtureSuites`, `cruxAuditFixtureCoverage`,
    `cruxAuditMigrationListRegistry`** — every store has a data-preserving
    suite that actually drives `cruxMigrationFixtureCases` over *its* list,
    every version in that list has a fixture, and every `List<CruxMigration>`
    in the repo is registered with the guards at all. The middle one is
    currently satisfied by construction — all four suites build their fixture
    map as a comprehension over `1..latestVersion` — and says so; the
    load-bearing halves today are the first and the third.
  - Every audit returns a `CruxGuardReport`, whose `describe()` states **what
    broke, why the rule exists, and the one legitimate way to make it green**,
    written for a reader who has never heard of the audit that produced these
    rules. This package still calls no test framework's `test()` itself.
  - New dependency: `crypto` (G1's fingerprints). Pure Dart, and already in the
    workspace's resolved set via `crux_cxp` and `crux_license`.
- **`formatCruxSchemaTimestamp` truncates to milliseconds, so its stamps really
  are fixed-width.** It documented "milliseconds" and was
  `toIso8601String()`, which widens the fraction to six digits whenever the
  microsecond component is non-zero — nearly every real `DateTime.now()`. The
  `schema_meta` / `schema_migrations` columns were therefore a mix of
  `.512Z` and `.512697Z`, and mixed widths do not sort as text: `.512Z` sorts
  *after* `.512001Z`. That sort is the stated reason those columns use the ISO
  8601 *extended* form rather than the basic form the backup and quarantine
  filenames use, so the claim is now made true rather than retracted — the
  shared team database is specified to port this shape. **No
  migration and no rewrite of existing rows:** reads go through `DateTime.parse`,
  which accepts both widths, nothing in the suite sorts these columns as text,
  and the ledger shipped in no release before this.

## 0.2.0

- **`crux_sqlite_test_support.dart`**, a second entry point mirroring
  `crux_license_core.dart` / `crux_projects_io.dart`: test-only tooling that
  proves a store built on this package actually keeps its promises, never
  exported from the runtime barrel. `cruxMigrationFixtureCases` is the shared
  loop behind every store's data-preserving migration suite — build a
  populated fixture at each historical schema version, upgrade it through the
  real production `CruxSqliteOpenPolicy`, and assert nothing was lost. A
  version with no registered fixture still gets a case, one that throws the
  moment it runs, so a shipped migration with no fixture fails loudly instead
  of silently going uncovered. `cruxOpenSecondConnectionVersion` is the
  concurrent-opener probe (a second connection in its own isolate, so it is
  not serialized behind the same in-process lock the first connection holds).
  `cruxColumnNamesOf` / `cruxIndexNamesOf` are the small schema readers every
  fixture assertion needs. This package still calls no test framework's
  `test()`/`group()` itself — the harness returns plain
  `CruxMigrationFixtureCase` values so it never has to choose between
  `package:test` and `package:flutter_test`.

- **Automatic pre-upgrade backup for every PRECIOUS database.** Before any
  upgrade of a store whose `CruxDbRecovery` says its data is unreconstructible,
  the open path writes `<db>.pre-v<oldVersion>-<ISO 8601 basic UTC>.bak` with
  `VACUUM INTO`, from `onConfigure` — the one hook `sqflite_common` runs outside
  the exclusive version transaction, which `VACUUM` cannot run inside. A store
  opts in by *being precious* (`CruxDbRecovery.isPrecious`), not by remembering
  to call anything; `cache.db` opts out by already declaring `recreate`.
  - **A failed backup aborts the migration**, as `CruxBackupFailedException` —
    a fourth member of the `sealed CruxSqliteException` family, so a diagnostics
    switch over it is a compile error until it is handled.
  - On success the newest `kCruxBackupsKept` (2) survive; pruning runs in
    `onOpen`, which a failed migration never reaches, so a failure keeps every
    backup it has.
  - `CruxMigrationFailedException.backupPath` and
    `CruxSchemaVersionSkewException.backupPath` name the file by absolute path —
    the second is the answer for a downgrading user.
  - New: `CruxPreUpgradeBackup`, `CruxBackupNotice`, `CruxBackupListener`,
    `CruxBackupFailureKind`, `CruxDbRecovery.isPrecious`,
    `CruxSqliteOpenPolicy.backup` / `.backsUpBeforeUpgrade`,
    `kCruxBackupsKept`, `kCruxBackupSizeGuardBytes`,
    `kCruxBackupFreeSpaceHeadroom`, `cruxFreeDiskBytes`, `CruxFreeDiskProbe`.
- Fix: `crux_io` was declared as a bare `^0.2.0` version constraint instead of
  the `path: ../crux_io` every other workspace sibling uses. `resolution:
  workspace` hid this from every check run *inside* crux-shared (melos, `dart
  pub get` at the root), but it broke the first product that took a plain
  `path:` dependency on this package from outside the workspace — exactly how
  every product consumes crux-shared — with "crux_sqlite from path is
  forbidden" (path vs. hosted source conflict against the product's own
  `crux_io` path dependency). Found adopting the package in the first store.

## 0.1.0

Initial release — the foundation every SQLite-using store in the suite will open
through.

- `CruxMigration` / `CruxMigrationRunner`: the append-only, additive-only
  migration model, ported from SimCrux's `SqlMigrations` (the one of the four
  stores already shaped correctly). The latest version is derived from the list
  length; the constructor rejects a list that is empty, non-contiguous from 1, or
  carrying a blank description, as a throw rather than an `assert`.
- `CruxSqliteOpenPolicy`: the one place in the suite an `OpenDatabaseOptions` is
  constructed. Version from the runner, `onCreate` and `onUpgrade` both routed
  through it, an `onDowngrade` that refuses, and the mandatory 5 s
  `busy_timeout`. Carries the recorded decisions that WAL is not adopted and
  that foreign-key enforcement stays off.
- `CruxDbRecovery`: the PRECIOUS/DERIVABLE data-value policy as a type declared
  at the call site — `renameAside`, `refuse`, `recreate`. `renameAside` and
  `recreate` require a recovery listener, so a silent quarantine is not an
  expressible shape.
- `CruxDatabaseCorruptionException`, `CruxMigrationFailedException`,
  `CruxSchemaVersionSkewException`: the three faults that used to arrive at one
  catch site as one exception, under a `sealed` base so a diagnostics surface
  can switch over them exhaustively.
- `isSqliteCorruption` and `quarantineDatabaseFile`, lifted from LintCrux Pro.
  `SQLITE_BUSY`, `SQLITE_LOCKED`, `SQLITE_READONLY` and `SQLITE_CANTOPEN` are
  deliberately excluded — a busy database must never read as a corrupt one.
- `ensureCruxSqliteFfiInitialized`, replacing the private copy each store kept.
