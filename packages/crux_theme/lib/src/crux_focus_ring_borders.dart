// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show lerpDouble;

import 'package:crux_a11y/crux_a11y.dart' show kCruxFocusRingGap;
import 'package:flutter/material.dart';

/// The button shape of keyboard focus under `cruxDesktopTheme`: the
/// control's rounded rectangle with its own [side], plus the Crux Desktop
/// focus [ring] standing [gap] outside it, the ring the owned controls draw
/// with `CruxFocusRing`.
///
/// A stock Material button only draws its shape, so the theme returns this
/// shape for the focused state; it paints outside its bounds and never
/// moves layout.
@immutable
class CruxFocusRingShape extends RoundedRectangleBorder {
  /// Creates the shape.
  const CruxFocusRingShape({
    required this.ring,
    super.side,
    super.borderRadius,
    this.gap = kCruxFocusRingGap,
  });

  /// The ring's colour and width.
  final BorderSide ring;

  /// The distance between the control's edge and the ring.
  final double gap;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    paintCruxFocusRing(
      canvas,
      borderRadius.resolve(textDirection).toRRect(rect),
      ring,
      gap,
    );
  }

  @override
  CruxFocusRingShape copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => CruxFocusRingShape(
    ring: ring,
    gap: gap,
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  ShapeBorder scale(double t) => CruxFocusRingShape(
    ring: ring.scale(t),
    gap: gap * t,
    side: side.scale(t),
    borderRadius: borderRadius * t,
  );

  // The ring is on or off: halfway through a shape animation it switches,
  // rather than fading through a ring-less rounded rectangle.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is CruxFocusRingShape) {
      return CruxFocusRingShape(
        ring: BorderSide.lerp(a.ring, ring, t),
        gap: lerpDouble(a.gap, gap, t)!,
        side: BorderSide.lerp(a.side, side, t),
        borderRadius: BorderRadiusGeometry.lerp(
          a.borderRadius,
          borderRadius,
          t,
        )!,
      );
    }
    return t < 0.5 ? a : this;
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is CruxFocusRingShape) return b.lerpFrom(this, t);
    return t < 0.5 ? this : b;
  }

  @override
  bool operator ==(Object other) =>
      other is CruxFocusRingShape &&
      other.side == side &&
      other.borderRadius == borderRadius &&
      other.ring == ring &&
      other.gap == gap;

  @override
  int get hashCode => Object.hash(side, borderRadius, ring, gap);
}

/// The text field border of keyboard focus under `cruxDesktopTheme`: the
/// outline in [borderSide] (the primary colour) plus the Crux Desktop focus
/// [ring] [gap] outside it.
@immutable
class CruxFocusRingInputBorder extends OutlineInputBorder {
  /// Creates the border.
  const CruxFocusRingInputBorder({
    required this.ring,
    super.borderSide,
    super.borderRadius,
    super.gapPadding,
    this.gap = kCruxFocusRingGap,
  });

  /// The ring's colour and width.
  final BorderSide ring;

  /// The distance between the field's edge and the ring.
  final double gap;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    paintCruxFocusRing(
      canvas,
      borderRadius.resolve(textDirection).toRRect(rect),
      ring,
      gap,
    );
  }

  @override
  CruxFocusRingInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) => CruxFocusRingInputBorder(
    ring: ring,
    gap: gap,
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
  );

  @override
  CruxFocusRingInputBorder scale(double t) => CruxFocusRingInputBorder(
    ring: ring.scale(t),
    gap: gap * t,
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
    gapPadding: gapPadding * t,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is CruxFocusRingInputBorder) {
      return CruxFocusRingInputBorder(
        ring: BorderSide.lerp(a.ring, ring, t),
        gap: lerpDouble(a.gap, gap, t)!,
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: lerpDouble(a.gapPadding, gapPadding, t)!,
      );
    }
    return t < 0.5 ? a : this;
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is CruxFocusRingInputBorder) return b.lerpFrom(this, t);
    return t < 0.5 ? this : b;
  }

  @override
  bool operator ==(Object other) =>
      other is CruxFocusRingInputBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius &&
      other.gapPadding == gapPadding &&
      other.ring == ring &&
      other.gap == gap;

  @override
  int get hashCode =>
      Object.hash(borderSide, borderRadius, gapPadding, ring, gap);
}

/// Strokes [ring] around [control], [gap] outside it, the corner radii
/// grown to stay concentric.
void paintCruxFocusRing(
  Canvas canvas,
  RRect control,
  BorderSide ring,
  double gap,
) {
  if (ring.style == BorderStyle.none || ring.width <= 0) return;
  final out = gap + ring.width / 2;
  canvas.drawRRect(
    control.inflate(out),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring.width
      ..color = ring.color,
  );
}
