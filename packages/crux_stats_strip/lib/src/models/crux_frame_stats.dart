// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Rolling frame-timing summary for the live statistics strip.
///
/// Derived from `SchedulerBinding.addTimingsCallback`, which reports the
/// build and raster durations the engine actually measured — not a
/// wall-clock guess taken from inside a frame.
@immutable
class CruxFrameStats {
  /// Creates a snapshot.
  const CruxFrameStats({
    required this.framesPerSecond,
    required this.lastFrameMicros,
    required this.budgetOverruns,
    required this.sampledFrames,
    required this.recentFrameMillis,
  });

  /// The empty state, before any frame has been timed.
  static const CruxFrameStats empty = CruxFrameStats(
    framesPerSecond: 0,
    lastFrameMicros: 0,
    budgetOverruns: 0,
    sampledFrames: 0,
    recentFrameMillis: <double>[],
  );

  /// Frames per second over the sampling window.
  final double framesPerSecond;

  /// Total build + raster time of the most recent frame, in microseconds.
  final int lastFrameMicros;

  /// How many sampled frames exceeded the frame budget.
  ///
  /// This is the number that matters. Average FPS hides jank — a run that
  /// holds 60 fps on average while dropping four frames during a scroll
  /// feels broken and reads as fine. The overrun count does not average
  /// the stutter away.
  final int budgetOverruns;

  /// How many frames the window has seen. Denominator for [budgetOverruns].
  final int sampledFrames;

  /// Recent per-frame totals in milliseconds, oldest first — the sparkline
  /// series.
  final List<double> recentFrameMillis;

  /// Fraction of sampled frames that overran, in `[0, 1]`.
  double get overrunRatio =>
      sampledFrames == 0 ? 0 : budgetOverruns / sampledFrames;

  @override
  String toString() =>
      'CruxFrameStats(fps: ${framesPerSecond.toStringAsFixed(1)}, '
      'overruns: $budgetOverruns/$sampledFrames)';
}
