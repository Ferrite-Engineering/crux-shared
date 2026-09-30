// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:shared_preferences/shared_preferences.dart';

/// Abstract codec defining how a typed settings model [T] is read from and
/// written to `SharedPreferences`.
///
/// Each product implements this for its own per-product `AppSettings`,
/// typically delegating the cross-suite portion to `CoreSettingsCodec` and
/// adding load/save for its product-specific fields.
///
/// Codecs are responsible for:
/// 1. Choosing key names (use namespaced keys like `settings.<field>`).
/// 2. Range-clamping on read (so out-of-range values fall back to defaults).
/// 3. Enum decoding via index (`prefs.getInt(...)` → `Enum.values[index]`).
/// 4. JSON-encoded compound fields (`Map`, `List<Map>`, etc.) when needed.
abstract class SettingsCodec<T> {
  /// Reads all of [T]'s persisted fields from [prefs] and returns a fully
  /// populated value. Missing or invalid fields fall back to defaults so
  /// forward-compatible schema changes never crash.
  Future<T> load(SharedPreferences prefs);

  /// Writes all of [settings]'s fields to [prefs].
  Future<void> save(SharedPreferences prefs, T settings);
}
