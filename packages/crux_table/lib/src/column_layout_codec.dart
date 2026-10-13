// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_table/src/column_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `SharedPreferences` codec for a table's column widths.
///
/// Stored under [prefsKey] as one JSON object of column name to weight. A
/// column missing or unreadable in it takes its default; the others keep
/// theirs. The key and the shape are the host's existing ones, so widths
/// saved by a product's own codec are read back unchanged.
class CruxColumnLayoutCodec<C extends Enum>
    implements SettingsCodec<CruxColumnLayout<C>> {
  /// Creates the codec for [columns], storing under [prefsKey].
  const CruxColumnLayoutCodec({required this.prefsKey, required this.columns});

  /// `SharedPreferences` key holding the JSON object.
  final String prefsKey;

  /// The columns the stored weights belong to.
  final CruxTableColumns<C> columns;

  @override
  Future<CruxColumnLayout<C>> load(SharedPreferences prefs) async {
    final raw = prefs.get(prefsKey);
    if (raw is! String) return columns.defaults;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return columns.defaults;
    }
    if (decoded is! Map<String, Object?>) return columns.defaults;
    return CruxColumnLayout<C>(columns, {
      for (final column in columns.columns)
        if (decoded[column.name] case final num weight)
          column: weight.toDouble(),
    });
  }

  @override
  Future<void> save(SharedPreferences prefs, CruxColumnLayout<C> settings) =>
      prefs.setString(
        prefsKey,
        jsonEncode({
          for (final entry in settings.weights.entries)
            entry.key.name: entry.value,
        }),
      );
}
