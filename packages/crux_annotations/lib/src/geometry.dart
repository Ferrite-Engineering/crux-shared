// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Maximum expanded balloons drawn before later ones render folded.
///
/// Ten open text boxes make a canvas unreadable, which defeats the point of
/// drawing on it. Past this count the rest fold to numbered dots; nothing is
/// hidden, and the panel still lists every one.
const int kCruxCalloutMaxExpanded = 6;

/// Width of an expanded callout balloon, in logical pixels.
const double kCruxCalloutBalloonWidth = 190;

/// Radius of a folded callout's numbered dot, in logical pixels.
const double kCruxCalloutDotRadius = 9;

/// The smallest distance, in logical pixels, a label is kept from the top of
/// the overlay. The default offset places a label above its anchor, which for
/// an anchor near the top edge would put it off the canvas; the leader still
/// reaches the anchor.
const double kCruxCalloutTopInset = 2;

/// How much of a callout a product draws at its current zoom.
///
/// Each product maps its own level-of-detail bands onto this; the shared
/// layer only knows the three answers.
enum CruxCalloutDetail {
  /// The balloon with its excerpt (or the dot, when folded or crowded).
  full,

  /// The numbered dot only, at a zoom where text would not be legible.
  dot,

  /// Nothing, at a zoom where even a dot would be clutter.
  hidden,
}

/// The callout layout rules both products share.
abstract final class CruxCalloutGeometry {
  /// Whether a callout draws as a numbered dot rather than a balloon.
  ///
  /// The note being edited is always expanded: a fresh note has no text yet,
  /// and every other rule here would fold it to a dot, so the editor would
  /// never appear. Otherwise a note folds when the user folded it, when it has
  /// no text, when its shape never carries a balloon ([alwaysDot]), or once
  /// [expandedSoFar] balloons have been drawn ([maxExpanded]).
  static bool isCollapsed({
    required bool isEditing,
    required bool collapsed,
    required bool hasText,
    required int expandedSoFar,
    bool alwaysDot = false,
    int maxExpanded = kCruxCalloutMaxExpanded,
  }) =>
      !isEditing &&
      (collapsed || !hasText || alwaysDot || expandedSoFar >= maxExpanded);

  /// The label's top-left corner (a balloon) or centre (a dot) for an anchor
  /// projected at [anchor], offset by ([labelDx], [labelDy]) and held
  /// [kCruxCalloutTopInset] below the top edge.
  static Offset labelOrigin(
    Offset anchor, {
    required double labelDx,
    required double labelDy,
  }) => Offset(
    anchor.dx + labelDx,
    math.max<double>(kCruxCalloutTopInset, anchor.dy + labelDy),
  );

  /// Where the leader from the anchor meets the label at [labelOrigin]: the
  /// dot's centre when [collapsed], otherwise the middle of the balloon's
  /// first line.
  static Offset leaderEnd(
    Offset labelOrigin, {
    required bool collapsed,
    double balloonWidth = kCruxCalloutBalloonWidth,
  }) => collapsed
      ? labelOrigin
      : Offset(labelOrigin.dx + balloonWidth / 2, labelOrigin.dy + 16);
}
