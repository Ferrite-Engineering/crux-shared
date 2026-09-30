// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/src/models/crux_frame_stats.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many frames the rolling window keeps.
const int kCruxFrameStatsWindow = 60;

/// Frame budget above which a frame counts as an overrun.
///
/// 16.67 ms is the 60 Hz budget. Products run on 120 Hz displays too, where
/// the real budget is half this — but a strip that reported overruns on a
/// 120 Hz panel for every frame between 8 and 16 ms would cry wolf
/// constantly, since 16 ms still renders smoothly to the eye. The strip is
/// an ambient "is something wrong" signal, not a profiler.
const Duration kCruxFrameBudget = Duration(microseconds: 16667);

/// Minimum gap between publications of the frame statistics.
///
/// The strip watches this provider, so publishing on every frame put the app
/// in a loop that fed itself: new state → strip rebuild → a frame → a
/// timings callback → new state. An idle window with the strip open rendered
/// flat out, which is a strange thing for a *performance* monitor to do.
///
/// Two updates a second is faster than anyone reads a number and slow enough
/// that the loop dies out between them. Frames are still counted on every
/// callback — only the publication is throttled, so the history, the frame
/// tally and the overrun tally stay exact.
const Duration kCruxFrameStatsPublishInterval = Duration(milliseconds: 500);

/// Rolling frame statistics, root-scope.
///
/// Registers a `SchedulerBinding` timings callback for the app's lifetime.
/// The callback is cheap (it appends to a bounded list) and the provider is
/// deliberately **not** auto-disposed: FPS history that resets every time
/// the user collapses the strip would make the sparkline useless exactly
/// when they open it to look at a stutter they just saw.
class CruxFrameStatsNotifier extends Notifier<CruxFrameStats> {
  final List<double> _recent = <double>[];
  int _overruns = 0;
  int _sampled = 0;
  int _lastMicros = 0;

  /// Time since the last publication. Monotonic, so a system clock change
  /// cannot stall the readout for hours or flood it.
  final Stopwatch _sincePublish = Stopwatch();

  /// Minimum gap between publications. Settable so a test can drive the
  /// throttle instead of waiting out real milliseconds.
  @visibleForTesting
  Duration publishInterval = kCruxFrameStatsPublishInterval;

  @override
  CruxFrameStats build() {
    // A test binding may not have a scheduler with timings support; guard so
    // the provider stays constructible in unit tests.
    final binding = SchedulerBinding.instance..addTimingsCallback(_onTimings);
    ref.onDispose(() {
      binding.removeTimingsCallback(_onTimings);
      _sincePublish.stop();
    });
    return CruxFrameStats.empty;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    for (final timing in timings) {
      final micros = timing.totalSpan.inMicroseconds;
      _lastMicros = micros;
      _sampled++;
      if (micros > kCruxFrameBudget.inMicroseconds) _overruns++;
      _recent.add(micros / 1000.0);
      if (_recent.length > kCruxFrameStatsWindow) _recent.removeAt(0);
    }
    _publishThrottled();
  }

  /// Publishes the accumulated statistics, unless the last publication was
  /// too recent.
  ///
  /// The first batch always publishes: a strip opened onto a dash for half a
  /// second looks broken, and there is no loop to damp until state has moved
  /// at least once.
  void _publishThrottled() {
    if (_sincePublish.isRunning && _sincePublish.elapsed < publishInterval) {
      return;
    }
    _sincePublish
      ..reset()
      ..start();
    _publish();
  }

  void _publish() {
    // FPS from the mean frame time over the window rather than a frame
    // count per wall-second: an idle app produces no frames at all, and a
    // wall-clock rate would report 0 fps for a perfectly healthy window in
    // which nothing needed redrawing.
    final meanMillis = _recent.isEmpty
        ? 0.0
        : _recent.reduce((a, b) => a + b) / _recent.length;
    final fps = meanMillis <= 0 ? 0.0 : 1000.0 / meanMillis;

    state = CruxFrameStats(
      framesPerSecond: fps,
      lastFrameMicros: _lastMicros,
      budgetOverruns: _overruns,
      sampledFrames: _sampled,
      recentFrameMillis: List<double>.unmodifiable(_recent),
    );
  }

  /// Clears the window and the overrun tally.
  ///
  /// The counters are cumulative for the session, so a user who wants to
  /// answer "does *this* action drop frames" needs a way to zero them
  /// without restarting the app.
  void reset() {
    _recent.clear();
    _overruns = 0;
    _sampled = 0;
    _lastMicros = 0;
    // Publishing an empty state immediately, and letting the next frame
    // publish too: a reset the user asked for must show up at once, and the
    // tally it zeroed must start climbing again visibly.
    _sincePublish
      ..reset()
      ..stop();
    state = CruxFrameStats.empty;
  }

  /// Feeds [timings] through the real accumulation path.
  @visibleForTesting
  void debugRecordTimings(List<FrameTiming> timings) => _onTimings(timings);
}

/// The app-wide frame statistics.
final NotifierProvider<CruxFrameStatsNotifier, CruxFrameStats>
cruxFrameStatsProvider =
    NotifierProvider<CruxFrameStatsNotifier, CruxFrameStats>(
      CruxFrameStatsNotifier.new,
    );
