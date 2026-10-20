// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The Crux Desktop layout tokens, carried on the ambient `ThemeData`.
///
/// `cruxDesktopTheme` (`crux_theme`) installs this extension; a phone or
/// tablet theme does not. Its presence is therefore the one signal the
/// shared helpers read to choose their desktop presentation: the toast stack
/// over the Material snack bar, the light dialog scrim, the overflow menu's
/// "⋯" glyph metrics. The choice is made once, by `cruxThemeForDevice`, and
/// never from the window size, so a desktop window narrowed to phone width
/// keeps the desktop layer.
@immutable
class CruxDesktopTokens extends ThemeExtension<CruxDesktopTokens> {
  /// Creates the tokens. The defaults are the Crux Desktop values; only
  /// [focusRingWidth] differs in high contrast ([CruxDesktopTokens.of]
  /// callers never need to pass the others).
  const CruxDesktopTokens({
    this.controlHeight = 28,
    this.denseControlHeight = 24,
    this.rowHeight = 24,
    this.twoLineRowHeight = 40,
    this.controlRadius = 4,
    this.menuRadius = 6,
    this.dialogRadius = 8,
    this.focusRingWidth = 1.5,
    this.scrimOpacity = 0.18,
    this.bodyFontSize = 13,
    this.secondaryFontSize = 12,
    this.titleFontSize = 14,
    this.toastBottomInset = 36,
    this.toastMaxWidth = 380,
  });

  /// The high-contrast tokens: a 2.5 px focus ring, everything else equal.
  const CruxDesktopTokens.highContrast() : this(focusRingWidth: 2.5);

  /// The tokens of the ambient theme, or null when the theme is not a Crux
  /// Desktop theme (a phone or tablet theme, or a product theme not yet
  /// built on `cruxDesktopTheme`).
  static CruxDesktopTokens? of(BuildContext context) =>
      Theme.of(context).extension<CruxDesktopTokens>();

  /// Whether the ambient theme is a Crux Desktop theme.
  static bool isDesktop(BuildContext context) => of(context) != null;

  /// Height of a button, text field, dropdown or icon button.
  final double controlHeight;

  /// Control height inside dock strips and dense tables.
  final double denseControlHeight;

  /// Height of a single-line list row.
  final double rowHeight;

  /// Height of a two-line list row.
  final double twoLineRowHeight;

  /// Corner radius of controls.
  final double controlRadius;

  /// Corner radius of menus and toasts.
  final double menuRadius;

  /// Corner radius of dialogs.
  final double dialogRadius;

  /// Width of the keyboard-focus ring.
  final double focusRingWidth;

  /// Opacity of the black scrim behind a blocking dialog.
  final double scrimOpacity;

  /// Body text size.
  final double bodyFontSize;

  /// Secondary text size.
  final double secondaryFontSize;

  /// Title text size (semibold).
  final double titleFontSize;

  /// Distance from the window's bottom edge to a toast: clears the status
  /// bar with a gap.
  final double toastBottomInset;

  /// Widest a toast grows before its text wraps.
  final double toastMaxWidth;

  /// The scrim colour behind a blocking dialog.
  Color get scrimColor => Colors.black.withValues(alpha: scrimOpacity);

  @override
  CruxDesktopTokens copyWith({
    double? controlHeight,
    double? denseControlHeight,
    double? rowHeight,
    double? twoLineRowHeight,
    double? controlRadius,
    double? menuRadius,
    double? dialogRadius,
    double? focusRingWidth,
    double? scrimOpacity,
    double? bodyFontSize,
    double? secondaryFontSize,
    double? titleFontSize,
    double? toastBottomInset,
    double? toastMaxWidth,
  }) => CruxDesktopTokens(
    controlHeight: controlHeight ?? this.controlHeight,
    denseControlHeight: denseControlHeight ?? this.denseControlHeight,
    rowHeight: rowHeight ?? this.rowHeight,
    twoLineRowHeight: twoLineRowHeight ?? this.twoLineRowHeight,
    controlRadius: controlRadius ?? this.controlRadius,
    menuRadius: menuRadius ?? this.menuRadius,
    dialogRadius: dialogRadius ?? this.dialogRadius,
    focusRingWidth: focusRingWidth ?? this.focusRingWidth,
    scrimOpacity: scrimOpacity ?? this.scrimOpacity,
    bodyFontSize: bodyFontSize ?? this.bodyFontSize,
    secondaryFontSize: secondaryFontSize ?? this.secondaryFontSize,
    titleFontSize: titleFontSize ?? this.titleFontSize,
    toastBottomInset: toastBottomInset ?? this.toastBottomInset,
    toastMaxWidth: toastMaxWidth ?? this.toastMaxWidth,
  );

  /// Tokens are discrete: a theme animation switches them at the midpoint
  /// rather than producing a 26.5 px control.
  @override
  CruxDesktopTokens lerp(
    covariant ThemeExtension<CruxDesktopTokens>? other,
    double t,
  ) {
    if (other is! CruxDesktopTokens) return this;
    return t < 0.5 ? this : other;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CruxDesktopTokens &&
          other.controlHeight == controlHeight &&
          other.denseControlHeight == denseControlHeight &&
          other.rowHeight == rowHeight &&
          other.twoLineRowHeight == twoLineRowHeight &&
          other.controlRadius == controlRadius &&
          other.menuRadius == menuRadius &&
          other.dialogRadius == dialogRadius &&
          other.focusRingWidth == focusRingWidth &&
          other.scrimOpacity == scrimOpacity &&
          other.bodyFontSize == bodyFontSize &&
          other.secondaryFontSize == secondaryFontSize &&
          other.titleFontSize == titleFontSize &&
          other.toastBottomInset == toastBottomInset &&
          other.toastMaxWidth == toastMaxWidth;

  @override
  int get hashCode => Object.hash(
    controlHeight,
    denseControlHeight,
    rowHeight,
    twoLineRowHeight,
    controlRadius,
    menuRadius,
    dialogRadius,
    focusRingWidth,
    scrimOpacity,
    bodyFontSize,
    secondaryFontSize,
    titleFontSize,
    toastBottomInset,
    toastMaxWidth,
  );
}
