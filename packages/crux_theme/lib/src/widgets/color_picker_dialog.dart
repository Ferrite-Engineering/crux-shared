// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minimal modal color picker built from Material 3 primitives.
///
/// The dialog offers three coordinated inputs over the same color:
///
/// * HSV sliders (hue 0–360°, saturation 0–100%, value 0–100%).
/// * A hex text field accepting `RRGGBB` or `RRGGBBAA` (with or without
///   a leading `#`).
/// * A read-only RGB read-out row showing the derived 0–255 channels.
///
/// A live preview swatch always reflects the currently-staged color so
/// the user can compare against the original before tapping OK. The
/// `initialColor` is preserved as a smaller "Before" swatch alongside
/// the staged "After" swatch.
///
/// The picker has no external dependencies — it intentionally avoids
/// `flutter_colorpicker` and friends so the `crux_theme` package stays
/// lightweight. Products that want richer pickers can plug their own
/// picker in via `TokenEditor` callbacks; this widget is the default.
///
/// Returns the picked [Color] when the user confirms, or `null` on
/// cancel / dismiss. Use [showColorPickerDialog] to launch the dialog
/// without instantiating the widget directly.
class ColorPickerDialog extends StatefulWidget {
  /// Creates a color picker pre-populated with [initialColor].
  const ColorPickerDialog({
    required this.initialColor,
    this.strings = const ThemeAppearanceStringsEn(),
    this.paletteSections = const <ColorPickerPaletteSection>[],
    super.key,
  });

  /// Color shown when the dialog first opens.
  final Color initialColor;

  /// Localized strings driving every label, tooltip, and error.
  final ThemeAppearanceStrings strings;

  /// Optional caller-supplied swatch sections rendered above the manual
  /// controls (e.g. a product palette quick-pick row and a preset grid).
  /// Tapping a swatch stages that color; the swatch matching the staged
  /// color renders the suite's selected treatment (check mark + glow).
  final List<ColorPickerPaletteSection> paletteSections;

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

/// One labelled swatch section for [ColorPickerDialog.paletteSections].
@immutable
class ColorPickerPaletteSection {
  /// Creates a palette section.
  const ColorPickerPaletteSection({
    required this.label,
    required this.colors,
    this.swatchSize = 20,
  });

  /// Localized section label rendered above the swatches.
  final String label;

  /// The swatches, in display order.
  final List<Color> colors;

  /// Swatch diameter (quick-pick rows read best at 32, dense grids at 20).
  final double swatchSize;
}

/// Shows [ColorPickerDialog] and returns the picked color.
///
/// Convenience entry point so callers can `await
/// showColorPickerDialog(...)` without manually wiring `showDialog`.
Future<Color?> showColorPickerDialog({
  required BuildContext context,
  required Color initialColor,
  ThemeAppearanceStrings strings = const ThemeAppearanceStringsEn(),
  List<ColorPickerPaletteSection> paletteSections =
      const <ColorPickerPaletteSection>[],
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) => ColorPickerDialog(
      initialColor: initialColor,
      strings: strings,
      paletteSections: paletteSections,
    ),
  );
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;
  String? _hexError;
  bool _syncingHexFromHsv = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: hexFromColor(_hsv.toColor()));
    _hexController.addListener(_onHexChanged);
  }

  @override
  void dispose() {
    _hexController
      ..removeListener(_onHexChanged)
      ..dispose();
    super.dispose();
  }

  void _onHexChanged() {
    if (_syncingHexFromHsv) return;
    final raw = _hexController.text.trim();
    if (raw.isEmpty) {
      setState(() => _hexError = null);
      return;
    }
    final parsed = colorFromHex(raw);
    if (parsed == null) {
      setState(() => _hexError = widget.strings.invalidHexMessage(raw));
      return;
    }
    setState(() {
      _hexError = null;
      _hsv = HSVColor.fromColor(parsed);
    });
  }

  void _setHsv(HSVColor next) {
    setState(() {
      _hsv = next;
      _syncingHexFromHsv = true;
      _hexController.text = hexFromColor(next.toColor());
      _hexController.selection = TextSelection.collapsed(
        offset: _hexController.text.length,
      );
      _syncingHexFromHsv = false;
      _hexError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final staged = _hsv.toColor();
    return AlertDialog(
      title: Text(strings.colorPickerDialogTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in widget.paletteSections) ...[
              _PaletteSection(
                section: section,
                staged: staged,
                onPick: (c) => _setHsv(HSVColor.fromColor(c)),
              ),
              const SizedBox(height: 14),
            ],
            _PreviewRow(
              before: widget.initialColor,
              after: staged,
              accessibilityLabel: strings.colorPickerPreviewLabel,
            ),
            const SizedBox(height: 16),
            _HexInput(
              controller: _hexController,
              label: strings.colorPickerHexLabel,
              errorText: _hexError,
            ),
            const SizedBox(height: 12),
            _RgbReadout(label: strings.colorPickerRgbLabel, color: staged),
            const SizedBox(height: 12),
            _HsvSliders(
              hsv: _hsv,
              strings: strings,
              onChanged: _setHsv,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.colorPickerCancelLabel),
        ),
        FilledButton(
          onPressed: _hexError != null
              ? null
              : () => Navigator.of(context).pop(_hsv.toColor()),
          child: Text(strings.colorPickerOkLabel),
        ),
      ],
    );
  }
}

