# Changelog

## Unreleased

- **A sorted column narrower than its arrow no longer overflows.**
  `CruxSortableHeaderCell` drew the arrow in a fixed 18 dp slot, so a
  squeezed pane that lays a sorted column out below 18 dp of content (9 px
  in LintCrux's 450 px test) overflowed the row. The slot is now bounded by
  the cell (`LayoutBuilder`) and the arrow scales down inside it; the label
  is `Expanded`, so with room it still gets everything the arrow does not
  take.

## 0.1.0

- Initial extraction, from two products' copies of the same table model: a
  sortable header over a virtualized list, columns sized by weight and
  resizable by dragging the dividers between them, widths that persist, and
  body cells with a hover-only tooltip. The copies differed only in the
  column enum, the default weights and the preference key, which is exactly
  what stays with the host.
- `CruxTableColumns<C>` and `CruxColumnLayout<C>`: the column set with its
  default weights and minimum width, and a layout of weights over it with
  `flexOf` and `resize`. The minimum is 56 px (`kCruxTableMinColumnWidth`):
  at 40, a sorted column dragged to its minimum had a blank header.
  `resize` checks that both columns can still meet the minimum before it
  clamps; one copy clamped first, and `num.clamp` throws when its bounds
  cross.
- `CruxColumnLayoutCodec<C>`: the `SettingsCodec` storing one JSON object of
  column name to weight under the host's own key, so saved widths survive
  the switch.
- `CruxColumnLayoutProviders<C>`: the settings-service provider, the launch
  provider a host overrides from `load()` before `runApp` so a restored tab
  draws at its saved widths on its first frame, and the `NotifierProvider`
  whose `CruxColumnLayoutNotifier` offers `resize` / `commit` / `reset` and
  implements `CruxColumnResizeController`, the seam the dividers drive.
- Widgets: `CruxTableHeader<C>` (header tokens, 28 dp, a divider after every
  column but the last), `CruxSortableHeaderCell` (a button, label
  ellipsizing, the sort arrow in a fixed slot on the sorted column only: two
  `Flexible`s capped the label at half the cell), `CruxColumnResizeHandle<C>`
  (8 dp, outside semantics, `DragStartBehavior.down`, double-click resets)
  and `CruxTableCell` (hover-only tooltip, optional in-cell annotation that
  the text ellipsizes before and that scales down rather than overflowing;
  no reserved slot after the last column). Keys follow the products' own
  `<table>Header-<column>` / `<table>Resize-<column>` convention through
  `cruxTableHeaderKey` / `cruxTableResizeKey`.
