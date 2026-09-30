// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// The suite's four shipped UI languages, as `CoreSettings.locale` codes
/// mapped to their self-named display labels.
///
/// Language names are deliberately *not* localized: a user stuck in a
/// language they cannot read must still be able to find their own.
const Map<String, String> kCruxSupportedLocales = {
  'en': '🇺🇸  English',
  'zh_CN': '🇨🇳  中文',
  'ja': '🇯🇵  日本語',
  'ko': '🇰🇷  한국어',
};

/// The Language picker for the Appearance settings category — one shared
/// tile so every Crux app exposes the same four locales the suite ships.
///
/// The suite persists the choice in the shared `CoreSettings.locale`
/// (crux_settings); this widget only renders and reports. WaveCrux was the
/// only app that surfaced it (with these exact items hard-coded inline);
/// the other three shipped all four translations unreachable.
class CruxLocaleSettingTile extends StatelessWidget {
  /// Creates the locale tile.
  const CruxLocaleSettingTile({
    required this.label,
    required this.description,
    required this.locale,
    required this.onChanged,
    super.key,
  });

  /// Localized tile title (e.g. "Language").
  final String label;

  /// Localized tile subtitle (e.g. "Applies immediately").
  final String description;

  /// The current `CoreSettings.locale` code. Unknown codes render as
  /// English (the suite default) rather than crashing the dropdown.
  final String locale;

  /// Called with the newly selected locale code.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = kCruxSupportedLocales.containsKey(locale) ? locale : 'en';
    return ListTile(
      title: Text(label),
      subtitle: Text(description),
      trailing: DropdownButton<String>(
        key: const ValueKey('cruxLocaleDropdown'),
        value: value,
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        items: [
          for (final entry in kCruxSupportedLocales.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
      ),
    );
  }
}
