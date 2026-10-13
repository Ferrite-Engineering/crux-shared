// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// A reviewed class whose name looks like an empty state but whose job is
/// not `CruxPanelEmptyState`'s.
@immutable
final class CruxEmptyStateExemption {
  /// Creates an exemption.
  const CruxEmptyStateExemption({
    required this.file,
    required this.className,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The class name.
  final String className;

  /// What the class does that `CruxPanelEmptyState` does not: a welcome
  /// surface, a grid cell fill, a layout that degrades below a panel's size.
  final String reason;
}

/// No hand-rolled copy of `CruxPanelEmptyState`.
///
/// `CruxPanelEmptyState` (`crux_ide_layout`) is the one "nothing to show"
/// widget: a centred, muted message with an optional icon and action, which
/// also describes its region to a screen reader. A local copy drifts from
/// it in style and in accessibility, and the next empty state is as likely
/// to copy the copy as to reach for the shared widget.
///
/// **The rule.** Every class declared in [sources] whose name contains
/// `Empty` or `Placeholder` is a finding unless it is in [exemptions] with
/// its reason. Private classes only, unless [includePublic] is true; a
/// public class is part of a package's surface and is often a deliberate,
/// different widget.
///
/// **What it cannot see.** It reads names. A copy named for something else
/// (`_NothingHere`), and an empty state built inline in a `build` method with
/// no class of its own, are not found; review those by hand.
///
/// **Exact accounting.** An exemption that matches no class is a finding.
/// [CruxGuardResult.matchesSeen] is the number of matching classes,
/// exempted or not.
CruxGuardResult cruxAuditPrivateEmptyStates({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxEmptyStateExemption> exemptions =
      const <CruxEmptyStateExemption>[],
  bool includePublic = false,
}) {
  final exempt = exemptions.toList();
  final used = <int>{};
  final findings = <CruxGuardFinding>[];
  var files = 0;
  var seen = 0;
  for (final file in sources) {
    files++;
    final unit = parseString(
      content: file.source,
      throwIfDiagnostics: false,
    ).unit;
    for (final declaration in unit.declarations) {
      if (declaration is! ClassDeclaration) continue;
      final token = declaration.namePart.typeName;
      final name = token.lexeme;
      if (!includePublic && !name.startsWith('_')) continue;
      if (!name.contains('Empty') && !name.contains('Placeholder')) continue;
      seen++;
      final index = exempt.indexWhere(
        (e) => e.file == file.path && e.className == name,
      );
      if (index >= 0) {
        used.add(index);
        continue;
      }
      findings.add(
        CruxGuardFinding(
          path: file.path,
          line: lineOf(file.source, token.offset),
          detail:
              'class $name looks like a hand-rolled empty state. Use '
              'CruxPanelEmptyState (crux_ide_layout), keeping its message and '
              'icon, or add an exemption saying what it does that the shared '
              'widget does not.',
        ),
      );
    }
  }
  for (var i = 0; i < exempt.length; i++) {
    if (used.contains(i)) continue;
    final e = exempt[i];
    findings.add(
      CruxGuardFinding(
        path: e.file,
        line: 0,
        detail:
            'exemption for ${e.className} matches no class: it was renamed '
            'or removed. Update or remove the entry.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files,
    matchesSeen: seen,
  );
}
