// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:meta/meta.dart';

/// A delay in nanoseconds as integer picoseconds, rounded to nearest.
///
/// Throws [FlowReadException] for a non-finite delay or one too large for an
/// integer, rather than storing a value nothing can compare.
int nanosecondsToPicoseconds(double ns) {
  if (!ns.isFinite || ns.abs() > 9e12) {
    throw FlowReadException(
      FlowReadFailure.nonFinite,
      'delay $ns ns is not a representable time',
    );
  }
  return (ns * 1000).round();
}

/// What kind of delay one segment of a timing path is.
///
/// The set of segment types a tool writes is open: nextpnr's iCE40 and ECP5
/// reports use `clk-to-q`, `logic`, `routing`, `setup` and `source`, Gowin
/// writes no `source`, and GateMate adds `clk-skew`. A type outside this enum
/// reads as [other], with the tool's own word kept in
/// [TimingSegment.rawType].
enum TimingSegmentType {
  /// Clock-to-output of the launching register.
  clkToQ('clk-to-q'),

  /// Interconnect between two cells.
  routing('routing'),

  /// Delay through a cell.
  logic('logic'),

  /// Setup requirement at the capturing register.
  setup('setup'),

  /// Hold requirement at the capturing register.
  hold('hold'),

  /// Any other type, named by [TimingSegment.rawType].
  other('other');

  const TimingSegmentType(this.wireName);

  /// The stable token written to JSON; also the nextpnr spelling for every
  /// type but [other].
  final String wireName;

  /// The type for a tool's own word, [other] when it is not one of ours.
  static TimingSegmentType fromToolWord(String word) {
    for (final type in values) {
      if (type != other && type.wireName == word) return type;
    }
    return other;
  }
}

/// Which reader produced a timing path.
enum TimingPathOrigin {
  /// nextpnr's `report.json` `critical_paths`.
  nextpnrReport('nextpnr_report'),

  /// An OpenSTA path report.
  openSta('opensta');

  const TimingPathOrigin(this.wireName);

  /// The stable token written to JSON.
  final String wireName;

  /// The origin named by [wireName].
  static TimingPathOrigin fromWireName(String wireName) {
    for (final origin in values) {
      if (origin.wireName == wireName) return origin;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown timing path origin ${describeFlowValue(wireName)}',
    );
  }
}

/// The clock edge a path end is timed against.
enum ClockEdge {
  /// The rising edge (`posedge`).
  rising('rising'),

  /// The falling edge (`negedge`).
  falling('falling');

  const ClockEdge(this.wireName);

  /// The stable token written to JSON.
  final String wireName;

  /// The edge named by [wireName].
  static ClockEdge fromWireName(String wireName) {
    for (final edge in values) {
      if (edge.wireName == wireName) return edge;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown clock edge ${describeFlowValue(wireName)}',
    );
  }
}

/// One segment of a timing path.
@immutable
class TimingSegment {
  /// Creates a segment.
  const TimingSegment({
    required this.type,
    required this.rawType,
    required this.fromCell,
    required this.toCell,
    required this.delayPs,
    required this.delayNs,
    this.fromPort,
    this.toPort,
    this.net,
    this.sources = const <String>[],
  });

  /// Reads a segment written by [toJson].
  factory TimingSegment.fromJson(Map<String, Object?> json) {
    final rawType = requireString(json['raw_type'], 'raw_type');
    return TimingSegment(
      type: TimingSegmentType.fromToolWord(rawType),
      rawType: rawType,
      fromCell: requireString(json['from_cell'], 'from_cell'),
      fromPort: optionalString(json['from_port'], 'from_port'),
      toCell: requireString(json['to_cell'], 'to_cell'),
      toPort: optionalString(json['to_port'], 'to_port'),
      net: optionalString(json['net'], 'net'),
      delayPs: requireInt(json['delay_ps'], 'delay_ps'),
      delayNs: requireFinite(json['delay_ns'], 'delay_ns'),
      sources: json['sources'] == null
          ? const <String>[]
          : requireStringList(json['sources'], 'sources'),
    );
  }

  /// The segment type.
  final TimingSegmentType type;

  /// The tool's own word for the type, kept for display and for the types
  /// [type] reads as [TimingSegmentType.other].
  final String rawType;

  /// The cell the segment starts at, as the tool names it.
  final String fromCell;

  /// The port on [fromCell], when the tool names it.
  final String? fromPort;

  /// The cell the segment ends at, as the tool names it.
  final String toCell;

  /// The port on [toCell], when the tool names it.
  final String? toPort;

  /// The net a routing segment runs on.
  final String? net;

  /// The delay, rounded to integer picoseconds. Comparisons use this.
  final int delayPs;

  /// The delay exactly as the tool wrote it, in nanoseconds. Display uses
  /// this.
  final double delayNs;

  /// The Yosys `src` spans the tool attached, verbatim. They may be absolute
  /// paths of the machine that ran synthesis; they are matched by suffix
  /// against a design's own sources and never opened directly.
  final List<String> sources;

