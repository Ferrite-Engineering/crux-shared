// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/src/dialog_sites.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// One member whose modal openers deliberately run outside
/// `ModalGuard.run`, and why they cannot be fired twice.
@immutable
final class CruxModalGuardAllowance {
  /// Creates an allowance.
  const CruxModalGuardAllowance({
    required this.file,
    required this.member,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The enclosing member, as [CruxDialogSite.member] names it.
  final String member;

  /// Why nothing can re-fire this opener while its surface is opening: for
  /// example, its only control sits behind the surface's own barrier, or a
  /// popup menu that closes on selection.
  final String reason;
}

/// Every modal opener runs inside `ModalGuard.run(...)`, or is allowed with a
/// reason.
///
/// A product's global `Shortcuts` / `Actions` layer sits above the
/// `Navigator`, so a chord pressed twice, key repeat, or a double-clicked menu
/// item dispatches an opener again while its first surface is still opening,
/// and stacks a second copy. `ModalGuard` (`crux_ide_layout`) makes an opener
/// idempotent for the life of its surface.
///
/// **One rule, default-guarded.** Whether an opener is reachable from a
/// shortcut, a menu or the command palette is a whole-program question (an
/// action dispatched in the open core, an opener provider overridden in the
/// Pro overlay, a closure on a button), and no syntactic scan answers it.
/// So every `showDialog`, `showModalBottomSheet`, `showGeneralDialog` and
/// `showCruxDialog` call must sit inside the arguments of a `ModalGuard.run`
/// call in the same file, or its enclosing member must be in [allowances]
/// with the argument for why it cannot be re-fired. A `showCruxDialog` call
/// may instead pass `modalGuardKey:` (anything but the literal `null`): the
/// helper then runs itself inside `ModalGuard.run` under that key.
///
/// **What it cannot see.** An opener in a helper that is only called from
/// inside a guard reads as unguarded: put the `showDialog` inside the guard
/// lambda, which is also what makes the guard visible to a reader. A dialog
/// opened by a shared helper (`confirmCruxDestructiveAction`) is not a call
/// this scanner sees, so such a member needs no allowance and gets no check.
///
/// **Exact accounting.** An allowance whose member has no unguarded opener
/// is a finding, so the list cannot outlive the code. [CruxGuardResult.
/// matchesSeen] is the number of opener calls.
CruxGuardResult cruxAuditModalGuard({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxModalGuardAllowance> allowances =
      const <CruxModalGuardAllowance>[],
}) {
  final files = sources.toList();
  final sites = cruxFindDialogSites(files);
  final allowed = allowances.toList();
  final used = <int>{};
  final findings = <CruxGuardFinding>[];
  for (final site in sites) {
    if (site.guarded) continue;
    final index = allowed.indexWhere(
      (a) => a.file == site.path && a.member == site.member,
    );
    if (index >= 0) {
      used.add(index);
      continue;
    }
    final fix = site.opener == 'showCruxDialog'
        ? "Pass modalGuardKey: '<key>'"
        : "Wrap it: ModalGuard.run('<key>', () => ${site.opener}(...))";
    findings.add(
      CruxGuardFinding(
        path: site.path,
        line: site.line,
        detail:
            '${site.opener} in ${site.member} is not inside ModalGuard.run, '
            'so a repeated chord, key repeat or double-clicked menu item can '
            'stack a second copy. $fix. If nothing can re-fire it, add an '
            'allowance for ${site.key} with the reason.',
      ),
    );
  }
  for (var i = 0; i < allowed.length; i++) {
    if (used.contains(i)) continue;
    final a = allowed[i];
    findings.add(
      CruxGuardFinding(
        path: a.file,
        line: 0,
        detail:
            'allowance for ${a.member} matches no unguarded opener: it is '
            'gone, renamed or now guarded. Remove the entry.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files.length,
    matchesSeen: sites.length,
  );
}
