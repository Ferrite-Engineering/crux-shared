## Unreleased

- A split button's face now has an accessible name. It was announced as a bare
  "button" while enabled (and flagged as a nameless stop by the focus-walk
  harness); it now carries the same text its tooltip shows, enabled or
  disabled. `CruxToolbarButton(tooltipOnHoverOnly: true)` states that text as
  its semantics label. No public API change.

- **Export namespace narrowed by 1 symbol.** `cruxToolbarTooltip` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- The overflow button is the suite's "⋯" (`Icons.more_horiz`), never "⋮".

- The toolbar surface takes the theme's `toolbar.background` chrome token
  and an enabled button's resting glyph takes `toolbar.icon`, both read from
  `CruxChromeColors`; unset, they keep `surfaceContainerHigh` and the
  `IconButton`'s own colour. A disabled button keeps its disabled colour, and
  a toggled-on glyph still takes `toolbar.iconActive`.

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
