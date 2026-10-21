// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';

/// A flat METRICS2.1 document (`metrics.json`, `or_metrics_out.json`) after
/// the input checks: every kept key is at most
/// [FlowInputLimits.maxMetricKeyLength] characters and every kept value is a
/// finite number, a string, a boolean or null.
@immutable
class MetricsDocument {
  const MetricsDocument._(
    this.values,
    this.droppedLongKeys,
    this.droppedValues,
  );

  /// Parses [text], the whole document.
  ///
  /// The document must be one JSON object. Throws [FlowReadException] when
  /// it is not, is too large or nests too deep. A key over the length cap
  /// is dropped and counted in [droppedLongKeys]; a value that is not a
  /// finite scalar (an `1e999` that decodes to infinity, a nested object) is
  /// dropped and counted in [droppedValues]. Neither fails the document:
  /// one bad metric must not hide every good one.
  factory MetricsDocument.parse(
    String text, {
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) {
    final json = requireObject(decodeFlowJson(text, limits), 'metrics');
    final values = <String, Object?>{};
    var longKeys = 0;
    var badValues = 0;
    for (final MapEntry(:key, :value) in json.entries) {
      if (key.length > limits.maxMetricKeyLength) {
        longKeys++;
        continue;
      }
      switch (value) {
        case null || String() || bool() || int():
          values[key] = value;
        case final double d when d.isFinite:
          values[key] = d;
        default:
          badValues++;
      }
    }
    return MetricsDocument._(Map.unmodifiable(values), longKeys, badValues);
  }

  /// Reads and parses the file at [path]. Throws [FlowReadException] as
  /// [MetricsDocument.parse] does, and a file-system exception when the file
  /// is absent or unreadable.
  static Future<MetricsDocument> readFile(
    String path, {
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) async =>
      MetricsDocument.parse(await readFlowFile(path, limits), limits: limits);

  /// The kept metrics, in document order.
  final Map<String, Object?> values;

  /// Keys dropped for being longer than the cap.
  final int droppedLongKeys;

  /// Values dropped for not being finite scalars.
  final int droppedValues;
}
