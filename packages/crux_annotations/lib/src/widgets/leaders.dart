// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';

/// One leader line from an anchor to its label, in overlay coordinates.
@immutable
class CruxCalloutLeader {
  /// Creates a leader. [dashed] marks a drifted note.
  const CruxCalloutLeader({
    required this.from,
    required this.to,
    required this.color,
    required this.dashed,
  });

  /// The anchor end.
  final Offset from;

  /// The label end.
  final Offset to;

  /// Stroke colour.
  final Color color;

  /// Whether the line is dashed, which is how drift reads on the canvas.
  final bool dashed;

  // Value equality so `CruxCalloutLeadersPainter.shouldRepaint` can ask
  // whether the geometry actually moved. Leaders are rebuilt from scratch on
  // every layout pass, so identity comparison would always say "different"
  // and the painter would repaint on every scroll and zoom frame.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxCalloutLeader &&
          other.from == from &&
          other.to == to &&
          other.color == color &&
          other.dashed == dashed;

  @override
  int get hashCode => Object.hash(from, to, color, dashed);
}

/// Paints every leader in a single full-overlay layer beneath the labels.
///
/// One painter rather than one per annotation, because a leader spans the gap
/// between an anchor and a label that may sit anywhere on the canvas, so a
/// per-annotation layer would have to be canvas-sized, and canvas-sized layers
/// stacked on one another shadow each other during hit testing. Leaders are
/// decoration, never affordances: wrap the painter in an `IgnorePointer`.
class CruxCalloutLeadersPainter extends CustomPainter {
  /// Creates the painter.
  const CruxCalloutLeadersPainter(this.leaders);

  /// The leaders to draw, in paint order.
  final List<CruxCalloutLeader> leaders;

  @override
  void paint(Canvas canvas, Size size) {
    for (final leader in leaders) {
      final paint = Paint()
        ..color = leader.color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      if (!leader.dashed) {
        canvas.drawLine(leader.from, leader.to, paint);
        continue;
      }

      // A dashed leader marks a drifted annotation: the claim was true of a
      // different version of the design.
      const dash = 4.0;
      const gap = 3.0;
      final delta = leader.to - leader.from;
      final length = delta.distance;
      if (length <= 0) continue;
      final step = delta / length;
      var travelled = 0.0;
      while (travelled < length) {
        final segment = math.min(dash, length - travelled);
        canvas.drawLine(
          leader.from + step * travelled,
          leader.from + step * (travelled + segment),
          paint,
        );
        travelled += dash + gap;
      }
    }
  }

  // The painter's whole output is a function of [leaders], so comparing them
  // is the complete answer, and the overwhelmingly common frame on a canvas
  // that relayouts on every scroll and zoom is one where nothing moved.
  @override
  bool shouldRepaint(CruxCalloutLeadersPainter oldDelegate) =>
      !listEquals(oldDelegate.leaders, leaders);
}
