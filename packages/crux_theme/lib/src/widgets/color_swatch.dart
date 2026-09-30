// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/widgets/color_picker_dialog.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';

/// Small clickable color swatch that opens [ColorPickerDialog] on tap
/// and reports the picked color back via [onColorPicked].
///
/// The swatch is a 24×24 dp filled rectangle with a 1 dp outline that
/// borrows the active theme's outline-variant color. The hit area is
/// inflated to 44 × 44 dp so the widget meets the WaveCrux mobile UI
/// standard touch-target floor even when embedded inside a dense list
/// row. Set [size] to render a larger swatch if needed; the hit area
/// always at least matches [size].
///
/// Pass [onColorPicked: null] (or omit it) for a read-only swatch.
class CruxColorSwatch extends StatelessWidget {
  /// Creates a swatch rendering [color].
  const CruxColorSwatch({
    required this.color,
    this.onColorPicked,
    this.strings = const ThemeAppearanceStringsEn(),
    this.size = 24,
    this.tooltip,
    super.key,
  });

  /// Color displayed in the swatch and pre-populated in the picker
  /// dialog when the user taps.
  final Color color;

  /// Callback fired with the newly-picked color when the user confirms
  /// the picker. When `null`, the swatch is read-only and does not open
  /// the picker.
  final ValueChanged<Color>? onColorPicked;

  /// Localized strings forwarded to [ColorPickerDialog]. Defaults to the
  /// English string set.
  final ThemeAppearanceStrings strings;

  /// Visual edge length in logical pixels. The hit area is at least
  /// `max(44, size)` to honor touch-target guidance.
  final double size;

  /// Optional tooltip rendered on hover. Defaults to the strings
  /// interface's "edit color" tooltip when [onColorPicked] is non-null.
  final String? tooltip;

  Future<void> _onTap(BuildContext context) async {
    final picked = await showColorPickerDialog(
      context: context,
      initialColor: color,
      strings: strings,
    );
    if (picked != null) onColorPicked?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hitSize = size < 44 ? 44.0 : size;
    final swatch = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
    );

    final hitArea = SizedBox(
      width: hitSize,
      height: hitSize,
      child: Center(child: swatch),
    );

    if (onColorPicked == null) {
      return Tooltip(
        message: tooltip ?? '',
        triggerMode: tooltip == null
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.tap,
        child: hitArea,
      );
    }

    return Tooltip(
      message: tooltip ?? strings.editTokenColorTooltip,
      child: InkWell(
        onTap: () => _onTap(context),
        borderRadius: BorderRadius.circular(4),
        child: hitArea,
      ),
    );
  }
}
