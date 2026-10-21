// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_flow/src/flow_verdict.dart';
import 'package:crux_flow/src/nextpnr/nextpnr_results.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:meta/meta.dart';

/// Reads nextpnr's `report.json`, written with `--report`.
///
/// One reader serves every architecture nextpnr places: the iCE40 and ECP5
/// back ends and the himbaechel ones (Gowin, GateMate) write the same four
/// sections with the same shapes. What differs is vocabulary, which the
/// reader keeps rather than interprets: segment types it has not seen read
/// as [TimingSegmentType.other] with the word kept, and cell names are kept
/// verbatim, opaque or not.
///
/// `detailed_net_timings` is not read here; it is large and only the slack
/// overlay wants it. Unknown keys are ignored.
@immutable
class NextpnrReportReader {
  /// Creates a reader bounded by [limits].
  const NextpnrReportReader({this.limits = FlowInputLimits.defaults});

  /// The input bounds.
  final FlowInputLimits limits;

  /// Parses a whole `report.json`. Throws [FlowReadException] when it is not
  /// a nextpnr report or breaks a limit.
  NextpnrReport parse(String text) {
    final json = requireObject(decodeFlowJson(text, limits), 'report');
    final fmax = requireObject(json['fmax'], 'fmax');
    final clocks = [
      for (final MapEntry(:key, :value) in fmax.entries)
        withFlowContext('fmax.$key', () {
          final entry = requireObject(value, key);
          return NextpnrClockFrequency(
            clock: key,
            achievedMhz: requireFinite(entry['achieved'], 'achieved'),
            constraintMhz: requireFinite(entry['constraint'], 'constraint'),
          );
        }),
    ];
    final paths = [
      for (final (i, p) in optionalList(
        json['critical_paths'],
        'critical_paths',
      ).indexed)
        withFlowContext(
          'critical_paths[$i]',
          () => _path(requireObject(p, 'path'), i + 1),
        ),
    ];
    final utilization = {
      for (final MapEntry(:key, :value) in optionalObject(
        json['utilization'],
        'utilization',
      ).entries)
        key: withFlowContext('utilization.$key', () {
          final entry = requireObject(value, key);
          return NextpnrResourceUse(
            used: requireInt(entry['used'], 'used'),
            available: requireInt(entry['available'], 'available'),
          );
        }),
    };
    return NextpnrReport(
      clocks: List.unmodifiable(clocks),
      criticalPaths: List.unmodifiable(paths),
      utilization: Map.unmodifiable(utilization),
    );
  }

  /// Reads the report at [path]: [FlowVerdict.notRun] when the file is
  /// absent or unreadable, [FlowVerdict.unrecognised] when it is malformed,
  /// otherwise the report's own verdict.
  Future<NextpnrReading<NextpnrReport>> readFile(String path) async {
    final String text;
    try {
      text = await readFlowFile(path, limits);
    } on FileSystemException catch (e) {
      return NextpnrReading(verdict: FlowVerdict.notRun, problem: e.message);
    } on FlowReadException catch (e) {
      return NextpnrReading(
        verdict: FlowVerdict.unrecognised,
        problem: e.message,
      );
    }
    try {
      final report = parse(text);
      return NextpnrReading(verdict: report.verdict, result: report);
    } on FlowReadException catch (e) {
      return NextpnrReading(
        verdict: FlowVerdict.unrecognised,
        problem: e.message,
      );
    }
  }

  TimingPath _path(Map<String, Object?> json, int rank) {
    final (fromEdge, clockFrom) = _event(requireString(json['from'], 'from'));
    final (toEdge, clockTo) = _event(requireString(json['to'], 'to'));
    final steps = requireList(json['path'], 'path');
    if (steps.isEmpty) {
      throw const FlowReadException(
        FlowReadFailure.malformed,
        '"path" has no segments',
      );
    }
    final segments = [
      for (final (i, s) in steps.indexed)
        withFlowContext('path[$i]', () => _segment(requireObject(s, 'step'))),
    ];
    final delayNs = segments.fold<double>(0, (sum, s) => sum + s.delayNs);
    return TimingPath(
      rank: rank,
      clockFrom: clockFrom,
      fromEdge: fromEdge,
      clockTo: clockTo,
      toEdge: toEdge,
      startpoint: segments.first.fromCell,
      endpoint: segments.last.toCell,
      delayPs: nanosecondsToPicoseconds(delayNs),
      delayNs: delayNs,
      segments: List.unmodifiable(segments),
      origin: TimingPathOrigin.nextpnrReport,
    );
  }

  TimingSegment _segment(Map<String, Object?> json) {
    final rawType = requireString(json['type'], 'type');
    final delayNs = requireFinite(json['delay'], 'delay');
    final from = requireObject(json['from'], 'from');
    final to = requireObject(json['to'], 'to');
    return TimingSegment(
      type: TimingSegmentType.fromToolWord(rawType),
      rawType: rawType,
      fromCell: requireString(from['cell'], 'from.cell'),
      fromPort: optionalString(from['port'], 'from.port'),
      toCell: requireString(to['cell'], 'to.cell'),
      toPort: optionalString(to['port'], 'to.port'),
      net: optionalString(json['net'], 'net'),
      delayPs: nanosecondsToPicoseconds(delayNs),
      delayNs: delayNs,
      sources: json['sources'] == null
          ? const <String>[]
          : List.unmodifiable(requireStringList(json['sources'], 'sources')),
    );
  }

  /// `posedge <clock>`, `negedge <clock>` or `<async>`.
  static (ClockEdge?, String?) _event(String event) {
    if (event.startsWith('posedge ')) {
      return (ClockEdge.rising, event.substring('posedge '.length));
    }
    if (event.startsWith('negedge ')) {
      return (ClockEdge.falling, event.substring('negedge '.length));
    }
    if (event == '<async>') return (null, null);
    return (null, event);
  }
}
