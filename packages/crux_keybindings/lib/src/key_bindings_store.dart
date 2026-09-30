// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/src/key_binding.dart';
import 'package:crux_keybindings/src/keymap_codec.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a product's keyboard-shortcut customization set (diffs from
/// default) to `SharedPreferences` under a single namespaced key, generic over
/// the product's [CruxAction] enum.
///
/// Every operation is best-effort: a missing platform plugin (unit tests),
/// corrupt JSON, or an I/O error resolves to "no customizations" on load and a
/// silent no-op on save, so a storage problem degrades to platform defaults
/// rather than crashing the app.
class KeyBindingsStore<A extends CruxAction> {
  /// Creates a store backed by [codec]. Pass [prefsOverride] in tests to bypass
  /// the platform plugin; override [preferenceKey] only if a product needs a
  /// distinct storage slot.
  KeyBindingsStore({
    required this.codec,
    this.preferenceKey = 'settings.shortcutBindings',
    this.prefsOverride,
  });

  /// Serializer for this product's actions.
  final KeymapCodec<A> codec;

  /// The `SharedPreferences` key the diff payload is stored under.
  final String preferenceKey;

  /// Test-only `SharedPreferences` instance. When null, the platform singleton
  /// is resolved on each call.
  final SharedPreferences? prefsOverride;

  /// Loads the persisted customization diffs. Returns an empty map when nothing
  /// is stored, the payload is corrupt, or storage is unavailable.
  ///
  /// Propagates [KeymapSchemaVersionException]: a stored keymap written by a
  /// newer build must be refused loudly, not treated as "no customizations" —
  /// swallowing it would wipe the user's bindings on the next save after a
  /// downgrade. Callers surface the refusal (and skip saving) instead.
  Future<Map<A, KeyBinding?>> load() async {
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      final raw = prefs.getString(preferenceKey);
      if (raw == null || raw.isEmpty) return {};
      return codec.decodeString(raw);
    } on KeymapSchemaVersionException {
      rethrow;
    } on Object {
      return {};
    }
  }

  /// Persists [diffs]. An empty map clears the stored value (back to all
  /// defaults). Failures are swallowed — persistence must never crash a UI
  /// interaction.
  Future<void> save(Map<A, KeyBinding?> diffs) async {
    try {
      final prefs = prefsOverride ?? await SharedPreferences.getInstance();
      if (diffs.isEmpty) {
        await prefs.remove(preferenceKey);
      } else {
        await prefs.setString(preferenceKey, codec.encodeToString(diffs));
      }
    } on Object {
      // Best-effort: a write failure leaves the in-memory state intact.
    }
  }
}
