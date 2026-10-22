// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Wraps a label so it can be dragged without moving its anchor: the
/// placement model's central invariant, expressed as a gesture.
///
/// ### Claiming the pointer from the canvas underneath
///
/// A product's canvas usually reads raw pointer events through a [Listener]
/// ancestor (pan, click-to-select, cursor placement). A raw listener sees
/// every event in its subtree whatever wins the gesture arena, so a
/// `GestureDetector` here cannot stop a label drag from also panning the
/// canvas. [onClaim] is the product's flag that its canvas handler reads and
/// ignores pointers while set: true on pointer-down, false again on
/// pointer-up or cancel.
///
/// The release runs on a microtask, not synchronously. Pointer events
/// dispatch deepest-first, so this widget sees the up before the ancestor
/// does; clearing the claim synchronously would let the canvas process that
/// same event as its own and, for example, place a cursor at the release
/// point.
class CruxCalloutDraggable extends StatelessWidget {
  /// Creates the draggable.
  const CruxCalloutDraggable({
    required this.child,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onTap,
    this.onPointerDown,
    this.onClaim,
    this.cursor,
    super.key,
  });

  /// The label.
  final Widget child;

  /// A drag began. Null with [onDragUpdate] makes the label immovable.
  final VoidCallback? onDragStart;

  /// The label moved by `delta` logical pixels.
  final void Function(Offset delta)? onDragUpdate;

  /// The drag ended.
  final VoidCallback? onDragEnd;

  /// A tap that was not a drag.
  final VoidCallback? onTap;

  /// Fired on pointer-down, before any recognizer competes for the sequence.
  ///
  /// Selection belongs here rather than on [onTap]. Adding a tap recognizer
  /// beside the pan one makes the pan wait to win the arena before it emits,
  /// so a drag silently loses its first slop distance of travel. A [Listener]
  /// callback claims nothing and costs nothing.
  final VoidCallback? onPointerDown;

  /// Sets or clears the product's "a callout owns this pointer" flag. See the
  /// class documentation.
  final ValueChanged<bool>? onClaim;

  /// Pointer cursor over this affordance. Defaults to the move cursor when the
  /// label is draggable.
  final MouseCursor? cursor;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) {
      onClaim?.call(true);
      onPointerDown?.call();
    },
    onPointerUp: (_) => scheduleMicrotask(() => onClaim?.call(false)),
    onPointerCancel: (_) => scheduleMicrotask(() => onClaim?.call(false)),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
      onPanUpdate: onDragUpdate == null ? null : (d) => onDragUpdate!(d.delta),
      onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
      child: MouseRegion(
        cursor:
            cursor ??
            (onDragUpdate == null
                ? MouseCursor.defer
                : SystemMouseCursors.move),
        child: child,
      ),
    ),
  );
}
