// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-visible copy for the multi-project chrome.
///
/// Per crux-shared convention this package carries **no ARB**: every host
/// supplies its own localized strings through an adapter so the copy is
/// translated once, in the product that owns the glossary, rather than
/// duplicated per package. Same shape as `CruxUpdateStrings`.
abstract class CruxProjectsUiStrings {
  /// Switcher dialog title.
  String get switcherTitle;

  /// Tooltip on the switcher's close button.
  String get switcherDismissTooltip;

  /// Placeholder in the switcher's filter field.
  String get switcherSearchHint;

  /// Heading above the open-projects section.
  String get switcherSectionOpen;

  /// Heading above the recently-closed section.
  String get switcherSectionRecent;

  /// Shown when no projects are open.
  String get switcherEmptyOpen;

  /// Shown when the recents list is empty.
  String get switcherEmptyRecent;

  /// Shown when a filter matches nothing.
  String get switcherEmptySearch;

  /// Per-row action that closes an open project.
  String get switcherActionClose;

  /// Per-row action that removes a recent entry.
  String get switcherActionForget;

  /// Chip marking the active project.
  String get switcherActiveIndicator;

  /// Footer entry that hands off to cross-project search. Only rendered
  /// when the host installs a [crossProjectSearchOpenerProvider].
  String get switcherFooterSearchAcrossProjects;

  /// Recents panel title.
  String get recentsPanelTitle;

  /// Recents panel empty state.
  String get recentsPanelEmpty;

  /// Recents panel per-row reopen action.
  String get recentsPanelReopen;

  /// Recents panel per-row forget action.
  String get recentsPanelForget;
}

/// The active [CruxProjectsUiStrings].
///
/// Unbound by default: the widgets are useless without copy, and a
/// silent English fallback would ship untranslated UI to every non-English
/// user without anyone noticing.
final Provider<CruxProjectsUiStrings> cruxProjectsUiStringsProvider =
    Provider<CruxProjectsUiStrings>((ref) {
      throw StateError(
        'cruxProjectsUiStringsProvider is unbound. The host application '
        'must override it with a localized CruxProjectsUiStrings adapter '
        'before mounting any crux_projects_ui widget.',
      );
    });

/// Builds the tier badge rendered beside the switcher / recents headings.
///
/// The multi-project registry is a paid feature in every product that has
/// one, but each product ships its own badge widget (brand accent, label).
/// Returning `null` renders no badge — correct for a host with no tier
/// system.
typedef CruxProjectsUiBadgeBuilder = Widget? Function(BuildContext context);

/// The active badge builder. Defaults to no badge.
final Provider<CruxProjectsUiBadgeBuilder> cruxProjectsUiBadgeBuilderProvider =
    Provider<CruxProjectsUiBadgeBuilder>(
      (ref) =>
          (_) => null,
    );

/// Opens the host's cross-project search surface.
///
/// `null` (the default) hides the switcher's footer entry entirely rather
/// than rendering a button that does nothing — a product without
/// cross-project search should not advertise it.
typedef CruxCrossProjectSearchOpener = void Function(BuildContext context);

/// The active cross-project search opener, or `null`.
final Provider<CruxCrossProjectSearchOpener?> crossProjectSearchOpenerProvider =
    Provider<CruxCrossProjectSearchOpener?>((ref) => null);
