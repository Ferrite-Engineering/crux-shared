// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';

/// What a flow run's own report or log says about its result.
///
/// A verdict is read from the tool's report or log, never from its exit
/// status: an exit status cannot tell a timing failure from a crash.
/// Everything other than [met] is a failing result for a test runner, but
/// they are kept apart because telling "violated" from "did not complete" is
/// the point of reading the report at all.
enum FlowVerdict {
  /// The run completed and every check it reports passed: for nextpnr, every
  /// clock reached its constraint.
  met('met'),

  /// The run completed and reported a violation: a clock below its
  /// constraint, a negative slack, a non-zero violation count. A finding
  /// about the design, not an error.
  violated('violated'),

  /// The run ended before producing its final results.
  stopped('stopped'),

  /// There is no result to read: the report or log is absent or could not be
  /// opened.
  notRun('not_run'),

  /// A result exists but does not say anything this package can classify:
  /// malformed, truncated, or a shape no reader knows.
  unrecognised('unrecognised');

  const FlowVerdict(this.wireName);

  /// The stable token written to JSON and telemetry (`[a-z0-9_]`).
  final String wireName;

  /// Whether this is [met], the only passing verdict.
  bool get isMet => this == met;

  /// The verdict named by [wireName].
  static FlowVerdict fromWireName(String wireName) {
    for (final verdict in values) {
      if (verdict.wireName == wireName) return verdict;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown flow verdict ${describeFlowValue(wireName)}',
    );
  }
}
