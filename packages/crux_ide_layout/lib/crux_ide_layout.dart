// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite dockable IDE-layout shell for the EDACrux suite.
///
/// One `CruxIdeLayout` implementation of the four-region `panes` `IdeLayout`,
/// rendered by every product in the suite. Each app projects its
/// own `PanelLayoutState` onto the `IdePanelLayout` (read) +
/// `IdePanelLayoutSink` (write) adapters; the shared widget owns the
/// `IdeController`, the resizer theme, and the visibility/size sync
/// boilerplate.
///
/// Re-exports `panes`' `PaneSize` and `IdePaneBuilder` so hosts can write their
/// adapters and pane builders without importing `panes` directly.
///
/// Also home to the suite's shared IDE-chrome affordances:
///
/// - `PlatformContextMenu` — the "long-press = right-click" wrapper every
///   product uses for row context menus.
/// - `showCruxInfoSnack` / `showCruxErrorSnack` — the standard feedback
///   snack bars (floating; 4 s info, 6 s error).
/// - `confirmCruxDestructiveAction` — the standard destructive-action
///   confirmation dialog (Cancel left, destructive-styled confirm right).
/// - `CruxSearchDialog` / `CruxSearchResultTile` — the standard Cmd/Ctrl+F
///   search modal shell (debounced query, ↑/↓/Enter keyboard navigation).
/// - `CruxPanelEmptyState` — the standard empty state for a dock panel.
/// - `EscapeDismissible` — Escape-to-close for Dialog-hosted Scaffold
///   screens (whose focus capture otherwise swallows Escape).
/// - `ModalGuard` — process-global re-entrancy guard so a repeated
///   shortcut/click can't stack two copies of an exclusive modal surface.
/// - `CruxHelpLink` — the muted contextual help icon linking a surface to
///   its product-website documentation page.
/// - `CruxFocusRegion` / `CruxFocusRegionScope` — keyboard regions: Tab
///   stays inside a region until it is exhausted, and F6 / Shift+F6 jump
///   between regions. `CruxIdeLayout` makes each of its four panes a region.
/// - `announceCrux` — speaks a status message through the screen reader.
///   The feedback snack bars call it, because the desktop accessibility
///   bridges do not announce live regions.
library;

export 'package:panes/panes.dart' show IdePaneBuilder, PaneSize;

export 'src/crux_ide_layout.dart';
export 'src/crux_ide_layout_theme.dart';
export 'src/crux_search_dialog.dart';
export 'src/escape_dismissible.dart';
export 'src/feedback.dart';
export 'src/focus_regions.dart';
export 'src/help_link.dart';
export 'src/ide_panel_layout.dart';
export 'src/modal_guard.dart';
export 'src/panel_empty_state.dart';
export 'src/platform_context_menu.dart';
