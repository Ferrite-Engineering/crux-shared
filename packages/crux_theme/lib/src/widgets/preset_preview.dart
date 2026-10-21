// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxChromeColors;
import 'package:crux_theme/src/chrome_theme_data.dart';
import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/theme_registry.dart';
import 'package:flutter/material.dart';

/// Small fixed-grid color preview of a [CruxColorTheme].
///
/// Renders a fixed-width grid of swatches sampled from the theme so the
/// user can compare presets at a glance without applying each one. By
/// default the preview samples the first eight tokens encountered in
/// registration order across the registry's categories — adequate
/// signal for most products. Callers that want to highlight specific
/// tokens (e.g. the WaveCrux preset cards highlight `canvas.background`,
/// `cursor.primary`, `signal.x.fill`, `signal.z.line`) supply
/// [tokens] explicitly as a list of `(categoryId, tokenId)` pairs.
class PresetPreview extends StatelessWidget {
  /// Creates a preview.
  const PresetPreview({
    required this.theme,
    this.tokens,
    this.swatchSize = 14,
    this.maxSwatches = 8,
    super.key,
  });

  /// Theme to sample colors from.
  final CruxColorTheme theme;

  /// Optional ordered list of `(categoryId, tokenId)` pairs to render.
  /// When `null`, the widget walks [ThemeRegistry.instance] in
  /// registration order until it has collected [maxSwatches] tokens.
  final List<(String, String)>? tokens;

  /// Edge length of each rendered swatch in logical pixels.
  final double swatchSize;

  /// Cap on the number of swatches rendered when [tokens] is null.
  /// Ignored when the caller supplies an explicit token list.
  final int maxSwatches;

  List<(String, String)> _resolveTokens() {
    final explicit = tokens;
    if (explicit != null) return explicit;
    final picked = <(String, String)>[];
    for (final category in ThemeRegistry.instance.registeredCategories) {
      for (final descriptor in category.tokens) {
        picked.add((category.id, descriptor.id));
        if (picked.length >= maxSwatches) return picked;
      }
    }
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final pairs = _resolveTokens();
    if (pairs.isEmpty) {
      return Container(
        width: swatchSize * 4 + 6,
        height: swatchSize,
        decoration: BoxDecoration(
          color: theme.colorOr('canvas', 'background', outline),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: outline),
        ),
      );
    }
    final resolved = <Color>[
      for (final pair in pairs)
        ThemeRegistry.instance.resolve(theme, pair.$1, pair.$2) ??
            theme.colorOr(pair.$1, pair.$2, outline),
    ];
    // Built-in presets that state no tokens (Crux Dark, Crux Light) resolve
    // to the registry's transparent "use the product's value" sentinel,
    // which would paint nothing. Show the colour they actually render as.
    ThemeData? product;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (var i = 0; i < pairs.length; i++)
          Container(
            width: swatchSize,
            height: swatchSize,
            decoration: BoxDecoration(
              color: _isTransparent(resolved[i])
                  ? _productColor(
                      product ??= _productThemeFor(context, theme.brightness),
                      pairs[i],
                    )
                  : resolved[i],
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: outline, width: 0.5),
            ),
          ),
      ],
    );
  }
}

bool _isTransparent(Color c) => (c.a * 255.0).round().clamp(0, 255) == 0;

/// The colour a preset that states no value for [pair] renders as in the
/// product theme [t], mirroring what `applyChromeTokens` leaves in place.
Color _productColor(ThemeData t, (String, String) pair) {
  final s = t.colorScheme;
  if (pair.$1 != chromeCategoryId) return s.surface;
  return switch (pair.$2) {
    ChromeTokens.scaffoldBackground => t.scaffoldBackgroundColor,
    ChromeTokens.panelBackground => s.surface,
    ChromeTokens.panelHeaderBackground => s.surfaceContainerHighest,
    ChromeTokens.panelHeaderForeground => s.onSurface,
    ChromeTokens.toolbarBackground =>
      t.appBarTheme.backgroundColor ?? s.surface,
    ChromeTokens.toolbarIcon => t.appBarTheme.foregroundColor ?? s.onSurface,
    ChromeTokens.toolbarIconActive => s.primary,
    ChromeTokens.statusBarBackground => s.surfaceContainerHigh,
    ChromeTokens.statusBarForeground => s.onSurfaceVariant,
    ChromeTokens.splitter => s.outlineVariant,
    ChromeTokens.splitterHover => s.primary,
    ChromeTokens.tabBarBackground => s.surface,
    ChromeTokens.tabBarSelected => s.surfaceContainerHighest,
    ChromeTokens.tabBarLabel => s.onSurface,
    _ => s.surface,
  };
}

/// The product's own [ThemeData] for [brightness] at the platform's current
/// contrast: the matching `MaterialApp` slot (light, dark, or the
/// high-contrast pair).
///
/// The product wires its active preset's chrome tokens into those slots, so a
/// slot that carries any is not the product's base scheme. In that case, and
/// when there is no `MaterialApp`, the scheme is rebuilt from the slot's
/// primary colour (which `applyChromeTokens` never changes) at the right
/// brightness and contrast.
ThemeData _productThemeFor(BuildContext context, Brightness brightness) {
  final ambient = Theme.of(context);
  final app = context.findAncestorWidgetOfExactType<MaterialApp>();
  final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
  final dark = brightness == Brightness.dark;
  final slot = app == null
      ? null
      : dark
      ? ((highContrast ? app.highContrastDarkTheme : null) ??
            app.darkTheme ??
            app.theme)
      : ((highContrast ? app.highContrastTheme : null) ?? app.theme);
  final candidate = slot ?? (ambient.brightness == brightness ? ambient : null);
  if (candidate != null && candidate.brightness == brightness) {
    final chrome = candidate.extension<CruxChromeColors>();
    final carriesTokens =
        chrome != null &&
        (chrome.toolbarBackground != null ||
            chrome.toolbarIcon != null ||
            chrome.toolbarIconActive != null ||
            chrome.statusBarBackground != null ||
            chrome.statusBarForeground != null ||
            chrome.splitter != null ||
            chrome.splitterHover != null ||
            chrome.tabBarBackground != null ||
            chrome.tabBarSelected != null ||
            chrome.tabBarLabel != null);
    if (!carriesTokens) return candidate;
  }
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: (candidate ?? ambient).colorScheme.primary,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
    ),
  );
}
