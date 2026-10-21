// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/flow_kind.dart';
import 'package:crux_flow/src/flow_step.dart';
import 'package:crux_flow/src/flow_verdict.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:meta/meta.dart';

/// Which run a [FlowRun] was read from, and by which reader.
@immutable
class FlowRunRef {
  /// Creates a reference.
  const FlowRunRef({
    required this.kind,
    required this.root,
    required this.tag,
    required this.readerVersion,
    required this.verified,
  });

  /// Reads a reference written by [toJson].
  factory FlowRunRef.fromJson(Map<String, Object?> json) => FlowRunRef(
    kind: FlowKind.fromWireName(requireString(json['kind'], 'kind')),
    root: requireString(json['root'], 'root'),
    tag: requireString(json['tag'], 'tag'),
    readerVersion: requireString(json['reader_version'], 'reader_version'),
    verified: requireBool(json['verified'], 'verified'),
  );

  /// The flow that produced the run.
  final FlowKind kind;

  /// The run directory, an absolute path already checked to lie inside the
  /// location the user opened.
  final String root;

  /// The run's tag (its directory name for LibreLane).
  final String tag;

  /// The tool version line the reader that read this run was written for.
  final String readerVersion;

  /// Whether that reader was verified against this tool version. False when
  /// the run came from a version newer than any verified one and was read
  /// best-effort by the nearest older reader.
  final bool verified;

  /// This reference as JSON; [FlowRunRef.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'kind': kind.wireName,
    'root': root,
    'tag': tag,
    'reader_version': readerVersion,
    'verified': verified,
  };

  @override
  bool operator ==(Object other) =>
      other is FlowRunRef &&
      other.kind == kind &&
      other.root == root &&
      other.tag == tag &&
      other.readerVersion == readerVersion &&
      other.verified == verified;

  @override
  int get hashCode => Object.hash(kind, root, tag, readerVersion, verified);

  @override
  String toString() => 'FlowRunRef(${kind.wireName} $tag)';
}

/// One flow run as read from its directory: what it concluded, the steps it
/// took, its metrics and its worst timing paths.
@immutable
class FlowRun {
  /// Creates a run.
  const FlowRun({
    required this.ref,
    required this.verdict,
    this.steps = const <FlowStep>[],
    this.metrics = const <String, Object?>{},
    this.timing = const <TimingPath>[],
    this.artifacts = const <String, String>{},
    this.toolVersions = const <String, String>{},
    this.startedAt,
    this.finishedAt,
  });

  /// Reads a run written by [toJson].
  factory FlowRun.fromJson(Map<String, Object?> json) => FlowRun(
    ref: withFlowContext(
      'ref',
      () => FlowRunRef.fromJson(requireObject(json['ref'], 'ref')),
    ),
    verdict: FlowVerdict.fromWireName(
      requireString(json['verdict'], 'verdict'),
    ),
    steps: [
      for (final (i, s) in optionalList(json['steps'], 'steps').indexed)
        withFlowContext(
          'steps[$i]',
          () => FlowStep.fromJson(requireObject(s, 'step')),
        ),
    ],
    metrics: _scalarMap(optionalObject(json['metrics'], 'metrics')),
    timing: [
      for (final (i, p) in optionalList(json['timing'], 'timing').indexed)
        withFlowContext(
          'timing[$i]',
          () => TimingPath.fromJson(requireObject(p, 'path')),
        ),
    ],
    artifacts: json['artifacts'] == null
        ? const <String, String>{}
        : requireStringMap(json['artifacts'], 'artifacts'),
    toolVersions: json['tool_versions'] == null
        ? const <String, String>{}
        : requireStringMap(json['tool_versions'], 'tool_versions'),
    startedAt: _optionalTime(json['started_at'], 'started_at'),
    finishedAt: _optionalTime(json['finished_at'], 'finished_at'),
  );

  /// Which run this is.
  final FlowRunRef ref;

  /// What the run's own report or log concluded.
  final FlowVerdict verdict;

  /// The steps, in run order.
  final List<FlowStep> steps;

  /// Final metric values by METRICS2.1 key, in the order the tool wrote
  /// them. Values are numbers, strings, booleans or null.
  final Map<String, Object?> metrics;

  /// The worst timing paths the run reports, worst first.
  final List<TimingPath> timing;

  /// The run's output files by kind, relative to [FlowRunRef.root].
  final Map<String, String> artifacts;

  /// Tool name to the version line it printed.
  final Map<String, String> toolVersions;

  /// When the run started, when recorded.
  final DateTime? startedAt;

  /// When the run finished, when recorded.
  final DateTime? finishedAt;

  /// This run as JSON; [FlowRun.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'verdict': verdict.wireName,
    if (steps.isNotEmpty) 'steps': [for (final s in steps) s.toJson()],
    if (metrics.isNotEmpty) 'metrics': metrics,
    if (timing.isNotEmpty) 'timing': [for (final p in timing) p.toJson()],
    if (artifacts.isNotEmpty) 'artifacts': artifacts,
    if (toolVersions.isNotEmpty) 'tool_versions': toolVersions,
    if (startedAt != null) 'started_at': startedAt!.toUtc().toIso8601String(),
    if (finishedAt != null)
      'finished_at': finishedAt!.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is FlowRun &&
      other.ref == ref &&
      other.verdict == verdict &&
      listEquals(other.steps, steps) &&
      mapEquals(other.metrics, metrics) &&
      listEquals(other.timing, timing) &&
      mapEquals(other.artifacts, artifacts) &&
      mapEquals(other.toolVersions, toolVersions) &&
      _sameInstant(other.startedAt, startedAt) &&
      _sameInstant(other.finishedAt, finishedAt);

  @override
  int get hashCode => Object.hash(
    ref,
    verdict,
    Object.hashAll(steps),
    deepHash(metrics),
    Object.hashAll(timing),
    deepHash(artifacts),
    deepHash(toolVersions),
    startedAt?.microsecondsSinceEpoch,
    finishedAt?.microsecondsSinceEpoch,
  );

  @override
  String toString() => 'FlowRun(${ref.tag} ${verdict.wireName})';
}

bool _sameInstant(DateTime? a, DateTime? b) =>
    a == null ? b == null : b != null && a.isAtSameMomentAs(b);

DateTime? _optionalTime(Object? value, String field) {
  final text = optionalString(value, field);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw FlowReadException(
      FlowReadFailure.malformed,
      '"$field" is ${describeFlowValue(text)}, expected an ISO 8601 time',
    );
  }
  return parsed;
}

Map<String, Object?> _scalarMap(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    key: switch (value) {
      null || String() || bool() || int() => value,
      final double d when d.isFinite => d,
      final double _ => throw FlowReadException(
        FlowReadFailure.nonFinite,
        'metric "$key" is not a finite number',
      ),
      _ => throw FlowReadException(
        FlowReadFailure.malformed,
        'metric "$key" is ${describeFlowValue(value)}, expected a scalar',
      ),
    },
};
