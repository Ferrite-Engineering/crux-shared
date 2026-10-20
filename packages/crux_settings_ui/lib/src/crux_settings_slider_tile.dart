// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:crux_settings_ui/src/crux_form_row.dart';
import 'package:flutter/material.dart';

/// The width of a settings slider and its readout on desktop.
const double kCruxSettingsSliderWidth = 280;

/// A uniform settings slider row: label + description, then a [Slider] with
/// a fixed-width value readout on the right. A [CruxFormRow]: on desktop the
/// slider sits at the row's end, [kCruxSettingsSliderWidth] wide; on phone
/// and tablet it runs full width under the label.
///
/// Gives every slider in a settings panel one rhythm instead of ad-hoc
/// slider-in-subtitle blocks.
class CruxSettingsSliderTile extends StatelessWidget {
  /// Creates a slider row.
  const CruxSettingsSliderTile({
    required this.title,
    required this.description,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.label,
    required this.valueText,
    required this.onChanged,
    super.key,
  });

  /// Row label.
  final String title;

  /// Secondary description shown under the [title].
  final String description;

  /// Minimum slider value.
  final double min;

  /// Maximum slider value.
  final double max;

  /// Number of discrete slider divisions.
  final int divisions;

  /// Current slider value.
  final double value;

  /// Label shown in the slider's drag bubble.
  final String label;

  /// Text rendered in the fixed-width readout to the right of the slider.
  final String valueText;

  /// Called as the user drags the slider.
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slider = Row(
      children: [
        Expanded(
          child: CruxSlider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            label: label,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: Text(
            valueText,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      // The slider keeps its own semantics node (its value indicator lives
      // in an overlay of its own), so the row does not merge it.
      child: CruxFormRow(
        label: title,
        help: description,
        mergeSemantics: false,
        child: CruxDesktopTokens.isDesktop(context)
            ? SizedBox(width: kCruxSettingsSliderWidth, child: slider)
            : slider,
      ),
    );
  }
}
