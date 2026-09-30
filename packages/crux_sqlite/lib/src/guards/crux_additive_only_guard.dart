// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_schema_snapshot.dart';

/// **Guard G2 — additive-only monotonicity.**
///
/// The set of tables at version N must be a subset of the set at N+1, and for
/// every table that already existed, the same for its columns. This is the
/// guard that directly implements "a push cannot destroy data outside a proper
/// migration": a dropped or renamed column is a column whose data no longer
/// exists, and there is no undo.
///
/// It works off the same [cruxSchemaSnapshotsOf] output as G1, so it sees what
/// SQLite actually ended up with rather than what the SQL appears to say — a
/// column removed by a table rebuild is caught here even though no `DROP
/// COLUMN` was ever written.
///
/// **Index churn is allowed and unchecked.** An index carries no data:
/// dropping one costs a query plan, and the row it pointed at is still there.
/// Requiring indexes to be monotonic would forbid replacing a bad index with a
/// better one, which is a change nobody should have to argue for.
CruxGuardReport cruxAuditAdditiveOnly({
  required CruxMigrationRunner runner,
  required List<CruxSchemaSnapshot> snapshots,
}) {
  final findings = <CruxGuardFinding>[];
  final ordered = [...snapshots]..sort((a, b) => a.version - b.version);

  for (var i = 0; i + 1 < ordered.length; i++) {
    final before = ordered[i];
    final after = ordered[i + 1];
    final step = 'v${before.version} -> v${after.version}';
    final describedBy = runner.latestVersion >= after.version
        ? ' ("${runner.migrationFor(after.version).description}")'
        : '';

    final droppedTables = before.tables.difference(after.tables).toList()
      ..sort();
    for (final table in droppedTables) {
      findings.add(
        CruxGuardFinding(
          location: '${runner.storeName} $step: table `$table`',
          detail:
              'the table exists at v${before.version} and does not exist at '
              'v${after.version}$describedBy. Every row it held on a '
              "user's disk is gone the moment they upgrade.",
        ),
      );
    }

    for (final table
        in before.tables.intersection(after.tables).toList()..sort()) {
      final lost =
          before.columnsByTable[table]!
              .difference(after.columnsByTable[table]!)
              .toList()
            ..sort();
      for (final column in lost) {
        findings.add(
          CruxGuardFinding(
            location: '${runner.storeName} $step: `$table`.`$column`',
            detail:
                'the column exists at v${before.version} and does not exist '
                'at v${after.version}$describedBy. If it was RENAMED, the '
                'data is still there under a name no earlier build knows; if '
                'it was DROPPED, the data is not there at all. From the '
                'outside those look the same, which is why neither is '
                'allowed without a written ruling.',
          ),
        );
      }
    }
  }

  return CruxGuardReport(
    guard: 'G2 — additive-only monotonicity',
    subject: runner.storeName,
    findings: findings,
    guideSection: 'rule 2; "When additive is not enough"',
    whatBroke:
        'A table or column that existed at one schema version does not exist '
        'at the next one.',
    whyTheRuleExists:
        'A dropped or renamed column is a column whose data no longer exists. '
        'The loss is invisible in review — the diff is one line of SQL — and '
        'the user finds out months later, when a chart is missing a series '
        'and nothing can bring it back. The additive set (new tables, new '
        'indexes, ADD COLUMN with a default, backfill UPDATEs) is closed '
        'under `cannot lose data`, which is the whole reason it is the only '
        'set allowed.',
    theWayToGreen:
        'Put it back. Carrying a superseded column forever is the normal, '
        'correct outcome of this rule and costs a few bytes a row — untidy is '
        'allowed, data loss is not. If the change genuinely cannot be '
        'expressed additively (a wrong column type, a wrong PRIMARY KEY), '
        'take the 12-step table-rebuild route in the guide, which requires a '
        'written ruling, a MIGRATION-DESTRUCTIVE waiver naming it, and a '
        'pre-upgrade backup.',
  );
}
