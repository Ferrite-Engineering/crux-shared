// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// One reviewed use of the `outline` colour token that is not text.
///
/// Pinned to the file, the line and the line's trimmed text, so an edit
/// around it re-flags whatever sits there now instead of carrying the
/// exemption forward to a use nobody has looked at.
@immutable
final class CruxOutlineExemption {
  /// Creates an exemption.
  const CruxOutlineExemption({
    required this.file,
    required this.line,
    required this.expectedTrimmed,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The 1-based line.
  final int line;

  /// The line's text, trimmed.
  final String expectedTrimmed;

  /// Why this use is a border, a stroke, a fill or an icon, and not text.
  final String reason;
}

/// A `ColorScheme`'s `outline` token never colours text.
///
/// `outline` is a Material 3 border token, chosen against the surfaces it
/// separates and never against text-contrast minimums; de-emphasised text
/// uses `onSurfaceVariant`. Without type information a scanner cannot tell a
/// `TextStyle.color` from a `BorderSide.color`, so every member access
/// `.outline` (or `?.outline`) under any receiver is a finding unless it is
/// pinned in [exemptions] with its reason.
///
/// It reads tokens, so a mention in a comment or a string is not a use, and
/// `.outlineVariant` and `Icons.help_outline` never match.
///
/// **Exact accounting.** An exemption that matches no use is a finding too,
/// so the list cannot outlive the code it describes, and [CruxGuardResult.
/// matchesSeen] equals the number of exemptions exactly when the result is
/// clean. That also catches two regressions on one day, which a floor
/// (`seen >= exemptions`) would let through.
CruxGuardResult cruxAuditOutlineText({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxOutlineExemption> exemptions = const <CruxOutlineExemption>[],
}) {
  final pinned = exemptions.toList();
  final used = <int>{};
  final findings = <CruxGuardFinding>[];
  var files = 0;
  var seen = 0;
  for (final file in sources) {
    files++;
    final lines = file.source.split('\n');
    for (final offset in _outlineAccesses(file.source)) {
      seen++;
      final line = lineOf(file.source, offset);
      final trimmed = lines[line - 1].trim();
      final index = pinned.indexWhere(
        (e) =>
            e.file == file.path &&
            e.line == line &&
            e.expectedTrimmed == trimmed,
      );
      if (index >= 0) {
        used.add(index);
        continue;
      }
      findings.add(
        CruxGuardFinding(
          path: file.path,
          line: line,
          detail:
              '`.outline` is a border token, and text coloured with it fails '
              'contrast. Use `onSurfaceVariant` for de-emphasised text; if '
              'this is a border, stroke, fill or icon, pin it as an exemption '
              'with its reason. ($trimmed)',
        ),
      );
    }
  }
  for (var i = 0; i < pinned.length; i++) {
    if (used.contains(i)) continue;
    final e = pinned[i];
    findings.add(
      CruxGuardFinding(
        path: e.file,
        line: e.line,
        detail:
            'exemption matches no `.outline` use (expected '
            '"${e.expectedTrimmed}"). The line moved or the use is gone: '
            'update or remove the entry.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files,
    matchesSeen: seen,
  );
}

/// Offsets of every `.outline` / `?.outline` member access in [source].
Iterable<int> _outlineAccesses(String source) sync* {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  Token? token = unit.beginToken;
  while (token != null && token.type != TokenType.EOF) {
    final next = token.next;
    if ((token.type == TokenType.PERIOD ||
            token.type == TokenType.QUESTION_PERIOD) &&
        next != null &&
        next.lexeme == 'outline') {
      yield next.offset;
    }
    token = next;
  }
}
