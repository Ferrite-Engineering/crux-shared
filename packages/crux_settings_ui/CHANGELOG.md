# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## 0.2.0

- Settings opens with keyboard focus on the selected category, so a screen
  reader announces where focus went; the dialog is named after its title.
- Escape closes the Settings dialog. The route's dismiss action is disabled
  with the non-dismissible barrier, and a disabled action found first ended
  the Escape lookup.
- The category rail is one Tab stop: Up / Down / Home / End move the
  selection, and each tile is announced as a button with its selected state.
  Tiles are 48 dp tall to meet the tap-target floor as separate targets.
- The rail and the detail pane are separate traversal groups, so Tab no
  longer alternates between the two columns by height.
- `CruxSettingsCard` makes each row its own semantics container, so a plain
  row's text no longer becomes the name of the whole card.

## 0.1.0

- Initial extraction from WaveCrux's dual-pane Settings. The domain-neutral
  chrome of a Settings panel, with no knowledge of any product domain and no
  strings of its own — everything visible arrives via constructor parameters.
- `CruxSettingsMasterDetail` — the responsive panel layout: a fixed-width
  category rail beside a scrolling detail pane above `dualPaneBreakpoint`,
  collapsing to a list → detail single column below it. `railWidth`,
  `scrollableDetail` and `showDetailTitle` are host-tunable.
- `CruxSettingsCategory` — one rail entry: icon, title, and the content widget
  the detail pane renders.
- `CruxSettingsCard` — grouped container for related rows.
- `CruxSettingsControlTile` — titled row with optional description and a
  caller-supplied control widget.
- `CruxSettingsSliderTile` — titled row with description, slider, and a
  formatted value read-out.
- The host retains the dialog / route wrapper, all strings, and all state.
