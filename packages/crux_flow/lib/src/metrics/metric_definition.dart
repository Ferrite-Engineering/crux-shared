// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// How a metric's per-modifier values fold into its base value.
enum MetricAggregator {
  /// Added up: counts, power, wire length.
  sum,

  /// The smallest: slacks, worst voltages.
  min,

  /// The largest: worst drops, worst skews, maximum violation counts.
  max,
}

/// What the suite knows about one METRICS2.1 base metric.
@immutable
class MetricDefinition {
  /// Creates a definition.
  const MetricDefinition(
    this.name, {
    this.aggregator,
    this.higherIsBetter,
    this.critical = false,
    this.dontAggregate = const <String>[],
  });

  /// The base metric name.
  final String name;

  /// How per-modifier values fold into the base, or null when they do not.
  final MetricAggregator? aggregator;

  /// Whether a higher value is an improvement; null when the direction is
  /// not a matter of better or worse.
  final bool? higherIsBetter;

  /// Whether any change in the value is flagged whatever its direction: a
  /// change that very likely means a dead chip, such as a new DRC error.
  final bool critical;

  /// Modifier names whose values are never folded into the base (`iter`:
  /// intermediate routing iterations are not part of the final count).
  final List<String> dontAggregate;

  @override
  bool operator ==(Object other) =>
      other is MetricDefinition &&
      other.name == name &&
      other.aggregator == aggregator &&
      other.higherIsBetter == higherIsBetter &&
      other.critical == critical &&
      other.dontAggregate.length == dontAggregate.length &&
      other.dontAggregate.indexed.every((e) => dontAggregate[e.$1] == e.$2);

  @override
  int get hashCode => Object.hash(
    name,
    aggregator,
    higherIsBetter,
    critical,
    Object.hashAll(dontAggregate),
  );

  @override
  String toString() => 'MetricDefinition($name)';
}

/// A versioned table of metric definitions.
///
/// The table is data, not code: a LibreLane release that adds, renames or
/// re-signs a metric gets a new table version, and a run is read against
/// the table matching the version that produced it.
@immutable
class MetricDefinitionTable {
  /// Creates a table. [definitions] keep their order.
  MetricDefinitionTable({
    required this.version,
    required this.source,
    required List<MetricDefinition> definitions,
  }) : definitions = List.unmodifiable(definitions),
       _byName = {for (final d in definitions) d.name: d};

  /// The table's own version.
  final int version;

  /// Where the table was ported from, file and release.
  final String source;

  /// Every definition, in upstream order.
  final List<MetricDefinition> definitions;

  final Map<String, MetricDefinition> _byName;

  /// The definition for the base metric [name], or null.
  MetricDefinition? operator [](String name) => _byName[name];

  /// Whether [name] is a defined base metric.
  bool contains(String name) => _byName.containsKey(name);
}

const MetricAggregator _sum = MetricAggregator.sum;
const MetricAggregator _min = MetricAggregator.min;
const MetricAggregator _max = MetricAggregator.max;
const List<String> _iter = <String>['iter'];

/// Version 1 of the metric table.
///
/// Ported from upstream LibreLane `librelane/common/metrics/library.py` as
/// released in LibreLane 3.0.16 (Apache-2.0, copyright Efabless Corporation
/// and the LibreLane contributors): every `Metric(...)` there, in the same
/// order, with the same aggregator, direction, criticality and
/// `dont_aggregate` list.
final MetricDefinitionTable librelaneMetricsV1 = MetricDefinitionTable(
  version: 1,
  source: 'librelane/common/metrics/library.py, LibreLane 3.0.16',
  definitions: const [
    // Area and counts.
    MetricDefinition('design__core__area', higherIsBetter: false),
    MetricDefinition('design__die__area', higherIsBetter: false),
    MetricDefinition('design__instance__area', higherIsBetter: false),
    MetricDefinition('design__instance__count', higherIsBetter: false),
    // Power.
    MetricDefinition('ir__drop__avg', higherIsBetter: false),
    MetricDefinition(
      'ir__drop__worst',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'ir__voltage__worst',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition('design_powergrid__drop__average', higherIsBetter: false),
    MetricDefinition(
      'design_powergrid__drop__worst',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design_powergrid__voltage__worst',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition(
      'power__internal__total',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'power__leakage__total',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'power__switching__total',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition('power__total', aggregator: _sum, higherIsBetter: false),
    // Timing.
    MetricDefinition(
      'timing__hold_vio__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'timing__hold_r2r_vio__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'timing__setup_vio__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'timing__setup_r2r_vio__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'timing__hold__ws',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition(
      'timing__hold_r2r__ws',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition(
      'timing__setup__ws',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition(
      'timing__setup_r2r__ws',
      aggregator: _min,
      higherIsBetter: true,
    ),
    MetricDefinition(
      'timing__hold__wns',
      aggregator: _min,
      higherIsBetter: true,
      critical: true,
    ),
    MetricDefinition(
      'timing__setup__wns',
      aggregator: _min,
      higherIsBetter: true,
      critical: true,
    ),
    MetricDefinition(
      'timing__hold__tns',
      aggregator: _min,
      higherIsBetter: true,
      critical: true,
    ),
    MetricDefinition(
      'timing__unannotated_net__count',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'timing__unannotated_net_filtered__count',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'timing__setup__tns',
      aggregator: _min,
      higherIsBetter: true,
      critical: true,
    ),
    MetricDefinition(
      'clock__skew__worst_hold',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'clock__skew__worst_setup',
      aggregator: _min,
      higherIsBetter: true,
    ),
    // Constraint violations.
    MetricDefinition(
      'design__max_slew_violation__count',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__max_fanout_violation__count',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__max_cap_violation__count',
      aggregator: _max,
      higherIsBetter: false,
    ),
    // Placement and routing.
    MetricDefinition(
      'route__wirelength',
      aggregator: _sum,
      higherIsBetter: false,
      dontAggregate: _iter,
    ),
    MetricDefinition(
      'route__wirelength__estimated',
      aggregator: _sum,
      higherIsBetter: false,
      dontAggregate: _iter,
    ),
    MetricDefinition(
      'route__wirelength__max',
      aggregator: _max,
      higherIsBetter: false,
      dontAggregate: _iter,
    ),
    MetricDefinition(
      'route__antenna_violation__count',
      aggregator: _sum,
      higherIsBetter: false,
      dontAggregate: _iter,
    ),
    MetricDefinition(
      'design__instance__displacement__max',
      aggregator: _max,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__instance__displacement__total',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition('design__instance__utilization', higherIsBetter: true),
    // Potential issues.
    MetricDefinition(
      'design__lint_warning__count',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__lint_error__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lint_timing_construct__count',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'antenna__violating__nets',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'antenna__violating__pins',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__instance_unmapped__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__disconnected_pin__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__inferred_latch__count',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__violations',
      aggregator: _sum,
      higherIsBetter: false,
    ),
    MetricDefinition(
      'design__xor_difference__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'route__drc_errors',
      aggregator: _sum,
      higherIsBetter: false,
      dontAggregate: _iter,
      critical: true,
    ),
    MetricDefinition(
      'magic__drc_error__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'magic__illegal_overlap__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'synthesis__check_error__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_error__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_device_difference__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_net_difference__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_property_fail__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_unmatched_device__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_unmatched_net__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
    MetricDefinition(
      'design__lvs_unmatched_pin__count',
      aggregator: _sum,
      higherIsBetter: false,
      critical: true,
    ),
  ],
);
