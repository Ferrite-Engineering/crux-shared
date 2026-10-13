// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/src/column_layout_providers.dart';
import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

/// The divider on a header cell's right edge: drag it to move width between
/// this column and the next, double-click it to restore the default widths.
///
/// Pointer-only and excluded from semantics. It is not a Tab stop, so the
/// table's keyboard order and what a screen reader announces are unchanged;
/// the default widths keep every column readable without it.
///
/// Give it `cruxTableResizeKey(tableId, column)` as its key, as
/// `CruxTableHeader` does.
class CruxColumnResizeHandle<C extends Enum> extends StatelessWidget {
  /// Creates the handle after [column].
  const CruxColumnResizeHandle({
    required this.column,
    required this.tableWidth,
    required this.controller,
    this.height = kCruxTableRowHeight,
    super.key,
  });

  /// The column on the handle's left; the drag trades width with the next.
  final C column;

  /// The width the resizable columns share, which turns a drag's pixels into
  /// weight.
  final double tableWidth;

  /// Receives the drag, its end, and a double-click.
  final CruxColumnResizeController<C> controller;

  /// The handle's height: the header's.
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Count movement from pointer-down, so the divider stays under the
          // cursor instead of lagging by the drag threshold.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: (d) =>
              controller.resize(column, d.delta.dx, tableWidth),
          onHorizontalDragEnd: (_) => controller.commit(),
          onDoubleTap: controller.reset,
          child: SizedBox(
            width: kCruxTableResizeHandleWidth,
            height: height,
            child: Center(
              child: SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
