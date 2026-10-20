// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Static-guard scanners shared by the four products.
///
/// Each scanner takes the sources as text and returns a `CruxGuardResult`;
/// nothing here calls `test()` or reads the disk. A product keeps a thin test
/// under `test/static/` that lists its own files, its own exemptions with
/// their reasons, and asserts the result is clean and not vacuous:
///
/// ```dart
/// final result = cruxAuditOutlineText(
///   sources: [
///     for (final f in Directory('lib').listSync(recursive: true)
///         .whereType<File>().where((f) => f.path.endsWith('.dart')))
///       CruxGuardSource(path: f.path, source: f.readAsStringSync()),
///   ],
///   exemptions: _outlineExemptions,
/// );
/// expect(result.isClean, isTrue, reason: result.describe());
/// expect(result.filesScanned, greaterThan(100));
/// ```
///
/// - `cruxAuditOutlineText`: the `outline` colour token never colours text.
/// - `cruxAuditUnusedL10nKeys` (with `cruxArbMessageKeys`): every
///   localisation key is read by some code, or retained with a reason.
/// - `cruxAuditRefAfterAwait`: a widget's `ref` is never used after an
///   `await` without a `mounted` check.
/// - `cruxAuditModalGuard`: every `showDialog` / `showModalBottomSheet` /
///   `showGeneralDialog` / `showCruxDialog` runs inside `ModalGuard.run`
///   (a `showCruxDialog` may pass `modalGuardKey:` instead), or is allowed
///   with a reason.
/// - `cruxAuditDismissibleFormDialogs`: a dialog that holds typed input
///   sets `barrierDismissible: false`.
/// - `cruxAuditCruxDesktop` (with `cruxParseDesktopAllowList` and
///   `cruxFormatDesktopAllowList`): no raw Material pattern the Crux Desktop
///   layer replaces (`showDialog`, `AlertDialog`, `SnackBar`,
///   `Icons.more_vert`, `Switch`, the list-tile toggles), outside a call site
///   marked `// crux-desktop: phone-only, <why>` or a per-file allow-list
///   with exact counts.
/// - `cruxAuditPrivateEmptyStates`: no hand-rolled copy of
///   `CruxPanelEmptyState`.
/// - `cruxAuditProcessExit`: no product ends its own process with
///   `dart:io`'s `exit`; it calls `crux_telemetry`'s `cruxExit`, which marks
///   the session's exit clean first.
/// - `cruxFindDialogSites` and `CruxClassIndex`: the dialog-site scan the
///   first two share, for a host's own canaries.
///
/// Every scanner reads the syntax tree, so comments and strings never match,
/// and every exemption or retention list is exact: an entry that matches
/// nothing is a finding.
library;

export 'src/crux_desktop_guard.dart';
export 'src/dialog_sites.dart'
    show
        CruxClassIndex,
        CruxDialogSite,
        cruxFindDialogSites,
        kCruxModalOpeners,
        kCruxTypedInputMarkers;
export 'src/dismissible_form_dialog_guard.dart';
export 'src/guard_types.dart'
    show CruxGuardFinding, CruxGuardResult, CruxGuardSource;
export 'src/modal_guard_guard.dart';
export 'src/outline_text_guard.dart';
export 'src/private_empty_state_guard.dart';
export 'src/process_exit_guard.dart';
export 'src/ref_after_await_guard.dart';
export 'src/unused_l10n_keys_guard.dart';
