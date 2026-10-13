// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/foundation.dart';

/// A table's resizable columns, left to right, with their default weights and
/// the narrowest any may be dragged.
///
/// One per table, declared once by the host as a `const`:
///
/// ```dart
/// const resultColumns = CruxTableColumns<ResultColumn>(
///   columns: [ResultColumn.status, ResultColumn.name, ResultColumn.time],
///   defaultWeights: {
///     ResultColumn.status: 1.2,
///     ResultColumn.name: 3,
///     ResultColumn.time: 1.6,
///   },
/// );
/// ```
///
/// A fixed-width column (a check box) is not listed here; it sits beside the
/// weighted ones and takes no part in the layout.
@immutable
class CruxTableColumns<C extends Enum> {
  /// Creates the column set. Every column in [columns] needs an entry in
  /// [defaultWeights]; [CruxColumnLayout] asserts it.
  const CruxTableColumns({
    required this.columns,
    required this.defaultWeights,
    this.minColumnWidth = kCruxTableMinColumnWidth,
  });

  /// The resizable columns, left to right.
  final List<C> columns;

  /// The weight every column starts with.
  final Map<C, double> defaultWeights;

  /// The narrowest a column may be dragged, in logical pixels.
  final double minColumnWidth;

  /// The layout every table starts with.
  CruxColumnLayout<C> get defaults => CruxColumnLayout<C>(this, defaultWeights);

  /// Whether [column] has a width in this layout.
  bool isResizable(C column) => columns.contains(column);

  /// Whether [column] is the last one, after which no divider is drawn.
  bool isLast(C column) => columns.isNotEmpty && columns.last == column;

  @override
  bool operator ==(Object other) =>
      other is CruxTableColumns<C> &&
      listEquals(other.columns, columns) &&
      mapEquals(other.defaultWeights, defaultWeights) &&
      other.minColumnWidth == minColumnWidth;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(columns),
    Object.hashAll(columns.map((c) => defaultWeights[c])),
    minColumnWidth,
  );

  @override
  String toString() => 'CruxTableColumns($columns)';
}

/// A table's column widths, as relative weights over a [CruxTableColumns].
///
/// Weights rather than pixels: the resizable columns always share the width
/// the fixed columns leave exactly, so a narrow pane never opens a gap and a
/// wide one never leaves one. Resizing moves width between two neighbouring
/// columns ([resize]), which keeps the total, and so every other column,
/// unchanged.
@immutable
class CruxColumnLayout<C extends Enum> {
  /// Creates a layout from [weights]. A column missing from [weights], or
  /// carrying a weight that is not a positive finite number, takes its
  /// default.
  CruxColumnLayout(this.columns, Map<C, double> weights)
    : assert(
        columns.columns.every(columns.defaultWeights.containsKey),
        'every column needs a default weight',
      ),
      weights = Map<C, double>.unmodifiable({
        for (final column in columns.columns)
          column: _valid(weights[column]) ?? columns.defaultWeights[column]!,
      });

  /// The columns this layout sizes.
  final CruxTableColumns<C> columns;

  /// Each resizable column's weight, for every column in [columns].
  final Map<C, double> weights;

  /// The sum of every column's weight.
  double get totalWeight => weights.values.fold(0, (a, b) => a + b);

  /// Whether every column is at its default weight.
  bool get isDefault => this == columns.defaults;

  /// The integer flex for [column], fine-grained enough that a one-pixel drag
  /// moves a divider. [column] must be one of [columns].
  int flexOf(C column) => (weights[column]! * 1000).round().clamp(1, 1 << 30);

  /// Moves [dx] logical pixels of width from the column after [column] to
  /// [column] (a negative [dx] moves it the other way), in a table whose
  /// resizable columns span [tableWidth] pixels. Neither column goes below
  /// the columns' minimum width. Returns this layout when [column] is the
  /// last one, is not resizable, or nothing can move.
  CruxColumnLayout<C> resize(C column, double dx, double tableWidth) {
    final order = columns.columns;
    final index = order.indexOf(column);
    if (index < 0 || index >= order.length - 1 || tableWidth <= 0) {
      return this;
    }
    final next = order[index + 1];
    final perPixel = totalWeight / tableWidth;
    final minWeight = columns.minColumnWidth * perPixel;
    final pair = weights[column]! + weights[next]!;
    // Checked before the clamp: with both columns already at their minimum
    // the clamp's bounds would cross, and `num.clamp` throws on that.
    if (pair < 2 * minWeight) return this;
    final left = (weights[column]! + dx * perPixel).clamp(
      minWeight,
      pair - minWeight,
    );
    if (left == weights[column]) return this;
    return CruxColumnLayout<C>(columns, {
      ...weights,
      column: left,
      next: pair - left,
    });
  }

  static double? _valid(double? weight) =>
      weight != null && weight.isFinite && weight > 0 ? weight : null;

  @override
  bool operator ==(Object other) =>
      other is CruxColumnLayout<C> &&
      other.columns == columns &&
      columns.columns.every((c) => other.weights[c] == weights[c]);

  @override
  int get hashCode => Object.hash(
    columns,
    Object.hashAll(columns.columns.map((c) => weights[c])),
  );

  @override
  String toString() => 'CruxColumnLayout($weights)';
}
