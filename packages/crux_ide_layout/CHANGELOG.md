# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## Unreleased

- `showCruxDialog` takes an optional `navigator:`: the dialog is pushed on
  that navigator (a tab's own, from crux_workspace) instead of the one
  `context` finds.
- `CruxSubmenu`: a menu item that opens a second menu beside itself (click,
  Enter or Right arrow). `CruxMenuItem` gains an optional `tooltip`.
- `cruxTextInputFocused()`: whether a text field holds focus, for a
  window-level shortcut that must leave the key to the field.
- An error toast's close button is now a Tab stop from inside a modal
  dialog too: the toast's focus follows the scope the user is tabbing in.
- `showCruxInfoSnack` / `showCruxErrorSnack` take an optional `action`
  (`CruxToastAction`: label and callback): a text button in the toast,
  reachable with Tab, announced after the message, closing the toast when
  chosen. An info toast with an action stays for `kCruxActionSnackDuration`
  (8 s) and never leaves while hovered or focused. Phone and tablet: a
  `SnackBarAction`. `CruxToastCard` gains `action` / `onAction`.

- **Crux Desktop components.** `showCruxDialog` (showDialog's named
  parameters plus `modalGuardKey`; Escape always closes) and `CruxDialog` /
  `CruxDialogAction` (title, body, action row, Enter for the default action,
  a destructive role, focus moved in on open, size clamped to the window).
  `confirmCruxDestructiveAction` is rebuilt on them: Cancel is now an
  outlined button holding focus, the confirm is still the error-coloured
  `FilledButton`. `CruxOverflowMenu` ("⋯"), `CruxContextMenuRegion`
  (right-click, Shift+F10, the Menu key) and `showCruxContextMenu` over one
  `CruxMenuEntry` list. `CruxDesktopTokens`, the theme extension whose
  presence marks a Crux Desktop theme.
- **`showCruxInfoSnack` / `showCruxErrorSnack` are toasts on desktop.** Under
  a theme carrying `CruxDesktopTokens` they show a `CruxToastCard`
  bottom-right above the status bar in the root overlay: one at a time, the
  newest replacing it, info gone after `kCruxInfoSnackDuration`, an error
  staying until closed. Without the tokens (phone, tablet, and every product
  not yet on `cruxDesktopTheme`) they are the same snack bars as before.
  Both take an optional `key`; `hideCruxSnack` removes the one showing.
- **`CruxChromeColors` moved here from `crux_theme`**, which re-exports it,
  and this package no longer depends on `crux_theme`. The edge now runs
  `crux_theme` -> `crux_ide_layout`, so the theme widgets can open
  `showCruxDialog` and the toasts. The chrome-token layout test moved to
  `crux_theme` with it.

- `showCruxReloadPrompt` / `hideCruxReloadPrompt`: the source-changed prompt
  every product shows when a watched file changes and auto-reload is set to
  prompt. A `MaterialBanner` with the product's message, Ignore, then the
  reload action; it stays until the user chooses, a second call while it is
  up does nothing, and the message is announced to screen readers. Three
  products had shown a snackbar whose only button was the reload, which
  never timed out and could not be declined (crux-shared#35).

- `CruxPanelEmptyState` describes its region. A named `CruxFocusRegion` is
  now a `CruxRegionHintHost`, and the empty state mounts a `CruxRegionHint`
  with its message, so while a panel is empty its region keeps its title as
  its name and gains the message as its description (semantics hint and
  tooltip). The visible message keeps its own node for browse mode.
  `crux_a11y` moves from a dev dependency to a dependency.

- `CruxDockRestoreFrame`: the fixed frame that places up to three
  collapsed-region restore bars around the IDE layout, always as
  `Row(leftBar?, Expanded(Column(Expanded(child), bottomBar?)), rightBar?)`
  with keyed slots (`leftBarKey`, `rightBarKey`, `bottomBarKey`,
  `centerKey`). Four products carried this frame, and all four once chose
  the wrapper widget by which regions were collapsed, so every dock toggle
  changed the widget type above the IDE layout and Flutter rebuilt every
  dock, the pane scope, the show/hide animation and the dock scroll
  positions beneath it; in one product a `GlobalKey`'d canvas then crossed a
  fresh semantics boundary and tripped a `flushSemantics` assertion under a
  screen reader. The bars arrive built, so the frame has no dock dependency
  and each product keeps the widget that owns its entries. A test pins the
  invariant: toggling any bar keeps the layout's element and state.
- The pane resizers follow the theme's `splitter` (at rest) and
  `splitter.hover` (hovered, dragged or focused) chrome tokens, read from
  `crux_theme`'s `CruxChromeColors`; the defaults are unchanged. A colour set
  in `CruxIdeLayoutTheme` still wins. Depends on `crux_theme`.

## 0.3.0

- `CruxFocusRegion` and `CruxFocusRegionScope`: keyboard regions. Tab stays
  inside a region until its controls are exhausted; F6 / Shift+F6 move to the
  next / previous region (reading order, restoring the control F6 left) and
  work even while nothing has focus, but never reach behind a dialog.
- The scope restores lost focus on desktop (`restoreLostFocus`): when focus
  falls onto a bare scope — the focused control was rebuilt away, or the
  window returned from a native dialog — it goes back to the control last
  focused inside the screen, else the `primary` region, else the first
  region. `CruxIdeLayout`'s center pane is primary. Liveness is judged by the
  node's parent link and a mounted element, not its context or cached
  ancestors, which a detached node keeps — trusting those asked a removed
  button for focus and left the window with none.
- Keyboard resizing: with focus inside a side or bottom region,
  Ctrl+Shift+Arrow (Cmd+Shift+Arrow on Apple platforms) grows or shrinks it
  by `kCruxPaneResizeStep`, within its minimum, and persists the size like a
  drag. It replaces the resizers' own arrow keys, which needed them focused.
  The key handler adds nothing to the semantics tree; a `CallbackShortcuts`
  in its place merged a search field with the text below it into one node.
- `CruxIdeLayout` makes each of its four panes a region, excludes a hidden
  pane's controls from focus, and keeps the `panes` resizers out of the Tab
  order. The resizers carry no semantics, so a screen reader announced each
  one as "text", and their full height interleaved one dock's buttons with
  another's. Dragging still resizes; keyboard resizing through those stops is
  gone until `panes` can label them.
- `announceCrux` speaks a message through the screen reader.
  `showCruxInfoSnack` (polite) and `showCruxErrorSnack` (assertive) now call
  it: a SnackBar is a live region, and the desktop bridges ignore live
  regions, so neither helper was ever heard.

## 0.2.1

- `CruxIdeLayout` now clamps its pixel-sized regions to the window. `panes`
  lays a pixel-sized region out as a hard `SizedBox` and never checks it
  against the container, so a window shorter/narrower than
  `regions + resizers + centerMinSize` starved the center region to zero and
  then overflowed the `RenderFlex` (a clipped panel plus a debug-mode overflow
  assert — hit in WaveCrux with a tall stage panel open). Regions now shrink
  instead: the bottom region against the available height, the left and right
  regions in proportion against the available width. The clamp is transient —
  never written to the `IdePanelLayoutSink` — so regions grow back to their
  stored sizes as the window does.

## 0.2.0

- `PlatformContextMenu` — the suite's "long-press = right-click" wrapper,
  promoted from the proven WaveCrux implementation as the shared source of
  truth. Fires `onContextMenu` with the global position on secondary-tap-up
  everywhere, and on long-press start in touch contexts. The host supplies
  `isTouchLayout` from its responsive-layout classification (replacing the
  product-side device-class provider read); the host platform is read from
  the inherited theme. `shouldEnableLongPressContextMenu` exposes the gating
  rule for reuse and tests.
- Feedback helpers: `showCruxInfoSnack` / `showCruxErrorSnack` — the
  standard floating snack bars (4 s info via `kCruxInfoSnackDuration`, 6 s
  error-container-styled error via `kCruxErrorSnackDuration`) — and
  `confirmCruxDestructiveAction`, the standard destructive-action
  confirmation dialog (Cancel left, error-colored filled confirm right,
  `false` on any non-confirm dismissal).

## 0.1.0

- Initial release. `CruxIdeLayout` — the four-region dockable IDE shell,
  implemented over `package:panes`, rendered by every product in the suite.
- `IdePanelLayout` (read) + `IdePanelLayoutSink` (write) adapters: each host
  projects its own panel-layout state onto these rather than adopting a shared
  state model, so no product has to restructure its state to use the shell.
- The shared widget owns the `IdeController`, the resizer theme
  (`CruxIdeLayoutTheme`), and the visibility/size synchronization boilerplate
  that was previously duplicated per product.
- Re-exports `panes`' `PaneSize` and `IdePaneBuilder` so hosts can write their
  adapters and pane builders without importing `panes` directly.
