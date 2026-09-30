// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// Styling for the `CruxIdeLayout` pane resizers.
///
/// Defaults match the suite-wide resizer convention: a 6dp
/// visible bar with a 12dp hit-test zone, the bar tinted `outlineVariant` at
/// rest and `primary` on hover/focus. Null colors resolve at build time
/// against the active theme: its `splitter` chrome token at rest and its
/// `splitter.hover` token on hover, drag and focus (both read from
/// `CruxChromeColors`), then the ambient `ColorScheme`. That way the default
/// adapts to light/dark and to a theme's own splitter colours without each
/// app passing colors, and an app that passes one opts out of the theme's.
@immutable
class CruxIdeLayoutTheme {
  /// Creates a resizer theme. Null colors fall back to the theme's
  /// `splitter` / `splitter.hover` chrome tokens, then to the ambient
  /// `ColorScheme` (`outlineVariant` at rest, `primary` on hover/focus).
  const CruxIdeLayoutTheme({
    this.resizerThickness = 6,
    this.resizerHitTestThickness = 12,
    this.resizerColor,
    this.resizerHoverColor,
    this.resizerFocusedColor,
  });

  /// Visible thickness of the resizer bar, in logical pixels.
  final double resizerThickness;

  /// Hit-test thickness of the resizer (the draggable zone), in logical
  /// pixels. Wider than [resizerThickness] so the thin bar is easy to grab.
  final double resizerHitTestThickness;

  /// Resizer bar color at rest. Null → the theme's `splitter` token, then
  /// `ColorScheme.outlineVariant`.
  final Color? resizerColor;

  /// Resizer bar color while hovered or dragged. Null → the theme's
  /// `splitter.hover` token, then `ColorScheme.primary`.
  final Color? resizerHoverColor;

  /// Resizer bar color while focused. Null → the theme's `splitter.hover`
  /// token, then `ColorScheme.primary`.
  final Color? resizerFocusedColor;
}
