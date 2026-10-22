// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/widgets.dart';

/// Fires [onDoubleTap] without entering the gesture arena.
///
/// **A `GestureDetector` cannot be used on a draggable label.** Its recognizer
/// would compete with the pan that drags the label, and a pan that has to win
/// the arena first emits nothing until it does: the drag silently loses its
/// opening slop distance of travel and the label trails the pointer for the
/// rest of the gesture. A [Listener] claims nothing, competes with nothing,
/// and leaves the pan untouched, so the pair is recognised here by hand from
/// raw pointer events.
///
/// Timing comes from [PointerEvent.timeStamp] rather than the wall clock, so
/// the widget behaves identically under a test's fake clock.
class CruxCalloutDoubleTapRegion extends StatefulWidget {
  /// Creates the region.
  const CruxCalloutDoubleTapRegion({
    required this.onDoubleTap,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  /// Null makes the region inert, which is how a read-only note refuses.
  final VoidCallback? onDoubleTap;

  /// The content.
  final Widget child;

  /// How much of the region answers a pointer.
  ///
  /// [HitTestBehavior.opaque] for a balloon, so the blank right-hand side of a
  /// short line is still a target. [HitTestBehavior.deferToChild] where the
  /// layout box is far wider than what is painted in it, so the gaps keep
  /// reaching the canvas underneath.
  final HitTestBehavior behavior;

  @override
  State<CruxCalloutDoubleTapRegion> createState() =>
      _CruxCalloutDoubleTapRegionState();
}

class _CruxCalloutDoubleTapRegionState
    extends State<CruxCalloutDoubleTapRegion> {
  Duration? _lastDown;
  Offset? _lastPosition;

  void _onPointerDown(PointerDownEvent event) {
    final last = _lastDown;
    final where = _lastPosition;
    _lastDown = event.timeStamp;
    _lastPosition = event.position;

    if (last == null || where == null) return;
    // Two presses close in both time and space. The distance check is what
    // stops a press, a drag away, and a second press elsewhere from reading as
    // a double-tap.
    if (event.timeStamp - last > kDoubleTapTimeout) return;
    if ((event.position - where).distance > kDoubleTapSlop) return;

    _lastDown = null;
    _lastPosition = null;
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _onPointerDown,
    behavior: widget.behavior,
    child: widget.child,
  );
}
