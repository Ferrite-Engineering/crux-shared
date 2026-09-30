// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:flutter/material.dart';

/// A uniform settings slider row: label + description, then a [Slider] with
/// a fixed-width value readout on the right.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
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
          ),
        ],
      ),
    );
  }
}
