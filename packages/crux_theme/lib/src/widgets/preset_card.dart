// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/widgets/preset_preview.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';

/// Tappable card representing a single [CruxColorTheme] in the preset
/// grid.
///
/// Renders a [PresetPreview] (small swatch grid sampled from the
/// theme), the preset's [CruxColorTheme.displayName], a brightness
/// icon, and an "active" outline when [isActive] is `true`. Tapping the
/// card fires [onActivate].
class PresetCard extends StatelessWidget {
  /// Creates a preset card.
  const PresetCard({
    required this.theme,
    required this.isActive,
    required this.onActivate,
    this.strings = const ThemeAppearanceStringsEn(),
    this.previewTokens,
    super.key,
  });

  /// Theme this card represents.
  final CruxColorTheme theme;

  /// Whether this preset is currently active. Controls the outline and
  /// the `aria-current`-style semantic label rendered around the card.
  final bool isActive;

  /// Tap handler. Typically activates the preset via
  /// `cruxColorThemeProvider`'s notifier.
  final VoidCallback onActivate;

  /// Localized strings driving labels and tooltips.
  final ThemeAppearanceStrings strings;

  /// Optional explicit list of `(categoryId, tokenId)` pairs forwarded
  /// to the inner [PresetPreview]. Use to highlight the tokens that
  /// most distinguish the host product's themes.
  final List<(String, String)>? previewTokens;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final card = Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onActivate,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Tooltip(
                    message: strings.brightnessLabel(isDark: isDark),
                    child: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      size: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PresetPreview(theme: theme, tokens: previewTokens),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: strings.activatePresetTooltip,
      child: Semantics(
        label: isActive ? strings.activePresetIndicatorLabel : null,
        selected: isActive,
        child: card,
      ),
    );
  }
}
