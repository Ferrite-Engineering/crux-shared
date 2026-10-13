// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/src/column_layout.dart';
import 'package:crux_table/src/column_layout_providers.dart';
import 'package:crux_table/src/column_resize_handle.dart';
import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/material.dart';

/// Builds the header cell for one column: usually a `CruxSortableHeaderCell`
/// keyed with `cruxTableHeaderKey`.
typedef CruxTableHeaderCellBuilder<C extends Enum> =
    Widget Function(BuildContext context, C column);

/// The header row above a table's virtualized list.
///
/// Draws the header chrome (`surfaceContainerHighest` background,
/// `outlineVariant` bottom border, [kCruxTableRowHeight] tall), lays the
/// resizable columns out by [layout]'s weights after any [leading]
/// fixed-width widgets, and puts a [CruxColumnResizeHandle] after every
/// column but the last, keyed `cruxTableResizeKey(tableId, column)`. The
/// cells themselves come from [cellBuilder], so the host decides their
/// labels and what a tap does.
///
/// The body rows read the same [layout] and use `flexOf` for their cells, so
/// a drag on a divider moves the header and every row together.
class CruxTableHeader<C extends Enum> extends StatelessWidget {
  /// Creates the header for the table named [tableId].
  const CruxTableHeader({
    required this.tableId,
    required this.layout,
    required this.cellBuilder,
    this.controller,
    this.leading = const <Widget>[],
    this.height = kCruxTableRowHeight,
    super.key,
  });

  /// The table's name, the prefix of every key under it.
  final String tableId;

  /// The current column widths.
  final CruxColumnLayout<C> layout;

  /// Builds each column's header cell.
  final CruxTableHeaderCellBuilder<C> cellBuilder;

  /// What the dividers drive. `null` draws no dividers.
  final CruxColumnResizeController<C>? controller;

  /// Fixed-width widgets before the weighted columns: a check box spacer,
  /// a plugin's own columns. Each sizes itself.
  final List<Widget> leading;

  /// The header's height.
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = this.controller;
    final columns = layout.columns;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          children: <Widget>[
            ...leading,
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth;
                  return Row(
                    children: <Widget>[
                      for (final column in columns.columns)
                        Expanded(
                          flex: layout.flexOf(column),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: cellBuilder(context, column)),
                              if (controller != null && !columns.isLast(column))
                                CruxColumnResizeHandle<C>(
                                  key: cruxTableResizeKey(tableId, column),
                                  column: column,
                                  tableWidth: tableWidth,
                                  controller: controller,
                                  height: height,
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
