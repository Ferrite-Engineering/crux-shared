// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Strings rendered by `ViewerTabBar` and its tab chips.
///
/// Products supply a subclass that pulls localized strings from their
/// `AppLocalizations` so the widget never bakes in English text. The
/// English-only [ViewerTabBarStringsEn] default is provided so callers can
/// drop the widget into a prototype without wiring localization first.
///
/// All fields are abstract getters so a future ARB-generated implementation
/// can replace the default without changing call sites.
@immutable
abstract class ViewerTabBarStrings {
  /// Const constructor for subclasses.
  const ViewerTabBarStrings();

  /// Tooltip rendered over the per-chip close (×) button.
  String get closeTabTooltip;

  /// Tooltip rendered over the per-chip close (×) button, parameterized by
  /// the tab's display [name]. Products that want a name-bearing tooltip
  /// (e.g. "Close cpu.vcd") override this; the default falls back to the
  /// non-parameterized [closeTabTooltip] so existing implementations are
  /// unaffected.
  String closeTabTooltipFor(String name) => closeTabTooltip;

  /// Tooltip rendered over the trailing "+" new-tab button.
  String get newTabTooltip;

  /// Default display name used when the host product opens an empty new tab
  /// via the trailing "+" button.
  String get newTabDefaultDisplayName;

  /// Fallback rendered in place of a tab's `displayName` when the host
  /// product hands in a blank string.
  String get unnamedTabFallback;

  /// "Reveal in Finder / Explorer / Files" context-menu item. Hosts supply
  /// the platform-resolved label; the default covers English macOS.
  String get revealTabMenuItem => 'Reveal in Finder';

  /// "Close Tab" context-menu item.
  String get closeTabMenuItem;

  /// "Close Other Tabs" context-menu item.
  String get closeOtherTabsMenuItem;

  /// "Close Tabs to the Right" context-menu item.
  String get closeTabsToTheRightMenuItem;

  /// "Move to New Window" context-menu item.
  String get moveToNewWindowMenuItem;

  /// Tooltip shown next to the disabled "Move to New Window" menu item when
  /// `kMultiWindowAvailable` is `false`.
  String get multiWindowUnavailableTooltip;

  /// Accessibility label rendered on the surrounding container of the active
  /// pane so screen readers announce focus changes.
  String get activePaneAccessibilityLabel;

  /// Accessibility hint announced while a tab is being dragged toward
  /// another pane's tab bar.
  String get dragToPaneAccessibilityHint;

  /// Tooltip describing the leading drag handle on each chip.
  String get reorderHandleTooltip;

  /// Tooltip on the chevron that scrolls the tab strip toward its start.
  ///
  /// These two carry a default because they were added after the interface
  /// shipped; every other member is abstract on purpose so a product cannot
  /// silently inherit English. A defaulted member is the compatible way to add
  /// a string to a `ViewerTabBarStrings` implementation that four products
  /// already subclass.
  String get scrollTabsLeftTooltip => 'Scroll tabs left';

  /// Tooltip on the chevron that scrolls the tab strip toward its end.
  String get scrollTabsRightTooltip => 'Scroll tabs right';
}

/// Default English [ViewerTabBarStrings] used when callers do not supply
/// their own. Mirrors the strings that products typically pull from their
/// ARB files.
class ViewerTabBarStringsEn extends ViewerTabBarStrings {
  /// Creates the default English string set.
  const ViewerTabBarStringsEn();

  @override
  String get closeTabTooltip => 'Close tab';

  @override
  String get newTabTooltip => 'New tab';

  @override
  String get newTabDefaultDisplayName => 'New Tab';

  @override
  String get unnamedTabFallback => '(unnamed tab)';

  @override
  String get closeTabMenuItem => 'Close Tab';

  @override
  String get closeOtherTabsMenuItem => 'Close Other Tabs';

  @override
  String get closeTabsToTheRightMenuItem => 'Close Tabs to the Right';

  @override
  String get moveToNewWindowMenuItem => 'Move to New Window';

  @override
  String get multiWindowUnavailableTooltip =>
      'Available when Flutter multi-window reaches stable';

  @override
  String get activePaneAccessibilityLabel => 'Active pane';

  @override
  String get dragToPaneAccessibilityHint =>
      'Drop here to move the tab into this pane';

  @override
  String get reorderHandleTooltip => 'Drag to reorder';
}
