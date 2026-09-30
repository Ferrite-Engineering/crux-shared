# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## Unreleased

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
