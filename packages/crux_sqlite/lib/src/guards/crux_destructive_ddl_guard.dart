// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_sqlite/src/guards/crux_guard_report.dart';
import 'package:crux_sqlite/src/guards/crux_guard_sources.dart';

/// The waiver marker a destructive statement must carry to be permitted.
///
/// `// MIGRATION-DESTRUCTIVE(<ruling>): <why, and what backs the data up>`
///
/// The marker is not a mute button. It is a pointer at the written decision
/// that permitted the exception, and a marker naming no ruling is as red as no
/// marker at all — a waiver whose justification lives only in the waiver is
/// the same thing as no justification.
const String kCruxDestructiveWaiverMarker = 'MIGRATION-DESTRUCTIVE';

/// How far above a destructive statement its waiver marker may sit.
///
/// Three lines, not "anywhere in the file": a file-level marker would waive
/// statements nobody looked at, including ones added later by somebody who
/// never saw the ruling. The marker has to be adjacent enough that a reviewer
/// reading the statement reads the waiver.
const int kCruxWaiverProximityLines = 3;

/// **Guard G3 — destructive DDL scanner.**
///
/// Scans Dart sources for `DROP TABLE`, `DROP COLUMN`, `RENAME TO`, `RENAME
/// COLUMN` and bare `DELETE FROM` (a `DELETE` with no `WHERE`, i.e. one that
/// empties a table), and requires each to carry a
/// [kCruxDestructiveWaiverMarker] waiver naming a ruling within
/// [kCruxWaiverProximityLines] lines above it.
///
/// **This is the guard that sees what G2 cannot.** G2 compares schema
/// versions, so it can only notice destruction that got a version number. A
/// `DROP TABLE` executed from a repair routine, a startup fixup, or a
/// "recreate the index" helper never appears in any version's schema and is
/// invisible to it — while doing exactly the same thing to the user's file.
///
/// A `DELETE ... WHERE ...` is left alone: bounded deletes are how retention
/// works in both products and there is nothing wrong with them. It is
/// `DELETE FROM <table>` with no predicate — the statement that empties a
/// table — that has to be argued for.
CruxGuardReport cruxAuditDestructiveDdl({
  required Iterable<CruxSourceFile> sources,
  required String subject,
}) {
  final findings = <CruxGuardFinding>[];
  final observations = <CruxGuardFinding>[];

  for (final file in sources) {
    for (final pattern in _patterns) {
      for (final match in pattern.expression.allMatches(file.source)) {
        if (pattern.isExempt?.call(file.source, match) ?? false) continue;
        final waiver = _waiverAbove(file.source, match.start);
        final location = file.locate(match.start);
        final statement = _statementText(file.source, match);
        if (waiver == null) {
          findings.add(
            CruxGuardFinding(
              location: location,
              detail:
                  '${pattern.name}: $statement\n'
                  '        No `// $kCruxDestructiveWaiverMarker(<ruling>): '
                  '<why, and what backs the data up>` marker within '
                  '$kCruxWaiverProximityLines lines above it.',
            ),
          );
        } else if (waiver.ruling.trim().isEmpty) {
          findings.add(
            CruxGuardFinding(
              location: location,
              detail:
                  '${pattern.name}: $statement\n'
                  '        The waiver marker names no ruling: '
                  '`${waiver.text}`. A waiver whose justification lives only '
                  'in the waiver is not a justification.',
            ),
          );
        } else if (waiver.rationale.trim().isEmpty) {
          findings.add(
            CruxGuardFinding(
              location: location,
              detail:
                  '${pattern.name}: $statement\n'
                  '        The waiver names ruling `${waiver.ruling}` but '
                  'says nothing about why, or about what backs the data up. '
                  'Both are required — the second is what a support '
                  'conversation needs.',
            ),
          );
        } else {
          observations.add(
            CruxGuardFinding(
              location: location,
              detail:
                  '${pattern.name}, waived under `${waiver.ruling}`: '
                  '${waiver.rationale}',
            ),
          );
        }
      }
    }
  }

  findings.sort((a, b) => a.location.compareTo(b.location));
  observations.sort((a, b) => a.location.compareTo(b.location));

  return CruxGuardReport(
    guard: 'G3 — destructive DDL scanner',
    subject: subject,
    findings: findings,
    observations: observations,
    guideSection: 'rule 2; "When additive is not enough"',
    whatBroke:
        'A statement that destroys data is present with no waiver naming the '
        'ruling that permitted it.',
    whyTheRuleExists:
        'DROP, RENAME and an unbounded DELETE each remove data that no undo, '
        'no backup policy and no support call reliably brings back. Each is '
        'one line, each reads as tidy-up in review, and the user finds out '
        'much later. Unlike a schema-version check, this scan also catches '
        'destruction that never got a version number at all — a repair '
        'routine, a startup fixup — which is invisible to every other guard '
        'while doing exactly the same thing to the file.',
    theWayToGreen:
        'Remove the statement. If the change genuinely cannot be expressed '
        'additively, write the ruling down first, then mark the statement '
        '`// $kCruxDestructiveWaiverMarker(<ruling>): <why, and what backs '
        'the data up>` on the line(s) immediately above it. A marker with no '
        'ruling, or with no rationale, stays red — the marker is a pointer at '
        'a decision, not a way to silence the check.',
  );
}

