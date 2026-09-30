// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/src/crux_settings_control_tile.dart';
import 'package:flutter/material.dart';

/// The auto-reload mode selector for the General settings category — one
/// shared control so every Crux app presents the same segmented
/// prompt / auto / off choice in the same order.
///
/// Before this, the same `AutoReloadMode` enum shipped in three different
/// presentations: WaveCrux segmented prompt/auto/off, NetCrux + LintCrux
/// segmented auto/prompt/off, SimCrux a dropdown. WaveCrux's order is
/// canonical: prompt (the default) leads.
class CruxAutoReloadSettingTile extends StatelessWidget {
  /// Creates the auto-reload tile.
  const CruxAutoReloadSettingTile({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.promptLabel,
    required this.autoLabel,
    required this.offLabel,
    super.key,
  });

  /// Localized tile title (e.g. "When a loaded file changes on disk").
  final String label;

  /// Localized tile subtitle.
  final String description;

  /// The current mode.
  final AutoReloadMode value;

  /// Called with the newly selected mode.
  final ValueChanged<AutoReloadMode> onChanged;

  /// Localized segment label for [AutoReloadMode.prompt].
  final String promptLabel;

  /// Localized segment label for [AutoReloadMode.auto].
  final String autoLabel;

  /// Localized segment label for [AutoReloadMode.off].
  final String offLabel;

  @override
  Widget build(BuildContext context) {
    return CruxSettingsControlTile(
      title: label,
      description: description,
      control: SegmentedButton<AutoReloadMode>(
        key: const ValueKey('cruxAutoReloadSegments'),
        segments: [
          ButtonSegment(
            value: AutoReloadMode.prompt,
            label: Text(promptLabel),
          ),
          ButtonSegment(value: AutoReloadMode.auto, label: Text(autoLabel)),
          ButtonSegment(value: AutoReloadMode.off, label: Text(offLabel)),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}
