// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// Header and body row height, in logical pixels, for rows set in
/// `bodySmall`. The density both tables that this package came from settled
/// on; a virtualized list uses it as its `itemExtent`.
const double kCruxTableRowHeight = 28;

/// The narrowest a column may be dragged, in logical pixels.
///
/// The header's 16 px of padding and the sorted column's 18 px arrow still
/// leave a few characters of label. At 40, a sorted column dragged to its
/// minimum had a blank header.
const double kCruxTableMinColumnWidth = 56;

/// Horizontal padding inside a header or body cell, each side.
const double kCruxTableCellPadding = 8;

/// The sort arrow's size in a header cell. A fixed slot, not a flexible one:
/// two `Flexible`s split the cell and capped the label at half of it.
const double kCruxTableSortArrowSize = 18;

/// The width of the drag target on a header cell's right edge.
const double kCruxTableResizeHandleWidth = 8;

/// The key of the header cell for [column] in the table named [tableId]:
/// `<tableId>Header-<column>`. The products' widget tests find header cells
/// by this convention.
Key cruxTableHeaderKey(String tableId, Enum column) =>
    ValueKey<String>('${tableId}Header-${column.name}');

/// The key of the resize handle after [column] in the table named [tableId]:
/// `<tableId>Resize-<column>`.
Key cruxTableResizeKey(String tableId, Enum column) =>
    ValueKey<String>('${tableId}Resize-${column.name}');
