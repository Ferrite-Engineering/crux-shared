// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/crux_migration.dart';
import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';

/// **Guard G6 — fixture coverage.**
///
/// Every version in a store's migration list has a data-preserving fixture:
/// a populated database built at that historical version, upgraded to HEAD
/// through the real production open path, and asserted field by field.
///
/// ## Why this is a data check and not a source scan
///
/// The per-version half of G6 is checked against the fixture map itself —
/// the same `Map<int, CruxMigrationFixture>` the store's data-preserving suite
/// hands to `cruxMigrationFixtureCases`, passed here as its key set. The
/// alternative was to regex the test file for map literal keys, and it is
/// worse in both directions: it would miss a map assembled by a loop or a
/// helper (a false green), and it would misread a key spelled as a constant (a
/// false red). Re-deriving by parsing a fact the program already holds is how
/// a guard ends up being about the parser.
///
/// ## Why the runtime harness is not enough on its own
///
/// `cruxMigrationFixtureCases` already emits one case per version and throws a
/// `StateError` naming the version when a registered fixture is missing, so
/// per-version coverage *is* enforced at run time. Two gaps remain, and they
/// are the reason this exists as a separate, static-ish guard:
///
///  * **It only fires for lists it was handed.** A store whose suite never
///    calls the harness produces zero cases and therefore zero failures. The
///    absence of a test looks exactly like a passing test. That gap is closed
///    by [cruxAuditFixtureSuites], not by this function.
///  * **It fires late and expensively.** The runtime failure happens inside a
///    case that has already created a temp directory and run a real upgrade,
///    one version at a time, so the first missing fixture is what you see.
///    This reports every gap at once, before any I/O, naming the store.
///
/// **Where it currently stands, stated plainly:** all four Crux SQLite stores
/// build their fixture map as a comprehension over
/// `1..runner.latestVersion`, so their key sets are complete by construction
/// and this check passes automatically. It becomes live the moment a map is
/// written out per version — which is what happens as soon as two versions
/// need different seed data. Until then the load-bearing halves of G6 are
/// [cruxAuditFixtureSuites] and [cruxAuditMigrationListRegistry].
CruxGuardReport cruxAuditFixtureCoverage({
  required CruxMigrationRunner runner,
  required Set<int> fixtureVersions,
}) {
  final findings = <CruxGuardFinding>[];

  for (var version = 1; version <= runner.latestVersion; version++) {
    if (fixtureVersions.contains(version)) continue;
    findings.add(
      CruxGuardFinding(
        location: '${runner.storeName}: v$version',
        detail:
            'no data-preserving fixture. The v$version migration is '
            '"${runner.migrationFor(version).description}", and nothing '
            'proves a file sitting at v$version today still holds its rows '
            'after upgrading to v${runner.latestVersion}.',
      ),
    );
  }

  for (final version in fixtureVersions.toList()..sort()) {
    if (version >= 1 && version <= runner.latestVersion) continue;
    findings.add(
      CruxGuardFinding(
        location: '${runner.storeName}: v$version fixture',
        detail:
            'a fixture is registered for v$version, which this migration list '
            'cannot produce (it runs 1..${runner.latestVersion}). Either a '
            'version was removed from the list — which strands every user '
            'already past it — or the fixture is numbered wrong and is '
            'silently testing nothing.',
      ),
    );
  }

  return CruxGuardReport(
    guard: 'G6 — fixture coverage',
    subject: runner.storeName,
    findings: findings,
    guideSection: '"Adding a migration", step 5',
    whatBroke:
        'A shipped schema version has no test proving that a user’s data '
        'survives the upgrade out of it.',
    whyTheRuleExists:
        'A migration is code, and the only evidence that a particular '
        'migration preserves data is a test that starts from a populated file '
        'at the OLD version and checks the values afterwards. Every version '
        'that ships without one is a version some user is sitting on with '
        'nothing standing behind it — and the failure, when it comes, is '
        'silent: rows that are simply not there any more, discovered when a '
        'chart looks wrong months later.',
    theWayToGreen:
        'Write the fixture. Build a populated v(N-1) database by running the '
        'migrations 0->N-1 and inserting rows through RAW SQL held in the '
        'test — never through the repository API, which only knows the '
        'current schema and would drift the fixture forward with the code. '
        'Then open at HEAD through the real production open path and assert: '
        'row counts unchanged, every pre-existing column value unchanged '
        'field by field, new columns at their declared default or backfilled '
        'value, every head index present, and the data reading back correctly '
        'through the repository API. cruxMigrationFixtureCases in '
        'crux_sqlite_test_support.dart is the loop; you supply the seed and '
        'the assertions.',
  );
}

