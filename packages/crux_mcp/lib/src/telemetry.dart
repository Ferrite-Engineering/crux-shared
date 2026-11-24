// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The one telemetry event a server records: one per call of a tool it
/// serves. Each product lists it in its own catalogue.
const String kMcpToolCallEvent = 'mcp.tool_call';

/// The `outcome` tokens of [kMcpToolCallEvent]: the six document outcomes,
/// `unreadable` for a command whose output was not a document, and
/// `crashed` for a command that threw.
const Set<String> kMcpToolCallOutcomes = <String>{
  'completed',
  'failed_gate',
  'usage_error',
  'input_error',
  'engine_error',
  'licence_error',
  'unreadable',
  'crashed',
};

/// The `duration` tokens of [kMcpToolCallEvent], shortest first.
const List<String> kMcpDurationBuckets = <String>[
  'lt_1s',
  '1s_10s',
  '10s_1m',
  '1m_10m',
  'ge_10m',
];

/// The duration bucket [elapsed] falls in.
String mcpDurationBucket(Duration elapsed) {
  if (elapsed < const Duration(seconds: 1)) return kMcpDurationBuckets[0];
  if (elapsed < const Duration(seconds: 10)) return kMcpDurationBuckets[1];
  if (elapsed < const Duration(minutes: 1)) return kMcpDurationBuckets[2];
  if (elapsed < const Duration(minutes: 10)) return kMcpDurationBuckets[3];
  return kMcpDurationBuckets[4];
}

/// Where an event goes: the product's telemetry service, as
/// `(name, properties) => service.record(TelemetryEvent(name, properties:
/// properties))`. Must never throw.
typedef McpTelemetrySink =
    void Function(String event, Map<String, Object?> properties);

/// The tool-call counter: one [kMcpToolCallEvent] per call, with three
/// properties and nothing else: `tool` (a name the server serves, never
/// what a caller typed), `outcome` (a [kMcpToolCallOutcomes] token) and
/// `duration` (a [kMcpDurationBuckets] token). Never an argument, a path, a
/// signal, a cell or any other name from a design.
///
/// Sent only under consent the product has recorded, asked through
/// [consented] on every call (for a headless binary: the desktop app's
/// recorded consent on this machine), and never when the `CI` environment
/// variable is set, whatever its value; otherwise not counted.
@immutable
class McpTelemetry {
  /// A counter that sends through [sink] when [consented] says yes and
  /// [environment] (the process environment, injectable for tests) has no
  /// `CI` variable.
  const McpTelemetry({
    required this.consented,
    required this.sink,
    required this.environment,
  });

  /// Whether the product has recorded consent to send. Asked per call.
  final bool Function() consented;

  /// Where an event goes.
  final McpTelemetrySink sink;

  /// The process environment.
  final Map<String, String> environment;

  /// Whether an event would be sent now.
  bool get sending => !environment.containsKey('CI') && consented();

  /// Records one call of [tool] that ended in [outcome] after [elapsed].
  /// Does nothing when not [sending], or when [outcome] is not a known
  /// token. Never throws.
  void toolCalled({
    required String tool,
    required String outcome,
    required Duration elapsed,
  }) {
    try {
      if (!kMcpToolCallOutcomes.contains(outcome) || !sending) return;
      sink(kMcpToolCallEvent, <String, Object?>{
        'tool': tool,
        'outcome': outcome,
        'duration': mcpDurationBucket(elapsed),
      });
    } on Object {
      // Telemetry never breaks a call.
    }
  }
}
