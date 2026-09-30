## Unreleased

- A toggled-on button's glyph takes the theme's `toolbar.iconActive` chrome
  token, read from `crux_theme`'s `CruxChromeColors`, and `primary` when the
  theme leaves it unset (as before). Depends on `crux_theme`.

## 0.1.0

- Initial extraction of the application toolbar from the four product
  toolbars into one shared, generic implementation.
- `CruxToolbar<A>` renders `[common] · divider · [specific]` with a stable
  auto-hiding overflow slot and an edge fade.
- `CruxToolbarMetrics` replaces four independent sets of magic numbers.
- `CruxToolbarSplitButton` — a Photoshop-style grouped tool button.
- `CruxRunStopButton` — a single morphing run/cancel control.
- Live-binding tooltips via `crux_keybindings.formatShortcutLabel`.
