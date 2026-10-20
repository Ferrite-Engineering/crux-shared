# Changelog

## Unreleased

- `CruxInspector`, the dock tab that shows and edits the current canvas
  selection's properties: selection-bound, built inside the dock's provider
  scope (never a route), sections from host and Pro seam builders,
  `CruxInspectorController.open()` for opening it with focus, Escape back to
  the canvas, held drafts with `CruxInspectorApplyBar`, the panel empty state.
  `CruxInspectorSection`, `CruxInspectorListSection` and
  `CruxInspectorValueRow` are its rows. `crux_ide_layout` and
  `crux_settings_ui` become dependencies.
- `CruxDock` is a `CruxRegionHintHost`: an empty panel inside it (a
  `CruxPanelEmptyState`) becomes the dock's description while the dock's name
  stays `semanticsLabel`. `crux_a11y` moves from a dev dependency to a
  dependency.

## 0.1.1

- `CruxDockRestoreBar` buttons are named buttons. An icon `InkWell` with only
  a tooltip merged into the bar's region node, so a screen reader announced
  the region name as bare text ("Panel dock, text") instead of the tab it
  restores.

## 0.1.0

- Initial release. `CruxDock` — the cross-suite VSCode-style tabbed region
  container for `CruxIdeLayout` regions: tab strip with `Badge.count` badges
  and per-tab close, auto-hiding single-pinned-entry header presentation,
  collapse / maximize / pop-out action cluster, and post-frame auto-reveal of
  newly appearing on-demand entries.
- `CruxDockEntry` — host-assembled tab descriptor whose `onClose` carries the
  suite's presence semantics (pinned vs. on-demand), generalized from
  WaveCrux's `BottomDockTab` plugin seam.
- `CruxDockPopOut` — the multi-window pop-out affordance configuration,
  rendered-but-disabled until Flutter multi-window reaches stable.
