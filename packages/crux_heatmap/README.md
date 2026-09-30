# crux_heatmap

The GitHub-contributions-style calendar heatmap LintCrux and SimCrux both
render over their Pro trend stores.

## Why this package exists, and why it is this small

A suite-wide audit reported ~1,680 lines of duplicated trend-tracking
code between the two products. Measured properly before extracting, that was
mostly parallel *shape* rather than shared *content*:

| Pair | Genuinely shared |
|---|---|
| `calendar_heatmap_grid` | **69%** |
| alerts banner | 44% |
| calendar heatmap screen | 37% |
| per-X trend chart screen | 35% |
| retention settings section | 22% |

Only the grid was a real duplicate — and its public surface was identical in
both products. So one widget was lifted, and the surrounding screens were
deliberately left alone: two products solving a similar problem is not the
same as two copies of one solution.

## The seam

The host supplies each day's resolved colour and localized tooltip. The
package never learns what is being plotted — LintCrux ramps violation density
against the busiest day in the range, SimCrux uses that day's pass rate and
dims by activity, and neither computation belongs in shared code.

```dart
CruxCalendarHeatmap<MyDay>(
  start: range.start,
  cells: [
    for (final day in days)
      CruxHeatmapCell(
        day: day.date,
        color: myColourFor(day),
        tooltip: l10n.heatmapTooltip(day.date, day.count),
        payload: day,
      ),
  ],
  onCellTap: (day) => openDrillDown(day),
)
```

`tooltip` is required rather than optional: a cell has no visible text, so
without one it is an unnamed tap target — and one of the two products this was
extracted from was building that string in hardcoded English.

## Not in scope

A **seed-failure** heatmap also exists in SimCrux. It shares the "grid of
coloured cells" idea and nothing else — it is not date-indexed, it carries a
legend, and its colours are discrete statuses rather than a ramp. It stays
where it is.
