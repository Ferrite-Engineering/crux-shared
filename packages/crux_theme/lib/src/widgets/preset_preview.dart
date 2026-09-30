// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

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
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final pair in pairs)
          Container(
            width: swatchSize,
            height: swatchSize,
            decoration: BoxDecoration(
              color:
                  ThemeRegistry.instance.resolve(theme, pair.$1, pair.$2) ??
                  theme.colorOr(pair.$1, pair.$2, outline),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: outline, width: 0.5),
            ),
          ),
      ],
    );
  }
}
