# crux_settings_ui

The domain-neutral *chrome* of a Settings panel, shared by every product in
the EDACrux suite: a responsive master-detail layout and the grouped-row
widgets used to compose each category's content.

This package deliberately knows nothing about any product domain. It has no
notion of waveforms, netlists, lint rules or test runs, and it does not read
or write settings — that is `crux_settings`' job. Everything visible arrives
through constructor parameters, including every string, so hosts localize with
their own `AppLocalizations` and this package needs no ARB files of its own.

## Surface

| Symbol | Purpose |
|---|---|
| `CruxSettingsMasterDetail` | The panel layout: a category rail beside a scrolling detail pane on wide viewports, collapsing to a list → detail single column on narrow ones. |
| `CruxSettingsCategory` | One entry in the rail: `icon`, `title`, and the `content` widget the detail pane renders. |
| `CruxSettingsCard` | A grouped container for related rows — the visual unit inside a category. |
| `CruxSettingsControlTile` | A titled row with an optional description and a caller-supplied `control` widget (switch, dropdown, button, anything). |
| `CruxSettingsSliderTile` | A titled row with a description, a slider, and a formatted value read-out. |

## Layout behaviour

`CruxSettingsMasterDetail` picks its layout from the available width against
`dualPaneBreakpoint`:

- **Wide** — a fixed-width category rail (`railWidth`) beside the detail pane.
  Selecting a category swaps the detail pane in place.
- **Narrow** — the category list fills the viewport, and selecting a category
  pushes the detail view over it with a back affordance.

`scrollableDetail` (default on) wraps the detail pane in a scroll view. Turn
it off when a category's content manages its own scrolling — a nested
scrollable inside a scrollable is the usual cause of a category that will not
scroll to the bottom.

`showDetailTitle` controls whether the detail pane repeats the category title.
Hosts that already render a title in their own dialog chrome turn it off.

## Composing a category

The host owns the content entirely. The usual shape is a `Column` of
`CruxSettingsCard`s, each holding a few tiles:

```dart
CruxSettingsMasterDetail(
  categories: [
    CruxSettingsCategory(
      icon: Icons.palette_outlined,
      title: l10n.settingsAppearance,
      content: Column(
        children: [
          CruxSettingsCard(
            children: [
              CruxSettingsControlTile(
                title: l10n.settingsThemeMode,
                description: l10n.settingsThemeModeDescription,
                control: DropdownButton<AppThemeMode>(/* … */),
              ),
              CruxSettingsSliderTile(
                title: l10n.settingsFontScale,
                description: l10n.settingsFontScaleDescription,
                label: '${scale.toStringAsFixed(2)}×',
                valueText: '${scale.toStringAsFixed(2)}×',
                value: scale,
                min: 0.8,
                max: 1.6,
                divisions: 8,
                onChanged: (v) => ref.read(settingsProvider.notifier).setScale(v),
              ),
            ],
          ),
        ],
      ),
    ),
  ],
)
```

Note that `CruxSettingsSliderTile` takes both `label` (the slider's own
floating label) and `valueText` (the read-out beside the title). They are
usually the same string, but they are separate so a host can abbreviate one.

## What the host still owns

- **The dialog or route wrapper.** This package renders the panel body, not
  a `Dialog`, `AlertDialog` or `Scaffold`. Desktop products typically wrap it
  in a dialog and mobile products push a full-screen route.
- **All strings.** Category titles, tile titles, descriptions and value
  read-outs are parameters.
- **State.** Read and write your settings through `crux_settings` (or
  whatever the product uses) and pass the current value in.

## Adopting other suite packages here

Several shared packages are designed to be dropped straight into a
`CruxSettingsCategory.content`:

- `crux_keybindings`' `KeyBindingsEditor` — the shortcut-customization surface.
- `crux_theme`'s `ThemeAppearanceSection` — the whole Settings → Appearance
  composition.

Both are plain widgets, so no shell change is needed to host them.

## Visibility & license

Private during the public beta; Apache 2.0 at the post-beta open-core flip,
alongside the rest of the suite.
