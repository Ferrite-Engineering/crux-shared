// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// One day in a [CruxCalendarHeatmap].
///
/// The host has already decided what this day *means* — it supplies the
/// resolved [color] and the localized [tooltip]. That is the whole seam: the
/// package lays out a date grid and never learns whether a cell is dark
/// because a lint run found 900 violations or because a regression suite went
/// red.
///
/// [payload] is handed straight back to `onCellTap` so the host can drill
/// down without re-deriving which day was tapped.
@immutable
class CruxHeatmapCell<T> {
  /// Creates a heatmap cell.
  const CruxHeatmapCell({
    required this.day,
    required this.color,
    required this.tooltip,
    required this.payload,
  });

  /// The day this cell represents. Only the date part is used for layout.
  final DateTime day;

  /// Fully-resolved fill colour.
  ///
  /// Resolved by the host because the *scale* is usually a property of the
  /// whole dataset rather than of one cell — LintCrux ramps each day against
  /// the busiest day's violation count, SimCrux against that day's own pass
  /// rate. A widget that owned the colour would have to own that decision
  /// too, and would then be modelling two products' metrics.
  final Color color;

  /// Localized tooltip for this cell.
  ///
  /// Required, and localized by the host, because the package carries no
  /// localizations. Making it required rather than optional is deliberate: a
  /// cell with no visible label and no tooltip is an unnamed target, and one
  /// of the two products this was extracted from was building this string in
  /// hardcoded English.
  final String tooltip;

  /// Opaque value returned to `onCellTap`.
  final T payload;
}

/// A GitHub-contributions-style calendar heatmap.
///
/// Rows are days of the week (Mon..Sun), columns are weeks. Cells flow down
/// each column, so the first column is padded by however many weekdays elapse
/// before [start].
///
/// ## What this package deliberately does not do
///
/// It does not know what it is plotting. LintCrux colours by violation
/// density against the busiest day; SimCrux colours by that day's pass rate
/// and dims by activity. Both computations stay in their product, and the
/// widget receives a list of coloured, tooltipped days.
///
/// That is why extracting this was worth it and extracting the surrounding
/// screens was not: measured 2026-08-18, the two grids were **69% identical**
/// with byte-identical public surfaces, while the retention sections around
/// them were 22% and the chart screens 35% — parallel shapes rather than
/// shared code.
class CruxCalendarHeatmap<T> extends StatelessWidget {
  /// Creates a calendar heatmap.
  const CruxCalendarHeatmap({
    required this.start,
    required this.cells,
    this.onCellTap,
    this.cellSize = 14,
    this.cellGap = 2,
    super.key,
  });

  /// First day of the range. Its weekday sets the first column's offset.
  final DateTime start;

  /// One entry per day, in ascending date order.
  final List<CruxHeatmapCell<T>> cells;

  /// Invoked with the tapped cell's payload. Null makes cells non-interactive.
  final void Function(T payload)? onCellTap;

  /// Per-cell square size in logical pixels.
  final double cellSize;

  /// Gap between adjacent cells in logical pixels.
  final double cellGap;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();

    // 1 = Monday .. 7 = Sunday. UTC so a host in a negative offset does not
    // shift the grid by a column depending on the hour the app launched.
    final firstColOffset = start.toUtc().weekday - 1;
    final weekCount = ((firstColOffset + cells.length) / 7).ceil();

    return InteractiveViewer(
      constrained: false,
      child: SizedBox(
        width: weekCount * (cellSize + cellGap),
        height: 7 * (cellSize + cellGap),
        child: Stack(
          children: <Widget>[
            for (var i = 0; i < cells.length; i++)
              _positioned(i + firstColOffset, cells[i]),
          ],
        ),
      ),
    );
  }

  Widget _positioned(int absoluteIndex, CruxHeatmapCell<T> cell) {
    final tap = onCellTap;
    return Positioned(
      left: (absoluteIndex ~/ 7) * (cellSize + cellGap),
      top: (absoluteIndex % 7) * (cellSize + cellGap),
      width: cellSize,
      height: cellSize,
      child: Tooltip(
        message: cell.tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: tap == null ? null : () => tap(cell.payload),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cell.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}
