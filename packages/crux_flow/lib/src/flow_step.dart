// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';

/// The state of one step of a flow run, as its run directory records it.
enum FlowStepStatus {
  /// The step wrote its output state.
  completed('completed'),

  /// The run's error record names this step.
  failed('failed'),

  /// The run records that this step was skipped.
  skipped('skipped'),

  /// The newest step without output state, while the flow process lives.
  running('running'),

  /// A step of the declared flow the run has not reached.
  notStarted('not_started');

  const FlowStepStatus(this.wireName);

  /// The stable token written to JSON.
  final String wireName;

  /// The status named by [wireName].
  static FlowStepStatus fromWireName(String wireName) {
    for (final status in values) {
      if (status.wireName == wireName) return status;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown step status ${describeFlowValue(wireName)}',
    );
  }
}

/// One step of a flow run.
///
/// Steps are a sub-model of the run, read from its directory: a flow's steps
/// run in sequence, so they are not jobs of their own.
@immutable
class FlowStep {
  /// Creates a step.
  const FlowStep({
    required this.ordinal,
    required this.id,
    required this.tool,
    required this.dir,
    required this.status,
    this.runtime,
    this.logPath,
    this.metricsOut,
  });

  /// Reads a step written by [toJson].
  factory FlowStep.fromJson(Map<String, Object?> json) => FlowStep(
    ordinal: requireInt(json['ordinal'], 'ordinal'),
    id: requireString(json['id'], 'id'),
    tool: requireString(json['tool'], 'tool'),
    dir: requireString(json['dir'], 'dir'),
    status: FlowStepStatus.fromWireName(
      requireString(json['status'], 'status'),
    ),
    runtime: switch (optionalInt(json['runtime_ms'], 'runtime_ms')) {
      null => null,
      final ms => Duration(milliseconds: ms),
    },
    logPath: optionalString(json['log_path'], 'log_path'),
    metricsOut: optionalString(json['metrics_out'], 'metrics_out'),
  );

  /// Position in the run, from 1. Display order only: step directories are
  /// identified by [id], because a release that inserts a step renumbers
  /// every directory after it.
  final int ordinal;

  /// The flow's own identifier for the step.
  final String id;

  /// The tool the step ran.
  final String tool;

  /// The step's directory, relative to the run root.
  final String dir;

  /// What the run directory records about the step.
  final FlowStepStatus status;

  /// Wall time, when the run records it.
  final Duration? runtime;

  /// The step's log, relative to the run root.
  final String? logPath;

  /// The step's metrics file, relative to the run root.
  final String? metricsOut;

  /// This step as JSON; [FlowStep.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'ordinal': ordinal,
    'id': id,
    'tool': tool,
    'dir': dir,
    'status': status.wireName,
    if (runtime != null) 'runtime_ms': runtime!.inMilliseconds,
    if (logPath != null) 'log_path': logPath,
    if (metricsOut != null) 'metrics_out': metricsOut,
  };

  @override
  bool operator ==(Object other) =>
      other is FlowStep &&
      other.ordinal == ordinal &&
      other.id == id &&
      other.tool == tool &&
      other.dir == dir &&
      other.status == status &&
      other.runtime == runtime &&
      other.logPath == logPath &&
      other.metricsOut == metricsOut;

  @override
  int get hashCode =>
      Object.hash(ordinal, id, tool, dir, status, runtime, logPath, metricsOut);

  @override
  String toString() => 'FlowStep($ordinal $id ${status.wireName})';
}