  /// This segment as JSON; [TimingSegment.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'raw_type': rawType,
    'from_cell': fromCell,
    if (fromPort != null) 'from_port': fromPort,
    'to_cell': toCell,
    if (toPort != null) 'to_port': toPort,
    if (net != null) 'net': net,
    'delay_ps': delayPs,
    'delay_ns': delayNs,
    if (sources.isNotEmpty) 'sources': sources,
  };

  @override
  bool operator ==(Object other) =>
      other is TimingSegment &&
      other.type == type &&
      other.rawType == rawType &&
      other.fromCell == fromCell &&
      other.fromPort == fromPort &&
      other.toCell == toCell &&
      other.toPort == toPort &&
      other.net == net &&
      other.delayPs == delayPs &&
      other.delayNs == delayNs &&
      listEquals(other.sources, sources);

  @override
  int get hashCode => Object.hash(
    type,
    rawType,
    fromCell,
    fromPort,
    toCell,
    toPort,
    net,
    delayPs,
    delayNs,
    deepHash(sources),
  );

  @override
  String toString() => 'TimingSegment($rawType $fromCell -> $toCell)';
}

/// One timing path: where it starts and ends, how long it takes, and the
/// segments it is made of.
@immutable
class TimingPath {
  /// Creates a path.
  const TimingPath({
    required this.rank,
    required this.startpoint,
    required this.endpoint,
    required this.delayPs,
    required this.delayNs,
    required this.segments,
    required this.origin,
    this.clockFrom,
    this.fromEdge,
    this.clockTo,
    this.toEdge,
    this.slackPs,
  });

  /// Reads a path written by [toJson].
  factory TimingPath.fromJson(Map<String, Object?> json) => TimingPath(
    rank: requireInt(json['rank'], 'rank'),
    clockFrom: optionalString(json['clock_from'], 'clock_from'),
    fromEdge: switch (optionalString(json['from_edge'], 'from_edge')) {
      null => null,
      final s => ClockEdge.fromWireName(s),
    },
    clockTo: optionalString(json['clock_to'], 'clock_to'),
    toEdge: switch (optionalString(json['to_edge'], 'to_edge')) {
      null => null,
      final s => ClockEdge.fromWireName(s),
    },
    startpoint: requireString(json['startpoint'], 'startpoint'),
    endpoint: requireString(json['endpoint'], 'endpoint'),
    slackPs: optionalInt(json['slack_ps'], 'slack_ps'),
    delayPs: requireInt(json['delay_ps'], 'delay_ps'),
    delayNs: requireFinite(json['delay_ns'], 'delay_ns'),
    segments: [
      for (final (i, s) in requireList(json['segments'], 'segments').indexed)
        withFlowContext(
          'segments[$i]',
          () => TimingSegment.fromJson(requireObject(s, 'segment')),
        ),
    ],
    origin: TimingPathOrigin.fromWireName(
      requireString(json['origin'], 'origin'),
    ),
  );

  /// Position in the report's own order, from 1 (1 is the worst path the
  /// report lists).
  final int rank;

  /// The clock the path is launched by; null for a path from an unclocked
  /// input.
  final String? clockFrom;

  /// The edge of [clockFrom] the path is launched on.
  final ClockEdge? fromEdge;

  /// The clock the path is captured by; null for a path to an unclocked
  /// output.
  final String? clockTo;

  /// The edge of [clockTo] the path is captured on.
  final ClockEdge? toEdge;

  /// The cell the path starts at, as the tool names it.
  final String startpoint;

  /// The cell the path ends at, as the tool names it.
  final String endpoint;

  /// The slack in picoseconds, when the report states one. nextpnr's report
  /// does not.
  final int? slackPs;

  /// The path delay, rounded to integer picoseconds.
  final int delayPs;

  /// The path delay in nanoseconds, the sum of the segments' raw delays.
  final double delayNs;

  /// The segments, in path order.
  final List<TimingSegment> segments;

  /// The reader that produced this path.
  final TimingPathOrigin origin;

  /// This path as JSON; [TimingPath.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'rank': rank,
    if (clockFrom != null) 'clock_from': clockFrom,
    if (fromEdge != null) 'from_edge': fromEdge!.wireName,
    if (clockTo != null) 'clock_to': clockTo,
    if (toEdge != null) 'to_edge': toEdge!.wireName,
    'startpoint': startpoint,
    'endpoint': endpoint,
    if (slackPs != null) 'slack_ps': slackPs,
    'delay_ps': delayPs,
    'delay_ns': delayNs,
    'segments': [for (final s in segments) s.toJson()],
    'origin': origin.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is TimingPath &&
      other.rank == rank &&
      other.clockFrom == clockFrom &&
      other.fromEdge == fromEdge &&
      other.clockTo == clockTo &&
      other.toEdge == toEdge &&
      other.startpoint == startpoint &&
      other.endpoint == endpoint &&
      other.slackPs == slackPs &&
      other.delayPs == delayPs &&
      other.delayNs == delayNs &&
      listEquals(other.segments, segments) &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(
    rank,
    clockFrom,
    fromEdge,
    clockTo,
    toEdge,
    startpoint,
    endpoint,
    slackPs,
    delayPs,
    delayNs,
    Object.hashAll(segments),
    origin,
  );

  @override
  String toString() => 'TimingPath(#$rank $startpoint -> $endpoint)';
}