class _PaletteSection extends StatelessWidget {
  const _PaletteSection({
    required this.section,
    required this.staged,
    required this.onPick,
  });

  final ColorPickerPaletteSection section;
  final Color staged;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final c in section.colors)
              _PaletteSwatch(
                color: c,
                size: section.swatchSize,
                selected: c.toARGB32() == staged.toARGB32(),
                onTap: () => onPick(c),
              ),
          ],
        ),
      ],
    );
  }
}

/// The suite's swatch circle: check mark + glow when [selected].
class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.color,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final luminance = color.computeLuminance();
    final iconColor = luminance > 0.5 ? Colors.black : Colors.white;
    final borderColor = selected
        ? iconColor
        : Colors.black.withValues(alpha: 0.25);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(Icons.check, size: size * 0.55, color: iconColor)
            : null,
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.before,
    required this.after,
    required this.accessibilityLabel,
  });

  final Color before;
  final Color after;
  final String accessibilityLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: accessibilityLabel,
      container: true,
      child: Row(
        children: [
          Expanded(child: _swatch(context, before)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _swatch(context, after, tall: true)),
        ],
      ),
    );
  }

  Widget _swatch(BuildContext context, Color color, {bool tall = false}) {
    return Container(
      height: tall ? 56 : 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

class _HexInput extends StatelessWidget {
  const _HexInput({
    required this.controller,
    required this.label,
    required this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '#',
        errorText: errorText,
        isDense: true,
      ),
      inputFormatters: _hexInputFormatters,
    );
  }
}

/// Hoisted out of `build()`: `_HexInput` rebuilds on every frame of an
/// HSV slider drag, and compiling a `RegExp` plus allocating two
/// formatter objects per frame is avoidable garbage on a drag path.
final List<TextInputFormatter> _hexInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
  LengthLimitingTextInputFormatter(8),
];

class _RgbReadout extends StatelessWidget {
  const _RgbReadout({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final a = (color.a * 255).round();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'R $r  G $g  B $b  A $a',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _HsvSliders extends StatelessWidget {
  const _HsvSliders({
    required this.hsv,
    required this.strings,
    required this.onChanged,
  });

  final HSVColor hsv;
  final ThemeAppearanceStrings strings;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LabelledSlider(
          label: strings.colorPickerHueLabel,
          value: hsv.hue,
          min: 0,
          max: 360,
          divisions: 360,
          onChanged: (v) => onChanged(hsv.withHue(v)),
        ),
        _LabelledSlider(
          label: strings.colorPickerSaturationLabel,
          value: hsv.saturation,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: (v) => onChanged(hsv.withSaturation(v)),
        ),
        _LabelledSlider(
          label: strings.colorPickerValueLabel,
          value: hsv.value,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: (v) => onChanged(hsv.withValue(v)),
        ),
      ],
    );
  }
}

class _LabelledSlider extends StatelessWidget {
  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        Expanded(
          child: CruxSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Parses a hex string like `'RRGGBB'`, `'#RRGGBB'`, `'RRGGBBAA'`, or
/// `'#RRGGBBAA'` into a [Color]. Returns `null` on any other input.
///
/// The 8-digit form reads the trailing pair as alpha (`RRGGBBAA`) — the
/// same channel order `ThemePackCodec` writes — so a hex copied out of a
/// theme-pack document pastes into the picker without silently swapping
/// alpha and red.
///
/// Exposed for use by [ColorPickerDialog] internals and by tests; the
/// parser is intentionally permissive about the leading `#` so the hex
/// input field's prefix and a pasted hex from elsewhere both round-trip.
Color? colorFromHex(String input) {
  var raw = input.trim();
  if (raw.startsWith('#')) raw = raw.substring(1);
  if (raw.length != 6 && raw.length != 8) return null;
  final parsed = int.tryParse(raw, radix: 16);
  if (parsed == null) return null;
  final argb = raw.length == 6
      ? 0xFF000000 | parsed
      // RRGGBBAA → AARRGGBB: move the trailing alpha pair to the front.
      : ((parsed & 0xFF) << 24) | (parsed >>> 8);
  return Color(argb);
}

/// Formats [color] as an upper-case 8-digit `RRGGBBAA` hex string with no
/// leading `#`, matching the channel order `ThemePackCodec` writes. Always
/// emits the alpha channel so a hex round-trip preserves transparency.
String hexFromColor(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  final a = (color.a * 255).round();
  String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  return '${two(r)}${two(g)}${two(b)}${two(a)}';
}
