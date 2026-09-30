// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/providers.dart';
import 'package:crux_theme/src/widgets/preset_card.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Responsive grid of [PresetCard]s for the supplied preset set.
///
/// Caller supplies the ordered [presets] list (typically
/// `builtinPresets().values.toList()` plus any product-specific
/// additions); the picker reads the active theme from
/// [cruxColorThemeProvider] and renders an "active" outline around the
/// matching card. Tapping a card calls `notifier.activate(preset)`.
///
/// Layout adapts to the available width:
/// * width ≥ 900 dp → 3 columns,
/// * width ≥ 600 dp → 2 columns,
/// * width <  600 dp → 1 column.
///
/// Adopters that want a different layout can compose their own grid
/// using [PresetCard] directly.
class PresetPicker extends ConsumerWidget {
  /// Creates a preset picker.
  const PresetPicker({
    required this.presets,
    this.strings = const ThemeAppearanceStringsEn(),
    this.previewTokens,
    super.key,
  });

  /// Presets to render, in display order.
  final List<CruxColorTheme> presets;

  /// Localized strings forwarded to every card.
  final ThemeAppearanceStrings strings;

  /// Optional list of `(categoryId, tokenId)` pairs forwarded to each
  /// card's [PresetCard.previewTokens]. Use to highlight the tokens
  /// that most distinguish the host product's themes (e.g. WaveCrux
  /// surfaces `canvas.background`, `cursor.primary`, `signal.x.fill`,
  /// `signal.z.line`).
  final List<(String, String)>? previewTokens;

  int _columnCount(double width) {
    if (width >= 900) return 3;
    if (width >= 600) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (presets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(strings.noPresetsAvailableMessage),
      );
    }
    final active = ref.watch(cruxColorThemeProvider);
    final notifier = ref.read(cruxColorThemeProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            // Fixed row height sized to the card's content (title row + one
            // row of swatches + 12 dp padding) rather than a fixed aspect
            // ratio, which left the cards much taller than their content and
            // padded out with empty space at wide column widths.
            mainAxisExtent: 76,
          ),
          itemCount: presets.length,
          itemBuilder: (context, index) {
            final preset = presets[index];
            return PresetCard(
              theme: preset,
              isActive: preset.id == active.id,
              onActivate: () => notifier.activate(preset),
              strings: strings,
              previewTokens: previewTokens,
            );
          },
        );
      },
    );
  }
}
