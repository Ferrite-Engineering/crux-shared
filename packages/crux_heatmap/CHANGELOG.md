# Changelog

## 0.1.0

- Initial release. `CruxCalendarHeatmap<T>` — the GitHub-contributions-style
  date grid LintCrux Pro and SimCrux Pro both render over their trend stores.
  Rows are days of the week, columns are weeks; the first column is padded by
  the start date's weekday. Pan and zoom via `InteractiveViewer`.
- `CruxHeatmapCell<T>` — one day, carrying a resolved colour, a localized
  tooltip and an opaque payload handed back to `onCellTap`.
- Extracted from two independently-written copies with byte-identical public
  surfaces. Only the colour mapping differed, and it stayed in the products:
  LintCrux ramps violation density against the busiest day in the range,
  SimCrux uses that day's pass rate dimmed by activity. A shared widget that
  owned either would be modelling one product's metric on behalf of both.
- `tooltip` is required rather than optional. A cell has no visible text, so
  it is the only thing a screen reader can announce — and one of the two
  source implementations was building it in hardcoded English.
