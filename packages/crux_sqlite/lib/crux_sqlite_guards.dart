// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The six CI guards that make a data-destroying schema change fail a build
/// instead of failing a user.
///
/// Six numbered rules, seven scanners: G5 grew a second half, G5b, rather
/// than the suite growing a seventh guard with one rule and its own manifest
/// for nobody to read.
///
/// ### Why this is a separate entry point
///
/// Same reason as `crux_sqlite_test_support.dart`, and the same precedent —
/// `crux_license_core.dart`. The main
/// `crux_sqlite.dart` barrel is the runtime contract every store opens
/// through, and test-only tooling never enters it. Nothing here is exported
/// from the runtime barrel and nothing here is ever imported by a product's
/// `lib/`. Like the other secondary barrels it carries its own
/// `api/crux_sqlite_guards.api.txt` golden, because a consumer can import it
/// and that makes it public API by exactly the same definition.
///
/// ```dart
/// import 'package:crux_sqlite/crux_sqlite.dart';               // runtime
/// import 'package:crux_sqlite/crux_sqlite_test_support.dart';  // fixtures
/// import 'package:crux_sqlite/crux_sqlite_guards.dart';        // guards
/// ```
///
/// ### The shape, and why it is not a workflow
///
/// The **scanners are here**, shared. What lives in each product is a thin
/// test under `test/static/` that points them at that repo's own sources,
/// migration lists and manifests. Both Pro repos already run `flutter test` in
/// CI and both already have a static-guard tradition, so the guards ride an
/// existing job: no new workflow, no new billing surface, and no new
/// `timeout-minutes` for somebody to forget.
///
/// Because the scanners are shared, a guard written once defends WaveCrux and
/// NetCrux too — on the day either grows a database, and without either repo
/// having to know how these rules came about.
///
/// ### The six
///
/// Numbered as the package README numbers them. G5 has two halves.
///
/// * **G1** [cruxAuditSchemaFingerprints] — a shipped migration was edited, a
///   version vanished, or the latest version decreased.
/// * **G2** [cruxAuditAdditiveOnly] — a table or column stopped existing
///   between two versions.
/// * **G3** [cruxAuditDestructiveDdl] — `DROP` / `RENAME` / bare
///   `DELETE FROM` with no waiver naming a ruling.
/// * **G4** [cruxAuditDatabaseDeletes] — a database file deleted by code that
///   cannot establish the data is reproducible.
/// * **G5** [cruxAuditOpenOptions] — a hand-rolled open missing `onDowngrade`
///   or `busy_timeout`; and **G5b** [cruxAuditOpenCatchShapes] — a catch-all
///   wrapped around a call that reaches an open, which is the one catch shape
///   that cannot tell corruption from our own migration bug from version
///   skew.
/// * **G6** [cruxAuditFixtureSuites], [cruxAuditFixtureCoverage] and
///   [cruxAuditMigrationListRegistry] — a version, or a whole store, with
///   nothing proving data survives it.
///
/// G1 and G2 share their input: [cruxSchemaSnapshotsOf] runs the migrations
/// 0→N in memory for each N and reports what SQLite actually ended up with.
/// Compute it once per store and hand it to both.
///
/// ### Every guard returns a value; nothing here calls `test()`
///
/// Each audit returns a [CruxGuardReport]. It is clean or it is not, and
/// [CruxGuardReport.describe] renders the failure message: **what broke, why
/// the rule exists, and the one legitimate way to make it green** — written
/// for a reader who has never heard of the audit that produced these rules,
/// because in a year that is everyone. A host test does:
///
/// ```dart
/// final report = cruxAuditAdditiveOnly(runner: runner, snapshots: snapshots);
/// expect(report.isClean, isTrue, reason: report.describe());
/// ```
///
/// That keeps this package pure Dart with no test framework in it, and it
/// means the message a developer reads is identical in both products.
///
/// ### A guard never seen red is not a guard
///
/// Every scanner here is proved against hand-written violating sources —
/// [CruxSourceFile.inline] exists for exactly that — before it is trusted
/// against a real `lib/`. A text scanner that has only ever been run over a
/// clean tree has never distinguished "the tree is clean" from "the regex
/// rotted".
///
/// The rules themselves, and the reasoning behind each one, are in the
/// package README, "The migration rules" ([kCruxMigrationGuideRef]).
/// **Deleting or loosening a guard is never the fix.** If a guard is wrong, it
/// is wrong in a way that can be stated — and the statement belongs in that
/// section first, as an edit to the rule, before the code that enforces it
/// changes.
///
/// Pure Dart, same as the runtime barrel.
library;

// Imported as well as exported so the [cross-references] above resolve.
import 'package:crux_sqlite/src/guards/crux_additive_only_guard.dart';
import 'package:crux_sqlite/src/guards/crux_database_delete_guard.dart';
import 'package:crux_sqlite/src/guards/crux_destructive_ddl_guard.dart';
import 'package:crux_sqlite/src/guards/crux_fixture_coverage_guard.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';
import 'package:crux_sqlite/src/guards/crux_open_catch_guard.dart';
import 'package:crux_sqlite/src/guards/crux_open_options_guard.dart';
import 'package:crux_sqlite/src/guards/crux_schema_fingerprint_guard.dart';
import 'package:crux_sqlite/src/guards/crux_schema_snapshot.dart';

export 'src/crux_db_recovery.dart' show CruxDbRecovery;
export 'src/crux_migration.dart' show CruxMigration, CruxMigrationRunner;
export 'src/guards/crux_additive_only_guard.dart';
export 'src/guards/crux_database_delete_guard.dart';
export 'src/guards/crux_destructive_ddl_guard.dart';
export 'src/guards/crux_fixture_coverage_guard.dart';
export 'src/guards/crux_guard_report.dart';
export 'src/guards/crux_guard_sources.dart';
export 'src/guards/crux_open_catch_guard.dart';
export 'src/guards/crux_open_options_guard.dart';
export 'src/guards/crux_schema_fingerprint_guard.dart';
export 'src/guards/crux_schema_manifest.dart';
export 'src/guards/crux_schema_snapshot.dart';
