// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_flow/src/flow_containment.dart';
import 'package:crux_flow/src/librelane/librelane_steps.dart';
import 'package:crux_flow/src/metrics/metric_aggregation.dart';
import 'package:crux_flow/src/metrics/metric_definition.dart';
import 'package:crux_flow/src/metrics/metrics_document.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A run's final metrics, as [LibreLaneMetricsReader] read them.
@immutable
class LibreLaneMetrics {
  /// Creates a reading.
  const LibreLaneMetrics({
    required this.values,
    required this.aggregatedKeys,
    required this.source,
    this.droppedLongKeys = 0,
    this.droppedValues = 0,
  });

  /// Every metric, after upstream aggregation, in the file's order with
  /// computed aggregates appended.
  final Map<String, Object?> values;

  /// The keys of [values] whose value aggregation computed or changed.
  final Set<String> aggregatedKeys;

  /// The file read, relative to the run root: `final/metrics.json`, or
  /// `final/metrics.csv` when the JSON is absent.
  final String source;

  /// Keys dropped for being over the length cap.
  final int droppedLongKeys;

  /// Values dropped for not being finite scalars.
  final int droppedValues;
}

/// Reads a LibreLane run's `final/metrics.json`, falling back to
/// `final/metrics.csv` when only that was kept, and folds per-corner values
/// into their bases with the metric table's aggregators (upstream
/// `aggregate_metrics`).
@immutable
class LibreLaneMetricsReader {
  /// Creates a reader bounded by [limits] that aggregates with [table].
  const LibreLaneMetricsReader({
    this.limits = FlowInputLimits.defaults,
    this.table,
  });

  /// The input bounds.
  final FlowInputLimits limits;

  /// The metric table; [librelaneMetricsV1] when null.
  final MetricDefinitionTable? table;

  /// The final metrics of the run at [runRoot], or null when it has neither
  /// file (the run stopped before `final/` was written).
  ///
  /// Throws [FlowReadException] when the file present is malformed or over
  /// a limit, and [FlowContainmentException] when it resolves outside the
  /// run root.
  LibreLaneMetrics? read(String runRoot) {
    final containment = FlowContainment(<String>[runRoot]);
    const jsonName = 'final/metrics.json';
    const csvName = 'final/metrics.csv';
    final jsonText = readOptionalFlowText(
      containment.require(p.join(runRoot, 'final', 'metrics.json')),
      limits,
    );
    final MetricsDocument document;
    final String source;
    if (jsonText != null) {
      document = MetricsDocument.parse(jsonText, limits: limits);
      source = jsonName;
    } else {
      final csvText = readOptionalFlowText(
        containment.require(p.join(runRoot, 'final', 'metrics.csv')),
        limits,
      );
      if (csvText == null) return null;
      document = parseCsv(csvText);
      source = csvName;
    }
    final folded = aggregateMetrics(document.values, table: table);
    return LibreLaneMetrics(
      values: Map.unmodifiable(folded),
      aggregatedKeys: Set.unmodifiable(<String>{
        for (final MapEntry(:key, :value) in folded.entries)
          if (!document.values.containsKey(key) ||
              document.values[key] != value)
            key,
      }),
      source: source,
      droppedLongKeys: document.droppedLongKeys,
      droppedValues: document.droppedValues,
    );
  }

  /// Parses LibreLane's `metrics.csv` (`Metric,Value` then one row per
  /// metric) into the same document `metrics.json` gives: integers, finite
  /// numbers, `True`/`False`, `None`, otherwise the text.
  MetricsDocument parseCsv(String text) {
    if (text.length > limits.maxBytes) {
      throw FlowReadException(
        FlowReadFailure.tooLarge,
        'input is ${text.length} characters, over the cap of '
        '${limits.maxBytes}',
      );
    }
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first.trim() != 'Metric,Value') {
      throw const FlowReadException(
        FlowReadFailure.malformed,
        'metrics.csv does not start with "Metric,Value"',
      );
    }
    final object = <String, Object?>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty || line.length > limits.maxLineLength) continue;
      final comma = line.indexOf(',');
      if (comma <= 0) continue;
      final key = line.substring(0, comma);
      var raw = line.substring(comma + 1);
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1).replaceAll('""', '"');
      }
      object[key] = _csvValue(raw);
    }
    return MetricsDocument.parse(jsonEncode(object), limits: limits);
  }

  static Object? _csvValue(String raw) {
    if (raw == 'None' || raw.isEmpty) return null;
    if (raw == 'True') return true;
    if (raw == 'False') return false;
    if (RegExp(r'^-?\d{1,18}$').hasMatch(raw)) return int.parse(raw);
    final d = double.tryParse(raw);
    if (d != null) return d.isFinite ? d : raw;
    return raw;
  }
}
