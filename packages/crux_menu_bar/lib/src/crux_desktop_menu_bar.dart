// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/src/menu_layout.dart';
import 'package:crux_menu_bar/src/menu_shortcut.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The one desktop menu bar every EDACrux product renders.
///
/// ## Two renderers, one model
///
/// The menu structure — which top-level menus exist, the order of their items,
/// and where the dividers fall — is built once from the declarative
/// [CruxMenuLayout], then rendered one of two ways depending on the host OS:
///
/// - **macOS** → [PlatformMenuBar], the *system* menu bar at the top of the
///   screen. Flutter's `DefaultPlatformMenuDelegate` only bridges to the native
///   menu on macOS. Logical groups become [PlatformMenuItemGroup]s (the OS
///   draws the separator).
/// - **Windows / Linux** → a Material [MenuBar] rendered *in-window* inside the
///   VS Code-style custom title bar from `crux_window_chrome`.
///   `PlatformMenuBar` is a silent no-op on these platforms. Logical groups
///   become [Divider]s.
///
/// ## Where each action appears
///
/// Membership and enablement come entirely from the product's descriptor
/// table, via [isVisible] and [isEnabled]. Order and grouping come from
/// [layout]. The two are kept in lock-step by a per-product conformance test
/// built on [cruxMenuLayoutActions].
///
/// ## Platform conventions (calibrated against VS Code)
///
/// On macOS the FIRST menu becomes the system application menu (the OS renames
/// it to the bundle name) and hosts
/// `About | Check for Updates | Settings | Services/Hide/… | Quit`, each in its
/// own separator group, followed by a standard **Window** menu before Help. On
/// Windows / Linux there is no branded leading menu: **Settings** and
/// **Quit/Exit** fold into the bottom of **File**, and **About** /
/// **Check for Updates** stay in **Help**.
///
/// ## Gating
///
/// Desktop-only. On platforms with no menu bar (iOS, Android, web) the widget
/// returns [child] directly, and products fall back to their toolbar overflow
/// menu. Hosts must **not** additionally gate this widget on window size: on
/// Windows/Linux the frameless window's title bar and its min/maximize/close
/// caption buttons are drawn here, so suppressing it would leave the user with
/// no way to close the window. Use [enabled] only for a genuine
/// platform-capability gate.
class CruxDesktopMenuBar<A extends Object> extends StatelessWidget {
  /// Creates the shared desktop menu bar.
  const CruxDesktopMenuBar({
    required this.layout,
    required this.appActions,
    required this.categoryLabel,
    required this.categoryAcceleratorLabel,
    required this.windowMenuLabel,
    required this.labelOf,
    required this.shortcutOf,
    required this.isVisible,
    required this.isEnabled,
    required this.onAction,
    required this.logo,
    required this.child,
    this.editionLine,
    this.enabled = true,
    super.key,
  });

  /// A one-line statement of the edition in force and who it is licensed to,
  /// rendered as a **disabled first item** in the macOS application menu, above
  /// `About <Product>`.
  ///
  /// Null renders nothing at all — which is the Open Core case, and the case on
  /// every platform other than macOS. Windows and Linux have no application
  /// menu to put this in; the window's edition badge is the surface there, and
  /// that is a platform difference rather than a gap.
  ///
  /// **Why the application menu rather than its title.** The macOS menu-bar
  /// application title IS `CFBundleName`, so appending an edition to it would
  /// recreate exactly the problem of a build-time constant claiming a runtime
  /// tier. This item is adjacent to that title, says the same thing, and can
  /// change with the licence.
  ///
  /// Disabled on purpose: it is a statement, not an action. A null
  /// `onSelected` is how `PlatformMenuItem` renders greyed out.
  final String? editionLine;

  /// Declarative order and grouping of this product's menu actions.
  final CruxMenuLayout<A> layout;

  /// The platform-placed About / Check for Updates / Settings / Quit actions.
  final CruxAppMenuActions<A> appActions;

  /// Localized plain title for a category (macOS `PlatformMenu`).
  final String Function(ActionCategory) categoryLabel;

  /// Localized title with the `&` mnemonic marker (Windows/Linux menu bar).
  final String Function(ActionCategory) categoryAcceleratorLabel;

