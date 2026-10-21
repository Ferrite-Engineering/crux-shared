// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/metrics/exact_decimal.dart';
import 'package:crux_flow/src/metrics/metric_definition.dart';
import 'package:crux_flow/src/metrics/metric_key.dart';

/// A metric value as a number, keeping whether it was an integer.
typedef MetricNumber = ({ExactDecimal exact, bool isInt});

/// [value] as a number, or null when it is not one (a string, a boolean,
/// null, or a non-finite double).
MetricNumber? metricNumber(Object? value) => switch (value) {
  final int i => (exact: ExactDecimal.fromInt(i), isInt: true),
  final double d when d.isFinite => (
    exact: ExactDecimal.fromJsonDouble(d),
    isInt: false,
  ),
  _ => null,
};

/// [number] back as the JSON value it stands for: an `int` when every input
/// to it was an integer, otherwise the nearest `double`.
Object metricValueOf(MetricNumber number) =>
    number.isInt ? number.exact.truncateToInt() : number.exact.toDouble();

/// Folds per-modifier metric values into their bases, as upstream
/// LibreLane's `aggregate_metrics` does.
///
/// For each key that carries modifiers and whose base metric has an
/// aggregator in [table], the value is folded into the base and into every
/// shorter prefix of its modifiers (`a__corner:x__vt:y` feeds `a` and
/// `a__corner:x`). A key with none of its modifiers in the definition's
/// `dontAggregate` list is folded; one with any is skipped. Keys without
/// modifiers are final values: they are not folded into anything, and an
/// aggregate computed here replaces them.
///
/// Upstream semantics kept on purpose, because LibreLane's own final metrics
/// were computed this way:
///
/// - A running value of exactly zero restarts the fold, as upstream's
///   `aggregated.get(name) or start` does. A minimum over `0` then `5`
///   therefore ends at `5`.
/// - Arithmetic is decimal, so `0.1 + 0.2` folds to `0.3`.
///
/// Values that are not numbers are skipped (upstream raises on them). The
/// result keeps [input]'s order, with aggregates for absent bases appended.
Map<String, Object?> aggregateMetrics(
  Map<String, Object?> input, {
  MetricDefinitionTable? table,
}) {
  final definitions = table ?? librelaneMetricsV1;
  final aggregated = <String, MetricNumber>{};
  for (final MapEntry(:key, :value) in input.entries) {
    final parsed = MetricKey.tryParse(key);
    if (parsed == null || !parsed.isModified) continue;
    final definition = definitions[parsed.base];
    final aggregator = definition?.aggregator;
    if (definition == null || aggregator == null) continue;
    if (parsed.modifiers.any(
      (m) => definition.dontAggregate.contains(m.name),
    )) {
      continue;
    }
    final number = metricNumber(value);
    if (number == null) continue;
    final name = StringBuffer(parsed.base);
    for (final modifier in parsed.modifiers) {
      final prefix = name.toString();
      final current = aggregated[prefix];
      final restart = current == null || current.exact.isZero;
      aggregated[prefix] = _fold(aggregator, restart ? null : current, number);
      name.write('__$modifier');
    }
  }
  return {
    ...input,
    for (final MapEntry(:key, :value) in aggregated.entries)
      key: metricValueOf(value),
  };
}

MetricNumber _fold(
  MetricAggregator aggregator,
  MetricNumber? current,
  MetricNumber value,
) {
  if (current == null) return value;
  return switch (aggregator) {
    MetricAggregator.sum => (
      exact: current.exact + value.exact,
      isInt: current.isInt && value.isInt,
    ),
    MetricAggregator.min =>
      value.exact.compareTo(current.exact) < 0 ? value : current,
    MetricAggregator.max =>
      value.exact.compareTo(current.exact) > 0 ? value : current,
  };
}
