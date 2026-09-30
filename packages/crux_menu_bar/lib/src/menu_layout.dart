// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:meta/meta.dart';

/// Declarative ordering and grouping of a product's menu-bar actions.
///
/// Each [ActionCategory] maps to an ordered list of **groups**; the menu bar
/// renders a separator between consecutive non-empty groups. An empty group
/// (every action in it hidden — e.g. an Enterprise block on an open-core
/// build) collapses away with no dangling separator, and a category whose
/// groups are all empty renders no top-level menu at all.
///
/// The layout is the single source of truth for *order and grouping only*.
/// Which actions are visible, and whether each is enabled, stays with the
/// product's descriptor table — see `CruxDesktopMenuBar.isVisible` and
/// `CruxDesktopMenuBar.isEnabled`.
///
/// ## What must NOT appear in a layout
///
/// [CruxAppMenuActions.settings] and [CruxAppMenuActions.quit] have
/// platform-specific placement the table cannot express (macOS application
/// menu vs. the bottom of the Windows/Linux File menu), so the menu bar places
/// them directly. [CruxAppMenuActions.about] and
/// [CruxAppMenuActions.checkForUpdates] *do* belong in the layout — under
/// `help`, which is their Windows/Linux home — and the macOS renderer hoists
/// them into the application menu.
typedef CruxMenuLayout<A extends Object> = Map<ActionCategory, List<List<A>>>;

/// The four actions whose menu placement is decided by the host platform
/// rather than by a [CruxMenuLayout].
///
/// On **macOS** all four render in the system application menu, in the
/// standard order `About | Check for Updates | Settings | … | Quit`. On
/// **Windows / Linux** [about] and [checkForUpdates] stay wherever the layout
/// puts them (conventionally Help), while [settings] and [quit] fold into the
/// bottom of the File menu — matching VS Code and native desktop behavior.
@immutable
class CruxAppMenuActions<A extends Object> {
  /// Creates the platform-placed application action set.
  const CruxAppMenuActions({
    required this.about,
    required this.settings,
    required this.quit,
    this.checkForUpdates,
  });

  /// `About <Product>` — macOS application menu, otherwise Help.
  final A about;

  /// "Settings…" — macOS application menu (⌘,), otherwise the bottom of File.
  final A settings;

  /// `Quit <Product>` / "Exit" — macOS application menu, otherwise the very
  /// bottom of File.
  final A quit;

  /// "Check for Updates…" — macOS application menu directly under [about],
  /// otherwise Help. Null for a product with no update checker.
  final A? checkForUpdates;

  /// The actions the macOS renderer hoists out of the layout into the
  /// application menu.
  Set<A> get macHoisted => <A>{
    about,
    settings,
    quit,
    if (checkForUpdates != null) checkForUpdates!,
  };

  /// The actions the Windows/Linux renderer folds into the File menu. [about]
  /// and [checkForUpdates] are deliberately absent — they stay in Help.
  Set<A> get desktopFolded => <A>{settings, quit};
}

/// One entry in a rendered menu — either an action or a logical separator.
@immutable
sealed class CruxMenuEntry<A extends Object> {
  const CruxMenuEntry();
}

/// A selectable action entry.
@immutable
final class CruxActionEntry<A extends Object> extends CruxMenuEntry<A> {
  /// Creates an action entry for [action].
  const CruxActionEntry(this.action);

  /// The action this entry invokes.
  final A action;
}

/// A logical separator between two groups of entries.
@immutable
final class CruxSeparatorEntry<A extends Object> extends CruxMenuEntry<A> {
  /// Creates a separator entry.
  const CruxSeparatorEntry();
}

/// A single top-level menu (File, View, …) and its ordered entries.
@immutable
class CruxTopMenu<A extends Object> {
  /// Creates a top-level menu.
  const CruxTopMenu({
    required this.label,
    required this.acceleratorLabel,
    required this.entries,
  });

  /// Plain localized title, used by the macOS native `PlatformMenu`.
  final String label;

  /// Localized title carrying the `&` Alt-accelerator marker, used by the
  /// Windows/Linux `MnemonicMenuBar`.
  final String acceleratorLabel;

  /// The ordered entries, separators included.
  final List<CruxMenuEntry<A>> entries;
}

/// Every action named anywhere in [layout], flattened.
///
/// Products use this in a conformance test: the union of this set and
/// [CruxAppMenuActions.desktopFolded] must equal exactly the set of actions
/// their descriptor table marks menu-visible, so a newly menu-visible action
/// fails the build until it is given a place in the layout.
Set<A> cruxMenuLayoutActions<A extends Object>(CruxMenuLayout<A> layout) => {
  for (final groups in layout.values)
    for (final group in groups) ...group,
};

/// Flattens ordered [groups] into an entry list, dropping actions that fail
/// [visible], dropping the empty groups that result, and inserting a single
/// [CruxSeparatorEntry] between consecutive surviving groups.
List<CruxMenuEntry<A>> cruxEntriesForGroups<A extends Object>(
  List<List<A>> groups,
  bool Function(A) visible,
) {
  final entries = <CruxMenuEntry<A>>[];
  for (final group in groups) {
    final survivors = group.where(visible).toList();
    if (survivors.isEmpty) continue;
    if (entries.isNotEmpty) entries.add(CruxSeparatorEntry<A>());
    entries.addAll(survivors.map(CruxActionEntry<A>.new));
  }
  return entries;
}
