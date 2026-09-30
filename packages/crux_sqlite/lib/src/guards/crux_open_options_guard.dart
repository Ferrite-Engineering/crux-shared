// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';

/// **Guard G5 — open-options conformance.**
///
/// Every hand-constructed `OpenDatabaseOptions` that passes `version:` must
/// also pass `onDowngrade:` and must set `busy_timeout` from `onConfigure:`.
///
/// Today no product constructs one: `CruxSqliteOpenPolicy.buildOptions` is
/// total, with no parameter that can omit either. **So this guard is not
/// written to catch today — it is written to catch the next hand-rolled
/// open**, the one somebody writes at 6pm because the shared policy did not
/// quite fit. Both halves of what it checks are live fuses:
///
///  * **No `onDowngrade`** does not give you a throw. It gives you silence:
///    sqflite skips the version callbacks and calls `setVersion` anyway,
///    stamping `user_version` DOWN. The next new-build launch then re-runs a
///    migration against a schema that already has it — `duplicate column
///    name`, on every open, permanently, with no recovery path.
///  * **No `busy_timeout`** means a concurrent opener that meets a held lock
///    gets `SQLITE_BUSY` immediately, no retry, no back-off. That surfaces as
///    a `DatabaseException`, which at a naive catch site is indistinguishable
///    from a corrupt file — and the handler written for a corrupt file
///    deletes it.
///
/// It reports a second thing without failing on it: every `openDatabase(...)`
/// call that does not go through `CruxSqliteOpenPolicy.open`. Those are not
/// wrong — a store may legitimately build options through the policy and open
/// them itself — but each one is a place where the policy's *path handling and
/// recovery* do not apply, so the set of them is worth pinning. Pass the ones
/// you know about in [expectedDirectOpenFiles]; anything else is red, which
/// makes a new bypass a review conversation instead of a discovery.
CruxGuardReport cruxAuditOpenOptions({
  required Iterable<CruxSourceFile> sources,
  required String subject,
  Set<String> expectedDirectOpenFiles = const <String>{},
}) {
  final findings = <CruxGuardFinding>[];
  final observations = <CruxGuardFinding>[];
  final seenDirectOpenFiles = <String>{};

  for (final file in sources) {
    for (final match in _optionsConstruction.allMatches(file.source)) {
      final args = cruxBalancedParens(file.source, match.end - 1);
      if (args == null) continue;
      if (!_hasArgument(args, 'version')) continue;
      final missing = <String>[
        if (!_hasArgument(args, 'onDowngrade')) 'onDowngrade:',
        if (!_setsBusyTimeout(args)) 'busy_timeout (via onConfigure:)',
      ];
      if (missing.isEmpty) continue;
      findings.add(
        CruxGuardFinding(
          location: file.locate(match.start),
          detail:
              'a hand-built OpenDatabaseOptions passes `version:` but not '
              '${missing.join(' and ')}.',
        ),
      );
    }

    for (final match in _openDatabaseCall.allMatches(file.source)) {
      final receiver = match.group(1) ?? '';
      // `policy.open(path)` / `_openPolicy.open(...)` is the sanctioned route
      // and is not an `openDatabase` call at all; what this finds is
      // `<factory>.openDatabase(...)`.
      if (receiver.contains('Policy') || receiver.contains('policy')) continue;
      seenDirectOpenFiles.add(file.path);
      final expected = expectedDirectOpenFiles.any(
        (e) => file.path.endsWith(e) || e.endsWith(file.path),
      );
      final finding = CruxGuardFinding(
        location: file.locate(match.start),
        detail: expected
            ? 'opens the database directly rather than through '
                  'CruxSqliteOpenPolicy.open — pinned, so the policy builds '
                  'the options here but does not absolutise the path or apply '
                  'a recovery.'
            : 'opens the database directly rather than through '
                  'CruxSqliteOpenPolicy.open, and is not in the pinned set. '
                  'The options may still be conforming, but the path is not '
                  'absolutised and no recovery policy applies to this open.',
      );
      (expected ? observations : findings).add(finding);
    }
  }

  for (final expected in expectedDirectOpenFiles) {
    final matched = seenDirectOpenFiles.any(
      (p) => p.endsWith(expected) || expected.endsWith(p),
    );
    if (matched) continue;
    findings.add(
      CruxGuardFinding(
        location: 'pinned direct-open $expected',
        detail:
            'no direct openDatabase call found there any more. If it now '
            'opens through CruxSqliteOpenPolicy.open, remove this pin — the '
            'set is meant to shrink.',
      ),
    );
  }

  findings.sort((a, b) => a.location.compareTo(b.location));
  observations.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G5 — open-options conformance',
    subject: subject,
    findings: findings,
    observations: observations,
    guideSection: 'rule 3; "Concurrency and version skew"',
    whatBroke:
        'A database is opened with options this suite does not consider safe, '
        'or from a site nobody has signed off.',
    whyTheRuleExists:
        'Omitting `onDowngrade` is not a missing nicety, it is a live fuse: '
        'sqflite stamps user_version DOWNWARD in silence, and the next launch '
        'of the newer build re-runs a migration against a schema that already '
        'has it — failing on every open from then on, with no recovery path. '
        'Omitting `busy_timeout` turns ordinary lock contention into an '
        'exception a naive handler cannot tell from a corrupt file, which is '
        'how a merely busy database once got deleted.',
    theWayToGreen:
        'Do not build OpenDatabaseOptions by hand. Open through '
        'CruxSqliteOpenPolicy — supply a migration list, a data-value '
        'declaration and a path, and get a conforming open. Its buildOptions '
        'is total: there is no argument that omits onDowngrade or the '
        'busy_timeout, so a non-conforming options object is not expressible. '
        'If the policy genuinely cannot express what a store needs, that is a '
        'bug in crux_sqlite to fix, not a reason for a second open path.',
  );
}

final RegExp _optionsConstruction = RegExp(r'\bOpenDatabaseOptions\s*\(');

final RegExp _openDatabaseCall = RegExp(r'(\w+)\s*\.\s*openDatabase\s*\(');

bool _hasArgument(String args, String name) =>
    RegExp('(^|[(,\\s])$name\\s*:').hasMatch(args);

bool _setsBusyTimeout(String args) =>
    RegExp('busy_timeout', caseSensitive: false).hasMatch(args) &&
    _hasArgument(args, 'onConfigure');