  /// Localized title of the macOS-only standard **Window** menu.
  final String windowMenuLabel;

  /// Localized display label for an action, tier suffix included.
  final String Function(A) labelOf;

  /// The user's current binding for an action, or null when unbound.
  final ShortcutActivator? Function(A) shortcutOf;

  /// Whether an action structurally appears in the menu surface right now.
  final bool Function(A) isVisible;

  /// Whether an action is currently invocable. A visible-but-disabled action
  /// renders greyed out rather than disappearing, so the menu keeps a stable
  /// shape and stays discoverable.
  final bool Function(A) isEnabled;

  /// Invoked when the user selects a menu item.
  final void Function(A) onAction;

  /// The product logo shown at the far left of the Windows/Linux title bar.
  final Widget logo;

  /// The widget tree below the menu bar.
  final Widget child;

  /// Host-supplied capability gate. When false the widget returns [child]
  /// unchanged. Do not wire this to window size — see the class docs.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final platformHostsMenuBar =
        !kIsWeb &&
        (platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows);
    if (!enabled || !platformHostsMenuBar) return child;

    return platform == TargetPlatform.macOS
        ? _buildMacOS(context)
        : _buildInWindow(context);
  }

  // ── macOS: native PlatformMenuBar ──────────────────────────────────────────

  Widget _buildMacOS(BuildContext context) {
    // A null `onSelected` is how PlatformMenuItem renders greyed out.
    PlatformMenuItem item(A action) => PlatformMenuItem(
      label: labelOf(action),
      shortcut: nativeMenuShortcut(shortcutOf(action)),
      onSelected: isEnabled(action) ? () => onAction(action) : null,
    );

    final hoisted = appActions.macHoisted;
    bool visibleInCategory(A action) =>
        !hoisted.contains(action) && isVisible(action);

    final windowMenu = _macWindowMenu();

    final menus = <PlatformMenuItem>[
      // The first menu becomes the system application menu; the OS replaces
      // the label with the bundle name, so the value here is only a fallback.
      PlatformMenu(
        label: categoryLabel(ActionCategory.app),
        menus: [
          // The edition statement sits above About, in its own group, and is
          // deliberately not selectable.
          if (editionLine case final String line)
            PlatformMenuItemGroup(
              members: [PlatformMenuItem(label: line)],
            ),
          PlatformMenuItemGroup(members: [item(appActions.about)]),
          if (appActions.checkForUpdates case final A updates)
            PlatformMenuItemGroup(members: [item(updates)]),
          PlatformMenuItemGroup(members: [item(appActions.settings)]),
          ..._providedGroups(const [
            [PlatformProvidedMenuItemType.servicesSubmenu],
            [
              PlatformProvidedMenuItemType.hide,
              PlatformProvidedMenuItemType.hideOtherApplications,
              PlatformProvidedMenuItemType.showAllApplications,
            ],
          ]),
          // The product's own Quit action rather than
          // PlatformProvidedMenuItemType.quit, so the host's quit handler runs
          // and flushes workspace state before the process exits.
          PlatformMenuItemGroup(members: [item(appActions.quit)]),
        ],
      ),
      for (final category in ActionCategory.values)
        if (category != ActionCategory.app)
          ...() {
            final entries = cruxEntriesForGroups(
              layout[category] ?? <List<A>>[],
              visibleInCategory,
            );
            if (entries.isEmpty) return const <PlatformMenuItem>[];
            // The standard macOS Window menu sits immediately before Help.
            return <PlatformMenuItem>[
              if (category == ActionCategory.help && windowMenu != null)
                windowMenu,
              PlatformMenu(
                label: categoryLabel(category),
                menus: _macChildren(entries, item),
              ),
            ];
          }(),
    ];

    return PlatformMenuBar(menus: menus, child: child);
  }

  /// The standard macOS Window menu, or null when the host provides none of
  /// its items.
  PlatformMenu? _macWindowMenu() {
    final groups = _providedGroups(const [
      [
        PlatformProvidedMenuItemType.minimizeWindow,
        PlatformProvidedMenuItemType.zoomWindow,
      ],
      [PlatformProvidedMenuItemType.toggleFullScreen],
    ]);
    if (groups.isEmpty) return null;
    return PlatformMenu(label: windowMenuLabel, menus: groups);
  }

  /// Wraps each non-empty run of *available* provided-menu types in its own
  /// [PlatformMenuItemGroup].
  ///
  /// [PlatformProvidedMenuItem] throws when instantiated for a type the host
  /// platform does not supply, and it keys off `defaultTargetPlatform` — the
  /// real host — not the theme's [TargetPlatform]. So a build that reaches the
  /// macOS branch via a themed platform override (widget tests, and a themed
  /// preview on another OS) must not construct these blind.
  static List<PlatformMenuItemGroup> _providedGroups(
    List<List<PlatformProvidedMenuItemType>> groups,
  ) => [
    for (final group in groups)
      if (group.where(PlatformProvidedMenuItem.hasMenu).toList()
          case final available when available.isNotEmpty)
        PlatformMenuItemGroup(
          members: [
            for (final type in available) PlatformProvidedMenuItem(type: type),
          ],
        ),
  ];

  /// Splits [entries] into separator-delimited runs. A single run is emitted
  /// bare; multiple runs each become a [PlatformMenuItemGroup] so the OS draws
  /// a divider between them.
  static List<PlatformMenuItem> _macChildren<A extends Object>(
    List<CruxMenuEntry<A>> entries,
    PlatformMenuItem Function(A) item,
  ) {
    final runs = <List<PlatformMenuItem>>[<PlatformMenuItem>[]];
    for (final entry in entries) {
      switch (entry) {
        case CruxSeparatorEntry<A>():
          runs.add(<PlatformMenuItem>[]);
        case CruxActionEntry<A>(:final action):
          runs.last.add(item(action));
      }
    }
    final nonEmpty = runs.where((r) => r.isNotEmpty).toList();
    if (nonEmpty.length <= 1) {
      return nonEmpty.isEmpty ? const <PlatformMenuItem>[] : nonEmpty.first;
    }
    return [for (final run in nonEmpty) PlatformMenuItemGroup(members: run)];
  }

  // ── Windows / Linux: in-window Material MenuBar ────────────────────────────

  Widget _buildInWindow(BuildContext context) {
    MenuItemButton item(A action) => MenuItemButton(
      onPressed: isEnabled(action) ? () => onAction(action) : null,
      shortcut: displayMenuShortcut(shortcutOf(action)),
      child: Text(labelOf(action)),
    );

    final folded = appActions.desktopFolded;
    bool visibleInCategory(A action) =>
        !folded.contains(action) && isVisible(action);

    final entriesByCategory = <ActionCategory, List<CruxMenuEntry<A>>>{};
    for (final category in ActionCategory.values) {
      if (category == ActionCategory.app) continue;
      final entries = cruxEntriesForGroups(
        layout[category] ?? <List<A>>[],
        visibleInCategory,
      );
      // Settings and Quit fold into the bottom of File, each its own group.
      if (category == ActionCategory.file) {
        final tail = cruxEntriesForGroups(
          <List<A>>[
            [appActions.settings],
            [appActions.quit],
          ],
          isVisible,
        );
        if (tail.isNotEmpty) {
          if (entries.isNotEmpty) entries.add(CruxSeparatorEntry<A>());
          entries.addAll(tail);
        }
      }
      if (entries.isNotEmpty) entriesByCategory[category] = entries;
    }

    final menuBar = MnemonicMenuBar(
      entries: [
        for (final MapEntry(key: category, value: entries)
            in entriesByCategory.entries)
          MnemonicMenuEntry(
            acceleratorLabel: categoryAcceleratorLabel(category),
            menuChildren: [
              for (final entry in entries)
                switch (entry) {
                  CruxSeparatorEntry<A>() => const Divider(height: 1),
                  CruxActionEntry<A>(:final action) => item(action),
                },
            ],
          ),
      ],
    );

    // Reaching here means a Windows/Linux desktop, which is exactly where the
    // build draws its own frameless chrome: app logo at the left, menus next
    // to it, then the min/maximize/close caption buttons.
    return buildWindowChrome(menuBar: menuBar, logo: logo, child: child);
  }
}
