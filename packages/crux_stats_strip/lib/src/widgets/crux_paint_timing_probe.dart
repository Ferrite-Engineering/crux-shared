// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Times how long its subtree takes to paint and reports each sample.
///
/// Wrap the widget whose render cost you want on the statistics strip:
///
/// ```dart
/// CruxPaintTimingProbe(
///   enabled: ref.watch(cruxStatsStripExpandedProvider),
///   onPaintTimed: (d) => ref
///       .read(paneRenderStatsProvider.notifier)
///       .recordPaint(paintMs: d.inMilliseconds, when: DateTime.now()),
///   child: const MyExpensiveTable(),
/// )
/// ```
///
/// ### The report is deferred out of the paint phase
///
/// Writing a provider from inside `paint()` is not allowed — the frame is
/// mid-flight and a resulting rebuild would be a mutation during layout.
/// The probe stores the duration and flushes it in a post-frame callback,
/// coalescing so a subtree that paints several times in one frame reports
/// once.
///
/// ### Never wrap the readout in its own probe
///
/// If the widget that *displays* the timing lives inside the probed
/// subtree, each report rebuilds it, which repaints the subtree, which
/// reports again — an unbounded repaint loop that looks like a hang. Keep
/// the strip outside the probe (in every current product it lives beside
/// the dock, not in it).
///
/// ### [enabled] exists so the cost is opt-in
///
/// A post-frame callback and a provider write on every frame, for a number
/// nobody is looking at, is measurement overhead bought for nothing. Hosts
/// pass the strip's expanded state so the probe is inert while collapsed.
class CruxPaintTimingProbe extends SingleChildRenderObjectWidget {
  /// Creates a probe.
  const CruxPaintTimingProbe({
    required this.onPaintTimed,
    this.enabled = true,
    super.child,
    super.key,
  });

  /// Invoked once per frame, after the frame, with the most recent paint
  /// duration of the subtree.
  final ValueChanged<Duration> onPaintTimed;

  /// When false the probe paints its child and measures nothing.
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCruxPaintTimingProbe(
        onPaintTimed: onPaintTimed,
        enabled: enabled,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCruxPaintTimingProbe renderObject,
  ) {
    renderObject
      ..onPaintTimed = onPaintTimed
      ..enabled = enabled;
  }
}

/// Render object backing [CruxPaintTimingProbe].
class RenderCruxPaintTimingProbe extends RenderProxyBox {
  /// Creates the render object.
  // Redirects to a private positional constructor so `_enabled` can be an
  // initializing formal: `this._enabled` is not usable as a *named*
  // parameter (Dart forbids private named parameters), which is what the
  // prefer_initializing_formals lint would otherwise ask for here.
  RenderCruxPaintTimingProbe({
    required ValueChanged<Duration> onPaintTimed,
    required bool enabled,
  }) : this._(onPaintTimed, enabled);

  RenderCruxPaintTimingProbe._(this.onPaintTimed, this._enabled);

  /// The report callback.
  ///
  /// A plain field rather than the usual RenderObject getter/setter pair
  /// with `markNeedsPaint`: swapping the callback does not change what the
  /// subtree looks like, and repainting for it would be measurement
  /// perturbing the thing it measures.
  ValueChanged<Duration> onPaintTimed;

  bool _enabled;

  /// Whether measurement is active.
  bool get enabled => _enabled;

  /// Turning measurement **on** forces one repaint.
  ///
  /// Without it, expanding the strip over a static screen leaves the paint
  /// segment showing "—" until something unrelated happens to redraw —
  /// which reads as a broken readout. One repaint at the moment the user
  /// asks for the number is the cost of having a number to show. Turning
  /// it *off* schedules nothing: there is no reading to produce.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) markNeedsPaint();
  }

  Duration _lastPaint = Duration.zero;
  bool _flushScheduled = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled) {
      super.paint(context, offset);
      return;
    }
    final stopwatch = Stopwatch()..start();
    super.paint(context, offset);
    stopwatch.stop();
    _lastPaint = stopwatch.elapsed;

    if (_flushScheduled) return;
    _flushScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      // The render object can be detached between the paint and the
      // callback (a pane closing mid-frame); reporting then would write
      // into a disposed container.
      if (!attached) return;
      onPaintTimed(_lastPaint);
    });
  }
}
