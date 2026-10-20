# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## Unreleased

- **`CruxFormRow` / `CruxFormSection`: label-left desktop forms.** A row
  around any control, plus `CruxFormRow.toggle` (a `CruxSwitch`, for a
  setting that applies at once) and `CruxFormRow.checkbox` (for an option in
  a form that applies on OK). The label is the control's accessible name and,
  for a switch or checkbox, its click target; help text sits under the
  control and is read as the hint. Inside a section the labels share a
  column; with a null `labelWidth` (Settings) label and control spread apart;
  without `CruxDesktopTokens` (phone, tablet) the label stacks above the
  control and a toggle keeps the Material switch.
- **The `CruxSettings*` rows are built on `CruxFormRow`.**
  `CruxSettingsControlTile` (and the auto-reload tile on it) puts its control
  at the row's end on desktop instead of under the label;
  `CruxSettingsSliderTile` holds its slider at `kCruxSettingsSliderWidth` on
  desktop; `CruxLocaleSettingTile` is a control tile with a boxed dropdown
  rather than a `ListTile`. The Settings dialog opens through
  `showCruxDialog`. New dependency on `crux_ide_layout`.

- **`CruxSettingsDialogShell` is no longer public.** No product built it
  directly; `openCruxSettings(asDialog: true)` is the way in, and the shell
  stays as its private implementation.
- **`CruxPolicyLock`**: the suite's one mount of `CruxPolicyLockNote`. A
  product wraps a policy-backed control in it with the resolved
  `PolicySource`; while that is `policyLocked` the control is dimmed, takes
  no pointer and no focus, and the lock note says why (above the control or
  below it, with an optional detail line). Every other source renders the
  control untouched. The sentence comes from `CruxPolicyLockScope`, mounted
  once per app, and is `kCruxPolicyLockNoteEn` without one. New dependency on
  `crux_policy` (pure Dart) for `PolicySource`.

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
