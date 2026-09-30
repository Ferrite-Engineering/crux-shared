// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_schema_manifest.dart';
import 'package:crux_sqlite/src/guards/crux_schema_snapshot.dart';

/// **Guard G1 — frozen schema fingerprints.**
///
/// A migration that has shipped is frozen: you add version N+1, you never edit
/// version N. This guard is the only thing that can tell the difference,
/// because both look like an ordinary diff to a `CREATE TABLE` string.
///
/// It compares the schema each version *actually produces* — run, not read
/// ([cruxSchemaSnapshotsOf]) — against [manifest]'s checked-in fingerprints.
/// Four ways to be red:
///
///  * **a fingerprint changed** — a shipped migration was edited;
///  * **a version has no manifest line** — a new version shipped without being
///    recorded, so from now on nothing freezes it either;
///  * **a manifest line has no version** — a version disappeared from the
///    list, or someone renumbered;
///  * **the latest version decreased** — a migration was removed from the end,
///    which strands every user already upgraded past it.
CruxGuardReport cruxAuditSchemaFingerprints({
  required CruxMigrationRunner runner,
  required List<CruxSchemaSnapshot> snapshots,
  required CruxSchemaManifest manifest,
}) {
  final findings = <CruxGuardFinding>[];
  final actual = {for (final s in snapshots) s.version: s.fingerprint};

  if (manifest.latestVersion > runner.latestVersion) {
    findings.add(
      CruxGuardFinding(
        location: '${runner.storeName}: latest version',
        detail:
            'the migration list stops at v${runner.latestVersion} but '
            '${manifest.source} records shipped versions up to '
            'v${manifest.latestVersion}. A schema version that has shipped '
            'cannot be withdrawn — every file already upgraded to '
            'v${manifest.latestVersion} would now be refused by this build as '
            'too new, on a downgrade nobody performed.',
      ),
    );
  }

  for (var version = 1; version <= runner.latestVersion; version++) {
    final recorded = manifest.fingerprints[version];
    final observed = actual[version];
    if (observed == null) {
      // Cannot happen for a well-formed snapshot list; reported rather than
      // asserted so a caller passing the wrong store's snapshots learns why.
      findings.add(
        CruxGuardFinding(
          location: '${runner.storeName}: v$version',
          detail:
              'no snapshot was produced for v$version — the snapshot list '
              'passed in does not cover this runner.',
        ),
      );
      continue;
    }
    if (recorded == null) {
      findings.add(
        CruxGuardFinding(
          location: '${runner.storeName}: v$version',
          detail:
              'not recorded in ${manifest.source}. Its schema fingerprint is '
              '$observed. If v$version is a version you just added, this is '
              'the one line you owe the manifest.',
        ),
      );
      continue;
    }
    if (recorded != observed) {
      findings.add(
        CruxGuardFinding(
          location: '${runner.storeName}: v$version',
          detail:
              'v$version produces a different schema than the one that '
              'shipped.\n'
              '            recorded: $recorded\n'
              '            now:      $observed\n'
              '        The v$version migration is '
              '"${runner.migrationFor(version).description}".',
        ),
      );
    }
  }

  // Versions above the list's latest are already reported as a withdrawal
  // above; what is left is a manifest line no migration list can ever produce,
  // which means the file has been hand-edited.
  for (final version in manifest.fingerprints.keys.toList()..sort()) {
    if (version >= 1) continue;
    findings.add(
      CruxGuardFinding(
        location: '${manifest.source}: v$version',
        detail:
            'v$version is not a version any migration list can produce — '
            'versions are contiguous from 1.',
      ),
    );
  }

  return CruxGuardReport(
    guard: 'G1 — frozen schema fingerprints',
    subject: '${runner.storeName} vs ${manifest.source}',
    findings: findings,
    guideSection: 'rule 1; "Adding a migration", step 4',
    whatBroke:
        'The schema one or more SHIPPED versions produce is not the schema '
        'that was recorded when they shipped.',
    whyTheRuleExists:
        'Every existing user file is the product of the exact migration '
        'sequence that shipped. Editing migration N changes what a FRESH '
        'install gets while leaving every already-installed file on the old '
        'shape, so the two silently diverge — and nothing at runtime ever '
        'notices, because both files report the same version number. It also '
        'invalidates every historical test fixture at a stroke: a vN fixture '
        'is built by running migrations 0->N, which is the historical schema '
        'only for as long as N is frozen.',
    theWayToGreen:
        'Revert the edit to the shipped migration and express the change as a '
        'NEW migration appended to the list, then add ONE line to the '
        'manifest for it. Never edit an existing manifest line, and never '
        'regenerate the manifest to make this pass — regenerating is the same '
        'action as deleting the guard.',
  );
}
