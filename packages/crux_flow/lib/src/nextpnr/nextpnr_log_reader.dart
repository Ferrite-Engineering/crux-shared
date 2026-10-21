// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/src/flow_verdict.dart';
import 'package:crux_flow/src/nextpnr/nextpnr_results.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';

/// Reads timing results out of a nextpnr log, for runs made without
/// `--report` (Edalize and FuseSoC do not pass it) and as a cross-check of
/// the report.
///
/// The line it reads is nextpnr's own verdict, one per clock:
///
/// ```text
/// Info: Max frequency for clock 'clk': 60.91 MHz (PASS at 12.00 MHz)
/// ERROR: Max frequency for clock 'clk': 60.91 MHz (FAIL at 1000.00 MHz)
/// ```
///
/// nextpnr prints one such line per clock after placement and another after
/// routing; the last line per clock is the result.
@immutable
class NextpnrLogReader {
  /// Creates a reader bounded by [limits].
  const NextpnrLogReader({this.limits = FlowInputLimits.defaults});

  /// The input bounds.
  final FlowInputLimits limits;

  static final RegExp _fmaxLine = RegExp(
    r"^(?:Info|Warning|ERROR):\s+Max frequency for clock '(.+)':\s+"
    r'([0-9]+(?:\.[0-9]+)?) MHz \((PASS|FAIL) at ([0-9]+(?:\.[0-9]+)?) MHz\)'
    r'\s*$',
  );

  /// Parses a whole log. Throws [FlowReadException] only when it breaks the
  /// byte limit; a log with no timing lines is a log, not an error.
  NextpnrLog parse(String text) {
    if (text.length > limits.maxBytes) {
      throw FlowReadException(
        FlowReadFailure.tooLarge,
        'log is ${text.length} characters, over the cap of ${limits.maxBytes}',
      );
    }
    final byClock = <String, NextpnrClockFrequency>{};
    String? errorLine;
    for (final raw in const LineSplitter().convert(text)) {
      if (raw.length > limits.maxLineLength) continue;
      final match = _fmaxLine.firstMatch(raw);
      if (match != null) {
        final achieved = double.parse(match.group(2)!);
        final constraint = double.parse(match.group(4)!);
        if (!achieved.isFinite || !constraint.isFinite) continue;
        final clock = match.group(1)!;
        // A later line replaces the earlier one in place, so clocks keep
        // the order they first appeared in.
        byClock[clock] = NextpnrClockFrequency(
          clock: clock,
          achievedMhz: achieved,
          constraintMhz: constraint,
          logMarker: match.group(3),
        );
      } else if (errorLine == null && raw.startsWith('ERROR:')) {
        errorLine = raw;
      }
    }
    return NextpnrLog(
      clocks: List.unmodifiable(byClock.values),
      errorLine: errorLine,
    );
  }

  /// Reads the log at [path]: [FlowVerdict.notRun] when the file is absent
  /// or unreadable, [FlowVerdict.unrecognised] when it breaks a limit,
  /// otherwise the log's own verdict.
  Future<NextpnrReading<NextpnrLog>> readFile(String path) async {
    try {
      final log = parse(await readFlowFile(path, limits));
      return NextpnrReading(verdict: log.verdict, result: log);
    } on FileSystemException catch (e) {
      return NextpnrReading(verdict: FlowVerdict.notRun, problem: e.message);
    } on FlowReadException catch (e) {
      return NextpnrReading(
        verdict: FlowVerdict.unrecognised,
        problem: e.message,
      );
    }
  }
}
