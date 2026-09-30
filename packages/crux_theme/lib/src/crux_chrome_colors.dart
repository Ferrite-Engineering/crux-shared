// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The suite chrome colours Material's `ThemeData` has no slot for.
///
/// `applyChromeTokens` resolves eight of the shared `chrome` tokens into this
/// extension and installs it on the `ThemeData` it returns. The shared chrome
/// widgets read it back through [of], so a preset switch, a theme pack or a
/// token edit in Settings → Appearance repaints them the way the other six
/// chrome tokens repaint the Material surfaces:
///
/// - [toolbarIconActive] (`toolbar.iconActive`): the glyph of a toggled-on
///   `CruxToolbarButton`.
/// - [statusBarBackground] (`statusBar.background`): the `CruxStatusBar`
///   surface.
/// - [statusBarForeground] (`statusBar.foreground`): the status bar's
///   baseline text, through `CruxStatusBar.resolveTextStyle`.
/// - [splitter] (`splitter`): a `CruxIdeLayout` pane resizer at rest.
/// - [splitterHover] (`splitter.hover`): the same resizer while hovered,
///   dragged or focused.
/// - [tabBarBackground] (`tabBar.background`): the `ViewerTabBar` strip.
/// - [tabBarSelected] (`tabBar.selected`): the active `ViewerTabBar` tab.
/// - [tabBarLabel] (`tabBar.label`): every `ViewerTabBar` tab title.
///
/// A null field means the theme does not set that token (or sets the
/// transparent sentinel), and the widget keeps its own Material-derived
/// colour. That is how every built-in preset without the token renders.
@immutable
class CruxChromeColors extends ThemeExtension<CruxChromeColors> {
  /// Creates the resolved chrome colours. Every field is optional; null
  /// means "use the widget's own default".
  const CruxChromeColors({
    this.toolbarIconActive,
    this.statusBarBackground,
    this.statusBarForeground,
    this.splitter,
    this.splitterHover,
    this.tabBarBackground,
    this.tabBarSelected,
    this.tabBarLabel,
  });

  /// The resolved chrome colours of the ambient [Theme], or null when the
  /// theme was not built through `applyChromeTokens`.
  static CruxChromeColors? of(BuildContext context) =>
      Theme.of(context).extension<CruxChromeColors>();

  /// Glyph tint of a toggled-on toolbar button. Default: `ColorScheme.primary`.
  final Color? toolbarIconActive;

  /// Status bar surface. Default: `ColorScheme.surfaceContainerHighest`.
  final Color? statusBarBackground;

  /// Status bar text, painted exactly as given. Default:
  /// `ColorScheme.onSurface` at 75 % opacity.
  final Color? statusBarForeground;

  /// Pane resizer at rest. Default: `ColorScheme.outlineVariant`.
  final Color? splitter;

  /// Pane resizer while hovered, dragged or focused. Default:
  /// `ColorScheme.primary`.
  final Color? splitterHover;

  /// Document tab strip behind the tabs. Default: none (the strip is
  /// transparent over its host).
  final Color? tabBarBackground;

  /// Background of the active document tab. Default:
  /// `ColorScheme.surfaceContainerHighest`.
  final Color? tabBarSelected;

  /// Title of every document tab. Default: `TextTheme.bodyMedium`'s colour.
  final Color? tabBarLabel;

  /// Whether no field is set, so every widget keeps its own default.
  bool get isEmpty =>
      toolbarIconActive == null &&
      statusBarBackground == null &&
      statusBarForeground == null &&
      splitter == null &&
      splitterHover == null &&
      tabBarBackground == null &&
      tabBarSelected == null &&
      tabBarLabel == null;

  @override
  CruxChromeColors copyWith({
    Color? toolbarIconActive,
    Color? statusBarBackground,
    Color? statusBarForeground,
    Color? splitter,
    Color? splitterHover,
    Color? tabBarBackground,
    Color? tabBarSelected,
    Color? tabBarLabel,
  }) => CruxChromeColors(
    toolbarIconActive: toolbarIconActive ?? this.toolbarIconActive,
    statusBarBackground: statusBarBackground ?? this.statusBarBackground,
    statusBarForeground: statusBarForeground ?? this.statusBarForeground,
    splitter: splitter ?? this.splitter,
    splitterHover: splitterHover ?? this.splitterHover,
    tabBarBackground: tabBarBackground ?? this.tabBarBackground,
    tabBarSelected: tabBarSelected ?? this.tabBarSelected,
    tabBarLabel: tabBarLabel ?? this.tabBarLabel,
  );

  /// Interpolates each colour with [Color.lerp]. A field set on one side
  /// only switches at the midpoint rather than fading through transparent:
  /// null here means "the widget's own colour", which a lerp toward
  /// transparent would not reproduce.
  @override
  CruxChromeColors lerp(
    covariant ThemeExtension<CruxChromeColors>? other,
    double t,
  ) {
    if (other is! CruxChromeColors) return this;
    return CruxChromeColors(
      toolbarIconActive: _lerp(toolbarIconActive, other.toolbarIconActive, t),
      statusBarBackground: _lerp(
        statusBarBackground,
        other.statusBarBackground,
        t,
      ),
      statusBarForeground: _lerp(
        statusBarForeground,
        other.statusBarForeground,
        t,
      ),
      splitter: _lerp(splitter, other.splitter, t),
      splitterHover: _lerp(splitterHover, other.splitterHover, t),
      tabBarBackground: _lerp(tabBarBackground, other.tabBarBackground, t),
      tabBarSelected: _lerp(tabBarSelected, other.tabBarSelected, t),
      tabBarLabel: _lerp(tabBarLabel, other.tabBarLabel, t),
    );
  }

  static Color? _lerp(Color? a, Color? b, double t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    return Color.lerp(a, b, t);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CruxChromeColors &&
        other.toolbarIconActive == toolbarIconActive &&
        other.statusBarBackground == statusBarBackground &&
        other.statusBarForeground == statusBarForeground &&
        other.splitter == splitter &&
        other.splitterHover == splitterHover &&
        other.tabBarBackground == tabBarBackground &&
        other.tabBarSelected == tabBarSelected &&
        other.tabBarLabel == tabBarLabel;
  }

  @override
  int get hashCode => Object.hash(
    toolbarIconActive,
    statusBarBackground,
    statusBarForeground,
    splitter,
    splitterHover,
    tabBarBackground,
    tabBarSelected,
    tabBarLabel,
  );
}
