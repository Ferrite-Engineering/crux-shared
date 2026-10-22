# crux_table

The table model two products arrived at separately and now share: a sortable
header over a virtualized list, columns sized by weight and resizable by dragging
the dividers between them, widths that persist, and body cells with a hover-only
tooltip. Generic over the host's column enum.

## What the host keeps

Its column enum, its default weights, its preference key, and its row widget.
Rows differ between tables in every way that matters (selection, focus, context
menus, the one sentence a screen reader hears per row), so no shared row is
offered; a row uses the shared layout for its cell widths and `CruxTableCell` for
its text cells.

## Declaring a table

```dart
// The columns, once, as a const.
const resultColumns = CruxTableColumns<ResultColumn>(
  columns: [ResultColumn.status, ResultColumn.name, ResultColumn.time],
  defaultWeights: {
    ResultColumn.status: 1.2,
    ResultColumn.name: 3,
    ResultColumn.time: 1.6,
  },
);

// The persisted widths, once, at the top level.
final resultColumnLayout = CruxColumnLayoutProviders<ResultColumn>(
  columns: resultColumns,
  prefsKey: 'myapp.resultColumnWeights',   // the key the host already uses
  name: 'resultColumnLayout',
);
```

Before `runApp`, so a restored tab draws at its saved widths on its first frame:

```dart
final loaded = await resultColumnLayout.load();
runApp(ProviderScope(
  overrides: [resultColumnLayout.launchOverride(loaded)],
  child: const App(),
));
```

## Rendering it

```dart
final layout = ref.watch(resultColumnLayout.layout);
final sort = ref.watch(sortProvider);

CruxTableHeader<ResultColumn>(
  tableId: 'results',
  layout: layout,
  controller: ref.read(resultColumnLayout.layout.notifier),
  leading: const [SizedBox(width: 32)],          // the check box column
  cellBuilder: (context, column) => CruxSortableHeaderCell(
    key: cruxTableHeaderKey('results', column),
    label: labelFor(column),
    sorted: sort.column == column,
    ascending: sort.ascending,
    onTap: () => ref.read(sortProvider.notifier).toggle(column),
  ),
);

// In a row, beside the fixed-width check box:
CruxTableCell(text: row.name, flex: layout.flexOf(ResultColumn.name), annotation: chip),
```

The header's dividers carry the key `cruxTableResizeKey('results', column)`
(`resultsResize-name`), and the header cells the key the host gives them
(`resultsHeader-name`), so the host's widget tests find them by the convention
they already use.

## Rules the shared widgets pin

- **Header tokens:** `surfaceContainerHighest` background, `outlineVariant` bottom
  border, labels in `labelMedium` w600 `onSurfaceVariant`, 28 dp tall
  (`kCruxTableRowHeight`, also the body row height and the list's `itemExtent`).
- **Sort arrow on the sorted column only, in a fixed slot.** Two `Flexible`s split
  the cell and capped the label at half of it ("Sever…" with room to spare). The
  label's maximum width is the cell less its padding and, on the sorted column, the
  18 px arrow.
- **56 px minimum column width.** At 40, a sorted column dragged to its minimum had
  a blank header.
- **Dividers are pointer-only and outside semantics.** Not a Tab stop; the
  default widths keep every column readable without them. `DragStartBehavior.down`
  so the divider stays under the cursor; double-click restores the defaults; a drag
  saves once, when it ends.
- **No divider after the last column**, and **no reserved slot after it**: a row
  annotation renders inside the cell it describes, right-aligned after the text at
  its natural width. The text ellipsizes first; in a cell too narrow for both, the
  annotation scales down instead of overflowing.
- **One announcement per row** is the host's job (its check box carries the
  sentence); `CruxTableCell` keeps its text out of semantics so it cannot become a
  second fragment.

## Exported on purpose

`tool/unused-exports.py` reports a symbol as *internal* when no other package and no product references it. These stay in the export namespace, for the reason given:

- **Named by an exported signature** (a host can receive or must name the type): `CruxColumnLayoutCodec` (in `CruxColumnLayoutProviders`).
- **Callback type named in an exported signature; a host passing a closure never writes it**: `CruxTableHeaderCellBuilder`.
