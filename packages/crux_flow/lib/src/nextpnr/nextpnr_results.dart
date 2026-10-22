// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/flow_verdict.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:meta/meta.dart';

/// One clock's achieved frequency against its constraint.
@immutable
class NextpnrClockFrequency {
  /// Creates a clock result.
  const NextpnrClockFrequency({
    required this.clock,
    required this.achievedMhz,
    required this.constraintMhz,
    this.logMarker,
  });

  /// The clock net, as nextpnr names it (the I/O buffer's output, so
  /// `clk$SB_IO_IN_$glb_clk` on iCE40 for a port called `clk`).
  final String clock;

  /// The highest frequency the placed and routed design reaches.
  final double achievedMhz;

  /// The frequency it was asked to reach.
  final double constraintMhz;

  /// `PASS` or `FAIL` as the log printed it; null when read from the report,
  /// which carries no marker.
  final String? logMarker;

  /// Whether the clock meets its constraint: from the marker when the log
  /// gave one (nextpnr compares unrounded values, the log prints two
  /// decimals), otherwise achieved at or above the constraint.
  bool get meetsConstraint => switch (logMarker) {
    'PASS' => true,
    'FAIL' => false,
    _ => achievedMhz >= constraintMhz,
  };

  @override
  bool operator ==(Object other) =>
      other is NextpnrClockFrequency &&
      other.clock == clock &&
      other.achievedMhz == achievedMhz &&
      other.constraintMhz == constraintMhz &&
      other.logMarker == logMarker;

  @override
  int get hashCode => Object.hash(clock, achievedMhz, constraintMhz, logMarker);

  @override
  String toString() =>
      'NextpnrClockFrequency($clock $achievedMhz MHz / $constraintMhz MHz)';
}

/// How much of one kind of device resource a design uses.
@immutable
class NextpnrResourceUse {
  /// Creates a usage figure.
  const NextpnrResourceUse({required this.used, required this.available});

  /// Instances the design uses.
  final int used;

  /// Instances the device has.
  final int available;

  @override
  bool operator ==(Object other) =>
      other is NextpnrResourceUse &&
      other.used == used &&
      other.available == available;

  @override
  int get hashCode => Object.hash(used, available);

  @override
  String toString() => 'NextpnrResourceUse($used / $available)';
}

/// The verdict for a set of clock results: met when there is at least one
/// clock and every clock meets its constraint, violated when any does not,
/// unrecognised when there are none (nothing was timed, so nothing can be
/// said to have met).
FlowVerdict verdictForClocks(List<NextpnrClockFrequency> clocks) {
  if (clocks.isEmpty) return FlowVerdict.unrecognised;
  return clocks.every((c) => c.meetsConstraint)
      ? FlowVerdict.met
      : FlowVerdict.violated;
}

/// What nextpnr's `report.json` (`--report`) says.
@immutable
class NextpnrReport {
  /// Creates a report.
  const NextpnrReport({
    required this.clocks,
    required this.criticalPaths,
    required this.utilization,
  });

  /// Every clock in the report's `fmax`, in report order.
  final List<NextpnrClockFrequency> clocks;

  /// The report's `critical_paths`, worst first per clock pair.
  final List<TimingPath> criticalPaths;

  /// Device resource usage by resource type.
  final Map<String, NextpnrResourceUse> utilization;

  /// Met iff every clock reaches its constraint (see [verdictForClocks]).
  FlowVerdict get verdict => verdictForClocks(clocks);
}

/// What a nextpnr log says, for runs that did not pass `--report` (the
/// Edalize default).
@immutable
class NextpnrLog {
  /// Creates a log summary.
  const NextpnrLog({required this.clocks, required this.errorLine});

  /// Each clock's last `Max frequency` line: nextpnr prints one after
  /// placement and one after routing, and the last is the final result.
  final List<NextpnrClockFrequency> clocks;

  /// The first `ERROR:` line that is not a timing result, when there is
  /// one.
  final String? errorLine;

  /// From the clocks' PASS and FAIL markers when the log has timing
  /// results; otherwise stopped when it records an error, and unrecognised
  /// when it records neither.
  FlowVerdict get verdict {
    if (clocks.isNotEmpty) return verdictForClocks(clocks);
    return errorLine != null ? FlowVerdict.stopped : FlowVerdict.unrecognised;
  }
}

/// One sink of a net in nextpnr's `detailed_net_timings`.
@immutable
class NextpnrNetEndpoint {
  /// Creates an endpoint.
  const NextpnrNetEndpoint({
    required this.maxDelayNs,
    this.cell,
    this.port,
    this.minDelayNs,
  });

  /// The cell the net reaches, as nextpnr names it.
  final String? cell;

  /// The port on [cell].
  final String? port;

  /// The smallest delay to this sink, in nanoseconds (`delay[0]`).
  final double? minDelayNs;

  /// The largest delay to this sink, in nanoseconds (`delay[1]`).
  final double maxDelayNs;

  @override
  bool operator ==(Object other) =>
      other is NextpnrNetEndpoint &&
      other.cell == cell &&
      other.port == port &&
      other.minDelayNs == minDelayNs &&
      other.maxDelayNs == maxDelayNs;

  @override
  int get hashCode => Object.hash(cell, port, minDelayNs, maxDelayNs);
}

/// One net of nextpnr's `detailed_net_timings` (`--detailed-timing-report`):
/// the cell that drives it and the delay to each of its sinks.
@immutable
class NextpnrNetTiming {
  /// Creates a net timing.
  const NextpnrNetTiming({
    required this.net,
    required this.endpoints,
    this.driver,
    this.port,
    this.sources = const <String>[],
  });

  /// The net, as nextpnr names it.
  final String net;

  /// The cell that drives the net.
  final String? driver;

  /// The driving port on [driver].
  final String? port;

  /// The Yosys `src` spans nextpnr attached to the net, verbatim; matched by
  /// suffix against a design's own sources and never opened.
  final List<String> sources;

  /// The sinks that carry a finite delay, in report order.
  final List<NextpnrNetEndpoint> endpoints;

  /// The largest delay to any sink, or null when no sink lists one.
  double? get maxDelayNs {
    double? largest;
    for (final e in endpoints) {
      if (largest == null || e.maxDelayNs > largest) largest = e.maxDelayNs;
    }
    return largest;
  }
}

/// The outcome of reading one nextpnr file from disk.
@immutable
class NextpnrReading<T extends Object> {
  /// Creates an outcome.
  const NextpnrReading({required this.verdict, this.result, this.problem});

  /// The verdict: the result's own when it was read, [FlowVerdict.notRun]
  /// when the file is absent or unreadable, [FlowVerdict.unrecognised] when
  /// it is malformed or over a limit.
  final FlowVerdict verdict;

  /// What was read, when it was.
  final T? result;

  /// Why nothing was read, when it was not.
  final String? problem;
}
