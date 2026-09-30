// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The geometry of a Crux application toolbar.
///
/// One token set for the whole suite. Before this existed, the four product
/// toolbars each hard-coded their own numbers and had drifted: three heights,
/// two divider footprints (12 dp vs 9 dp), two background roles, two border
/// edges — and one product specified no height at all, so its bar changed size
/// between the open-core and Pro builds.
@immutable
class CruxToolbarMetrics {
  /// Creates a metric set. Prefer [desktop] / [touch].
  const CruxToolbarMetrics({
    required this.height,
    required this.iconSize,
    required this.buttonSize,
    required this.dividerWidth,
    required this.dividerHeight,
    required this.horizontalPadding,
  });

  /// Desktop density: a 40 dp bar of 36 dp hit boxes around 18 dp glyphs.
  static const CruxToolbarMetrics desktop = CruxToolbarMetrics(
    height: 40,
    iconSize: 18,
    buttonSize: 36,
    dividerWidth: 12,
    dividerHeight: 20,
    horizontalPadding: 4,
  );

  /// Touch density: a 48 dp bar of 48 dp hit boxes around 24 dp glyphs, so
  /// every target clears the 44 dp minimum.
  static const CruxToolbarMetrics touch = CruxToolbarMetrics(
    height: 48,
    iconSize: 24,
    buttonSize: 48,
    dividerWidth: 16,
    dividerHeight: 24,
    horizontalPadding: 4,
  );

  /// Overall bar height.
  final double height;

  /// Glyph size inside each button.
  final double iconSize;

  /// Square hit box for each button.
  final double buttonSize;

  /// Total horizontal footprint a divider occupies, line plus its margins.
  final double dividerWidth;

  /// Height of the divider's visible line.
  final double dividerHeight;

  /// Padding at the leading and trailing ends of the button strip.
  final double horizontalPadding;
}
