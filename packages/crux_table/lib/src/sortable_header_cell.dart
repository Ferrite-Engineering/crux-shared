// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/material.dart';

/// A header cell that sorts its column when activated.
///
/// Announced as a button: a bare `InkWell` carries the tap action but no
/// role, and a screen reader called each header plain "text". The label
/// ellipsizes; the sort arrow, drawn on the sorted column only, sits in a
/// fixed [kCruxTableSortArrowSize] slot after it. Two `Flexible`s split the
/// cell and capped the label at half of it, so a column with room for the
/// whole word showed "Sever…"; a fixed slot gives the label everything the
/// arrow does not take, and the unsorted columns keep those pixels for their
/// label.
///
/// Give it `cruxTableHeaderKey(tableId, column)` as its key so the host's
/// widget tests find it.
class CruxSortableHeaderCell extends StatelessWidget {
  /// Creates a header cell labelled [label].
  const CruxSortableHeaderCell({
    required this.label,
    required this.onTap,
    this.sorted = false,
    this.ascending = true,
    super.key,
  });

  /// The column's title.
  final String label;

  /// Sorts by this column, or flips the direction when it is already the
  /// sort column.
  final VoidCallback onTap;

  /// Whether this is the column the table is sorted by.
  final bool sorted;

  /// The sort direction shown when [sorted].
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      container: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kCruxTableCellPadding,
          ),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sorted)
                Icon(
                  ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: kCruxTableSortArrowSize,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
