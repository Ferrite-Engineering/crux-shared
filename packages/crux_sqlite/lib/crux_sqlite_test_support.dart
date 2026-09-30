// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Test-only tooling for proving a store built on `crux_sqlite` keeps the
/// one promise that actually matters: data survives an upgrade.
///
/// ### Why this is a separate entry point
///
/// The main `crux_sqlite.dart` barrel is the runtime surface every store
/// opens through, and it stays exactly that — nothing here is exported from
/// it, and nothing here is ever imported by a product's `lib/`. The
/// precedent is `crux_license`'s `crux_license_core.dart`: a package's normal
/// barrel is its production contract, and tooling that exists only to *test*
/// stores
/// built on that contract gets its own import so the two can never blur —
/// `test-only tooling must never enter the runtime API surface`, which this
/// package's own `crux_sqlite_guards.dart` (the CI guard scanners) will
/// follow the same way.
///
/// ```dart
/// import 'package:crux_sqlite/crux_sqlite.dart';               // runtime
/// import 'package:crux_sqlite/crux_sqlite_test_support.dart';  // tests only
/// ```
///
/// ### What is here
///
/// [cruxMigrationFixtureCases] is the shared loop behind every store's
/// data-preserving migration suite (README, "Adding a migration", step 5):
/// build a
/// populated fixture at each historical schema version, upgrade it through
/// the real production [CruxSqliteOpenPolicy], and assert nothing was lost.
/// It returns plain [CruxMigrationFixtureCase] values — this package never
/// calls `test()` itself, so it never has to choose between `package:test`
/// and `package:flutter_test`, which three of the four Crux SQLite databases
/// are exercised from.
///
/// [cruxOpenSecondConnectionVersion] is the concurrent-opener probe: a
/// second, genuinely independent connection to the same file, run in its own
/// isolate so it is not serialized behind the same in-process lock the first
/// connection holds (README, "Concurrency and version skew").
///
/// [cruxColumnNamesOf] and [cruxIndexNamesOf] are the small `PRAGMA
/// table_info` / `sqlite_master` readers every fixture assertion needs to
/// check a column or an index actually exists.
///
/// Pure Dart, same as the runtime barrel — no test framework is a dependency
/// of this library, only of the tests that consume it.
library;

// Imported (not just exported) so the doc comment's [cross-references]
// above resolve; the public surface itself comes from the `export`s below.
import 'package:crux_sqlite/src/crux_open_policy.dart';
import 'package:crux_sqlite/src/testing/crux_concurrent_opener_probe.dart';
import 'package:crux_sqlite/src/testing/crux_migration_fixture_harness.dart';
import 'package:crux_sqlite/src/testing/crux_schema_probe.dart';

export 'src/crux_open_policy.dart'
    show CruxDbRecoveryListener, CruxSqliteOpenPolicy;
export 'src/testing/crux_concurrent_opener_probe.dart';
export 'src/testing/crux_migration_fixture_harness.dart';
export 'src/testing/crux_schema_probe.dart';
