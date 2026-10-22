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
///   messages: toasts on desktop, floating snack bars on phone and tablet.
/// - `confirmCruxDestructiveAction` — the standard destructive-action
///   confirmation, a `CruxDialog` (Cancel first and focused, the
///   destructive-styled confirm after it).
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
/// - `showCruxReloadPrompt` / `hideCruxReloadPrompt` — the source-changed
///   prompt every product shows when a watched file changes: a banner with
///   Ignore and a reload action, which stays until the user chooses.
/// - `announceCrux` — speaks a status message through the screen reader.
///   The feedback snack bars call it, because the desktop accessibility
///   bridges do not announce live regions.
/// - `CruxDockRestoreFrame` — the fixed, keyed frame that places the
///   collapsed-region restore bars around the IDE layout without ever
///   changing the widget type above it, so a dock toggle rebuilds nothing
///   beneath.
///
/// And the Crux Desktop components every desktop surface is built from:
///
/// - `showCruxDialog` / `CruxDialog` / `CruxDialogAction` — the one way a
///   dialog opens and the one frame it draws: Escape closes, Enter runs the
///   default action, a destructive variant keeps focus on the safe choice,
///   the size is clamped to the window, and `ModalGuard` is a parameter.
/// - The toast stack behind `showCruxInfoSnack` / `showCruxErrorSnack` on
///   desktop (bottom-right above the status bar, one visible, errors stay
///   until closed), `hideCruxSnack`, and `CruxToastCard`.
/// - `CruxOverflowMenu` / `CruxContextMenuRegion` / `showCruxContextMenu`
///   — the "⋯" button and the same commands on right-click, Shift+F10 and
///   the Menu key; `CruxSubmenu` cascades a second menu from one item.
/// - `cruxTextInputFocused` — whether a text field holds focus, for a
///   window-level shortcut that must leave the keystroke to the field.
/// - `CruxSegmentedControl` / `CruxSegment` — one choice of a few, one Tab
///   stop with arrow keys between segments and a focus ring per segment.
/// - `CruxPopUpButton` / `CruxPopUpItem` / `CruxPopUpFormField` — one
///   choice of a list in a menu: the desktop replacement for
///   `DropdownButton` and `DropdownButtonFormField`.
/// - `CruxDesktopTokens` — the layout tokens a Crux Desktop theme carries;
///   their presence is how the helpers above know they are on desktop.
/// - `CruxChromeColors` — the chrome colours Material has no slot for,
///   which `crux_theme`'s `applyChromeTokens` resolves.
library;

export 'package:panes/panes.dart' show IdePaneBuilder, PaneSize;

export 'src/crux_chrome_colors.dart';
export 'src/crux_desktop_tokens.dart';
export 'src/crux_dialog.dart' hide kCruxDialogDefaultWidth, kCruxDialogGutter;
export 'src/crux_ide_layout.dart' hide kCruxPaneResizeStep;
export 'src/crux_ide_layout_theme.dart';
export 'src/crux_overflow_menu.dart';
export 'src/crux_pop_up_button.dart';
export 'src/crux_search_dialog.dart'
    hide kCruxSearchDialogRowExtent, kCruxSearchDialogSize;
export 'src/crux_segmented_control.dart';
export 'src/crux_toast.dart' show CruxToastAction, CruxToasts;
export 'src/dock_restore_frame.dart';
export 'src/escape_dismissible.dart';
export 'src/feedback.dart';
export 'src/focus_regions.dart' hide CruxFocusRegionState;
export 'src/help_link.dart';
export 'src/ide_panel_layout.dart';
export 'src/modal_guard.dart';
export 'src/panel_empty_state.dart';
export 'src/platform_context_menu.dart';
export 'src/pushed_route.dart';
export 'src/reload_prompt.dart';
export 'src/text_input_focus.dart';
