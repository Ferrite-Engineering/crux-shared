// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_guards/src/dialog_sites.dart';
import 'package:crux_guards/src/guard_types.dart';
import 'package:meta/meta.dart';

/// A member whose modal opener holds in-progress input the scanner cannot
/// infer, so it is declared a form by hand.
@immutable
final class CruxKnownFormDialog {
  /// Creates an entry.
  const CruxKnownFormDialog({
    required this.file,
    required this.member,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The enclosing member, as [CruxDialogSite.member] names it.
  final String member;

  /// Why this dialog is a form: a builder that forwards a `Widget`
  /// parameter, a picker, a workflow that holds a selection rather than
  /// text.
  final String reason;
}

/// A member whose form dialog deliberately stays dismissible by a scrim
/// click, and why nothing is lost.
@immutable
final class CruxDismissibleFormAllowance {
  /// Creates an allowance.
  const CruxDismissibleFormAllowance({
    required this.file,
    required this.member,
    required this.reason,
  });

  /// The file, as the sources name it.
  final String file;

  /// The enclosing member, as [CruxDialogSite.member] names it.
  final String member;

  /// Why a stray click cannot discard anything the user typed.
  final String reason;
}

/// A dialog that holds in-progress input sets `barrierDismissible: false`
/// (`isDismissible: false` for a bottom sheet). `showCruxDialog` defaults to
/// dismissible like `showDialog` and is read the same way.
///
/// Workflow and form dialogs close by a deliberate act (Cancel, the close
/// button, Escape), never a stray click on the scrim, which discards what
/// the user typed. Lightweight confirms and read-only viewers may stay
/// dismissible and are not flagged.
///
/// **What counts as a form.** A `showDialog`, `showCruxDialog`,
/// `showModalBottomSheet` or `showGeneralDialog` call is a form when its own
/// text names
/// `TextEditingController`, `TextField` or `TextFormField`, or names a class
/// that does, itself or through the `State` its `createState` builds. Classes
/// are looked up in [sources] and in [classSources] (the open core's `lib/`
/// and the shared packages, where a dialog's widget may be declared); a
/// private name only in the file that uses it. [knownForms] declares the rest
/// by hand.
///
/// **What it cannot see**, and [knownForms] exists for: a builder that
/// forwards a `Widget` parameter instead of naming a class, a form nested
/// two widgets deep, and a picker or workflow that holds a selection rather
/// than text.
///
/// **Exact accounting.** A [knownForms] entry that matches no opener, and an
/// [allowances] entry that matches no dismissible form, are findings.
/// [CruxGuardResult.matchesSeen] is the number of form dialogs found.
CruxGuardResult cruxAuditDismissibleFormDialogs({
  required Iterable<CruxGuardSource> sources,
  Iterable<CruxGuardSource> classSources = const <CruxGuardSource>[],
  Iterable<CruxKnownFormDialog> knownForms = const <CruxKnownFormDialog>[],
  Iterable<CruxDismissibleFormAllowance> allowances =
      const <CruxDismissibleFormAllowance>[],
}) {
  final files = sources.toList();
  final sites = cruxFindDialogSites(files);
  final index = CruxClassIndex(<CruxGuardSource>[...files, ...classSources]);
  final known = knownForms.toList();
  final allowed = allowances.toList();
  final knownUsed = <int>{};
  final allowedUsed = <int>{};
  final findings = <CruxGuardFinding>[];
  var forms = 0;

  for (final site in sites) {
    final knownIndex = known.indexWhere(
      (k) => k.file == site.path && k.member == site.member,
    );
    if (knownIndex >= 0) knownUsed.add(knownIndex);
    final isForm =
        knownIndex >= 0 ||
        site.namesTypedInput ||
        site.referencedTypes.any((t) => index.holdsTypedInput(t, site.path));
    if (!isForm) continue;
    forms++;
    if (!site.dismissible) continue;
    final allowIndex = allowed.indexWhere(
      (a) => a.file == site.path && a.member == site.member,
    );
    if (allowIndex >= 0) {
      allowedUsed.add(allowIndex);
      continue;
    }
    final flag = site.opener == 'showModalBottomSheet'
        ? 'isDismissible'
        : 'barrierDismissible';
    findings.add(
      CruxGuardFinding(
        path: site.path,
        line: site.line,
        detail:
            '${site.opener} in ${site.member} holds in-progress input, but a '
            'stray click on the scrim closes it and discards that input. '
            'Pass `$flag: false`; Cancel, the close button and Escape still '
            'close it.',
      ),
    );
  }
  for (var i = 0; i < known.length; i++) {
    if (knownUsed.contains(i)) continue;
    final k = known[i];
    findings.add(
      CruxGuardFinding(
        path: k.file,
        line: 0,
        detail:
            'known form ${k.member} matches no modal opener: it moved or is '
            'gone. Update or remove the entry, or the dialog stops being '
            'checked.',
      ),
    );
  }
  for (var i = 0; i < allowed.length; i++) {
    if (allowedUsed.contains(i)) continue;
    final a = allowed[i];
    findings.add(
      CruxGuardFinding(
        path: a.file,
        line: 0,
        detail:
            'allowance for ${a.member} matches no dismissible form dialog. '
            'Remove the entry.',
      ),
    );
  }
  return CruxGuardResult(
    findings: findings,
    filesScanned: files.length,
    matchesSeen: forms,
  );
}