final class _Pattern {
  const _Pattern(this.name, this.expression, {this.isExempt});
  final String name;
  final RegExp expression;

  /// Narrows a pattern that would otherwise fire on a legitimate shape. Only
  /// `DELETE` has one, and only for a `DELETE` carrying a `WHERE`.
  final bool Function(String source, RegExpMatch match)? isExempt;
}

/// `DROP INDEX` is deliberately absent: an index carries no data, so dropping
/// one costs a query plan and never a user's history (the same reason G2 does
/// not require index sets to grow).
final List<_Pattern> _patterns = <_Pattern>[
  _Pattern('DROP TABLE', RegExp(r'\bDROP\s+TABLE\b', caseSensitive: false)),
  _Pattern('DROP COLUMN', RegExp(r'\bDROP\s+COLUMN\b', caseSensitive: false)),
  _Pattern(
    'RENAME COLUMN',
    RegExp(r'\bRENAME\s+COLUMN\b', caseSensitive: false),
  ),
  _Pattern('RENAME TO', RegExp(r'\bRENAME\s+TO\b', caseSensitive: false)),
  _Pattern(
    'bare DELETE FROM (no WHERE — empties the table)',
    RegExp(r'\bDELETE\s+FROM\b', caseSensitive: false),
    isExempt: _deleteHasPredicate,
  ),
];

/// A `DELETE` is exempt when the same statement carries a `WHERE`.
///
/// The statement is taken as the text from the `DELETE` up to the first `;`,
/// the end of the enclosing string literal, or 400 characters — whichever
/// comes first. Bounded deletes are how retention works in both products and
/// there is nothing to argue about; it is the unbounded one that empties a
/// table.
bool _deleteHasPredicate(String source, RegExpMatch match) {
  final end = (match.start + 400).clamp(0, source.length);
  final window = source.substring(match.start, end);
  final terminator = window.indexOf(';');
  final statement = terminator < 0 ? window : window.substring(0, terminator);
  return RegExp(r'\bWHERE\b', caseSensitive: false).hasMatch(statement);
}

final class _Waiver {
  const _Waiver({
    required this.text,
    required this.ruling,
    required this.rationale,
  });
  final String text;
  final String ruling;
  final String rationale;
}

final RegExp _waiverExpression = RegExp(
  '$kCruxDestructiveWaiverMarker'
  r'\(([^)]*)\)\s*:?\s*(.*)$',
);

/// The waiver marker on the statement's own line, or within
/// [kCruxWaiverProximityLines] lines above it.
_Waiver? _waiverAbove(String source, int offset) {
  final lines = source.split('\n');
  // 0-based index of the line [offset] falls on.
  final index = '\n'.allMatches(source.substring(0, offset)).length;
  final from = (index - kCruxWaiverProximityLines).clamp(0, lines.length - 1);
  // The statement's own line is included — a trailing marker on the same line
  // is as adjacent as adjacency gets.
  final candidates = lines.sublist(from, index + 1);
  for (final line in candidates.reversed) {
    final match = _waiverExpression.firstMatch(line);
    if (match == null) continue;
    return _Waiver(
      text: match.group(0)!.trim(),
      ruling: match.group(1)!.trim(),
      rationale: match.group(2)!.trim(),
    );
  }
  return null;
}

/// A one-line excerpt of the offending statement, for the failure message.
String _statementText(String source, RegExpMatch match) {
  final end = (match.start + 90).clamp(0, source.length);
  final excerpt = source
      .substring(match.start, end)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return end < source.length ? '$excerpt…' : excerpt;
}