/// **Guard G6, the half that is not vacuous today.**
///
/// Requires each registered store to have a data-preserving suite that
/// actually drives `cruxMigrationFixtureCases` over *its* migration list.
///
/// This exists because of what the four existing suites look like. Every one
/// of them builds its fixture map as a comprehension —
/// `{for (var v = 1; v <= runner.latestVersion; v++) v: _fixture(v)}` — so its
/// key set is complete by construction and [cruxAuditFixtureCoverage] cannot
/// tell it anything it does not already know. That is a perfectly good way to
/// write the suite; it just means the per-version check is currently satisfied
/// automatically, and a guard that is satisfied automatically is not doing
/// work. What remains genuinely losable is the whole suite: a new store lands,
/// nobody writes one, and every other guard stays green because none of them
/// looks at `test/`.
///
/// [storeMarkers] maps a store's name to the identifiers that would appear in
/// its suite — its migration list, its store class. A file under the scanned
/// test tree must contain a `cruxMigrationFixtureCases(` call *and* one of
/// those identifiers.
CruxGuardReport cruxAuditFixtureSuites({
  required Iterable<CruxSourceFile> testSources,
  required Map<String, List<String>> storeMarkers,
  required String subject,
}) {
  final findings = <CruxGuardFinding>[];
  final observations = <CruxGuardFinding>[];
  final harnessFiles = testSources
      .where((f) => f.source.contains('cruxMigrationFixtureCases('))
      .toList();

  for (final entry in storeMarkers.entries) {
    final matches = harnessFiles
        .where((f) => entry.value.any(f.source.contains))
        .toList();
    if (matches.isEmpty) {
      findings.add(
        CruxGuardFinding(
          location: entry.key,
          detail:
              'no file under the scanned test tree calls '
              'cruxMigrationFixtureCases() and mentions any of '
              '${entry.value.join(', ')}. This store has no data-preserving '
              'migration suite at all, so every version of it is unproven and '
              'no other guard is looking.',
        ),
      );
      continue;
    }
    observations.add(
      CruxGuardFinding(
        location: entry.key,
        detail:
            'data-preserving suite: '
            '${(matches.map((f) => f.path).toList()..sort()).join(', ')}',
      ),
    );
  }

  if (storeMarkers.isNotEmpty && harnessFiles.isEmpty) {
    findings.add(
      const CruxGuardFinding(
        location: 'the whole test tree',
        detail:
            'nothing anywhere calls cruxMigrationFixtureCases(). Either the '
            'scan is pointed at the wrong directory — in which case this '
            'guard has been passing vacuously — or every data-preserving '
            'suite in this repo is gone.',
      ),
    );
  }

  findings.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G6 — fixture coverage (data-preserving suite exists)',
    subject: subject,
    findings: findings,
    observations: observations,
    guideSection: '"Adding a migration", step 5',
    whatBroke:
        'A store has no data-preserving migration suite, so nothing anywhere '
        'proves an upgrade of it keeps the data.',
    whyTheRuleExists:
        'The runtime harness fails loudly when a REGISTERED store is missing '
        'a version, but it only ever runs for the migration lists somebody '
        'handed it. A store whose suite was never written produces no cases '
        'and therefore no failures, and the absence of a test looks exactly '
        'like a passing test. Every other guard reads lib/ and would stay '
        'green throughout.',
    theWayToGreen:
        "Write the suite: hand the store's runner, its CruxDbRecovery "
        'declaration and a fixture per version to cruxMigrationFixtureCases '
        'in crux_sqlite_test_support.dart, and register each returned case '
        "with your test framework's test(). The README's \"Adding a "
        'migration" step 5 says what each fixture must assert.',
  );
}

/// The guard set's own guard: every `List<CruxMigration>` declared in the
/// scanned sources is registered with the guards.
///
/// G1, G2 and G6 are all *per store*, and a store they were never told about
/// is a store none of them checks. Nothing else in the mechanism notices that:
/// a new database with a hand-written open path and no registration would sail
/// through a completely green guard suite, which is precisely the shape the
/// suite got into before any of this existed — five open paths, four opinions,
/// one of them deleting user data.
///
/// [registeredListNames] are the Dart identifiers the repo's guard test has
/// pointed the other guards at, e.g. `lintcruxTrendStoreMigrations`.
CruxGuardReport cruxAuditMigrationListRegistry({
  required Iterable<CruxSourceFile> sources,
  required Set<String> registeredListNames,
  required String subject,
}) {
  final findings = <CruxGuardFinding>[];
  final declared = <String, String>{};

  for (final file in sources) {
    for (final match in _migrationListDeclaration.allMatches(file.source)) {
      declared[match.group(1)!] = file.locate(match.start);
    }
  }

  for (final entry in declared.entries) {
    if (registeredListNames.contains(entry.key)) continue;
    findings.add(
      CruxGuardFinding(
        location: entry.value,
        detail:
            '`${entry.key}` is a migration list no guard has been pointed at. '
            'Its schema is not fingerprinted (G1), its versions are not '
            'checked for additivity (G2), and nothing requires it to have '
            'data-preserving fixtures (G6).',
      ),
    );
  }

  for (final name in registeredListNames.toList()..sort()) {
    if (declared.containsKey(name)) continue;
    findings.add(
      CruxGuardFinding(
        location: 'registered list `$name`',
        detail:
            '`$name` is registered with the guards but declared nowhere in '
            'the scanned '
            'sources. Either it moved out of the scanned tree — in which case '
            'the guard test is now scanning the wrong directory — or the '
            'store was deleted and this registration is stale.',
      ),
    );
  }

  findings.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G6 — fixture coverage (store registry)',
    subject: subject,
    findings: findings,
    guideSection: '"Adding a migration", step 5; "The six CI guards"',
    whatBroke:
        'A store’s migration list exists in this repo but no guard is '
        'pointed at it.',
    whyTheRuleExists:
        'Guards G1, G2 and G6 are per store. A store nobody registered is a '
        'store all three silently skip, and a green suite that skips a store '
        'is worse than no suite: it is a green suite. This check is the one '
        'that makes adding a database impossible to do quietly.',
    theWayToGreen:
        'Add the store to this repo’s guard test: its migration list, a '
        'schema fingerprint manifest, its CruxDbRecovery declaration, and the '
        'version set of its data-preserving fixtures. Every database in the '
        'suite must also appear in the inventory table in the migration '
        'guide — a database that is not in that table is a bug in one '
        'direction or the other.',
  );
}

final RegExp _migrationListDeclaration = RegExp(
  r'List<CruxMigration>\s+(\w+)\s*=',
);
