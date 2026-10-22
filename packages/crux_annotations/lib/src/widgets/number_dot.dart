// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_annotations/src/geometry.dart';
import 'package:flutter/widgets.dart';

/// A folded callout: its number on a filled circle, matched by the number its
/// panel row shows.
class CruxCalloutNumberDot extends StatelessWidget {
  /// Creates the dot.
  const CruxCalloutNumberDot({
    required this.number,
    required this.color,
    required this.onColor,
    this.selected = false,
    super.key,
  });

  /// The callout's number, assigned over the whole ordered set so it matches
  /// the panel.
  final int number;

  /// The fill.
  final Color color;

  /// The number's colour, and the selection ring's.
  final Color onColor;

  /// Whether this is the selected callout. Shown as a ring rather than a
  /// colour change, so it never collides with the drift styling: a note can
  /// be both selected and drifted, and those two facts stay separately
  /// legible.
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: kCruxCalloutDotRadius * 2,
    height: kCruxCalloutDotRadius * 2,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: selected ? Border.all(color: onColor, width: 2) : null,
    ),
    child: Text(
      '$number',
      style: TextStyle(
        color: onColor,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// The small inert circle drawn on a callout's anchor, where its leader
/// starts. Centre it on the anchor's projected point.
class CruxCalloutAnchorDot extends StatelessWidget {
  /// Creates the anchor dot.
  const CruxCalloutAnchorDot({required this.color, super.key});

  /// Diameter in logical pixels.
  static const double size = 6;

  /// The fill.
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}
