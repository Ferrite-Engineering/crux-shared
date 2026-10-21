// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/src/crux_desktop_tokens.dart';
import 'package:flutter/material.dart';

/// The metrics and colours the owned Crux Desktop controls draw with, all
/// taken from the ambient theme: sizes from [CruxDesktopTokens] (their
/// defaults when the theme carries none), colours from the [ColorScheme],
/// so a product seed or a theme pack carries through.
@immutable
class CruxControlStyle {
  const CruxControlStyle._({
    required this.height,
    required this.radius,
    required this.menuRadius,
    required this.face,
    required this.border,
    required this.borderStrong,
    required this.label,
    required this.labelSecondary,
    required this.labelDisabled,
    required this.selectedFill,
    required this.onSelected,
    required this.focus,
    required this.overlay,
    required this.menuSurface,
    required this.error,
    required this.value,
    required this.button,
  });

  /// The style of the ambient theme; [dense] takes the dock-strip height.
  factory CruxControlStyle.of(BuildContext context, {bool dense = false}) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final tokens = CruxDesktopTokens.of(context) ?? const CruxDesktopTokens();
    final dark = s.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final size = tokens.bodyFontSize;
    final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: FontWeight.w400,
      color: s.onSurface,
    );
    return CruxControlStyle._(
      height: dense ? tokens.denseControlHeight : tokens.controlHeight,
      radius: tokens.controlRadius,
      menuRadius: tokens.menuRadius,
      // Light: a white face with a border, which reads as a control on
      // Windows, GNOME, KDE and macOS alike. Dark: the highest container.
      face: dark ? s.surfaceContainerHighest : s.surfaceContainerLowest,
      border: highContrast ? s.outline : s.outlineVariant,
      borderStrong: highContrast ? s.onSurface : s.outline,
      label: s.onSurface,
      labelSecondary: s.onSurfaceVariant,
      labelDisabled: s.onSurface.withValues(alpha: 0.38),
      // The secondary container is close to white in light, so the light
      // selection takes the dimmer fixed tone: a clear step from the face.
      selectedFill: dark ? s.secondaryContainer : s.secondaryFixedDim,
      onSelected: dark ? s.onSecondaryContainer : s.onSecondaryFixed,
      focus: s.primary,
      overlay: s.onSurface,
      menuSurface: dark ? s.surfaceContainerHighest : s.surface,
      error: s.error,
      value: body,
      button: body.copyWith(fontWeight: FontWeight.w500),
    );
  }

  /// Control height.
  final double height;

  /// Control corner radius.
  final double radius;

  /// Menu corner radius.
  final double menuRadius;

  /// A neutral control's face.
  final Color face;

  /// The 1 px border at rest.
  final Color border;

  /// The border on hover and press.
  final Color borderStrong;

  /// Label and value text.
  final Color label;

  /// Secondary text and the chevron.
  final Color labelSecondary;

  /// Text of a disabled control.
  final Color labelDisabled;

  /// The selected segment's face.
  final Color selectedFill;

  /// The selected segment's label.
  final Color onSelected;

  /// The focus ring.
  final Color focus;

  /// The hover and press overlay colour.
  final Color overlay;

  /// A menu's surface.
  final Color menuSurface;

  /// The error border.
  final Color error;

  /// Values: 13 px regular.
  final TextStyle value;

  /// Segment labels: 13 px medium.
  final TextStyle button;

  /// [base] under the hover overlay (6 %).
  Color hover(Color base) =>
      Color.alphaBlend(overlay.withValues(alpha: 0.06), base);

  /// [base] under the pressed overlay (12 %): darker in light, lighter in
  /// dark, never the other way round.
  Color pressed(Color base) =>
      Color.alphaBlend(overlay.withValues(alpha: 0.12), base);

  /// [base] at half alpha, for a disabled face.
  Color disabled(Color base) => base.withValues(alpha: base.a * 0.5);
}
