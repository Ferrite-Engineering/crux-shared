// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/src/key_binding.dart';
import 'package:flutter/widgets.dart';

/// Pure helpers that turn a product's default bindings plus a persisted
/// **diff** map into the resolved activator map the app consumes — and back.
///
/// A product's binding notifier wires these to its own `defaultBindings()` and
/// persistence layer, keeping the notifier itself trivial. Generic over the
/// product's action type `A` (typically a `CruxAction` enum).
abstract final class KeyBindingResolver {
  /// Overlays [diffs] onto a copy of [defaults]: a non-null value rebinds, a
  /// `null` value removes the binding (explicit unbind).
  static Map<A, ShortcutActivator> resolve<A>(
    Map<A, ShortcutActivator> defaults,
    Map<A, KeyBinding?> diffs,
  ) {
    final map = Map<A, ShortcutActivator>.of(defaults);
    diffs.forEach((action, binding) {
      if (binding == null) {
        map.remove(action);
      } else {
        map[action] = binding.materialize();
      }
    });
    return map;
  }

  /// Computes the diff of [current] against [defaults] across [actions],
  /// including explicit unbinds (`null` values) where a default existed but the
  /// current map has none. This is what gets persisted and exported.
  static Map<A, KeyBinding?> diff<A>(
    Iterable<A> actions,
    Map<A, ShortcutActivator> current,
    Map<A, ShortcutActivator> defaults,
  ) {
    final diffs = <A, KeyBinding?>{};
    for (final action in actions) {
      final cur = current[action];
      final def = defaults[action];
      if (activatorsEqual(cur, def)) continue;
      // Every stored activator is a SingleActivator; a non-SingleActivator
      // cannot be serialized neutrally and is treated as an unbind.
      diffs[action] = cur is SingleActivator
          ? KeyBinding.fromActivator(cur)
          : null;
    }
    return diffs;
  }

  /// Value equality for two (nullable) activators. Two nulls are equal; two
  /// [SingleActivator]s compare by trigger + modifiers; anything else compares
  /// by identity.
  static bool activatorsEqual(ShortcutActivator? a, ShortcutActivator? b) {
    if (a == null || b == null) return a == b;
    if (a is SingleActivator && b is SingleActivator) {
      return a.trigger == b.trigger &&
          a.control == b.control &&
          a.meta == b.meta &&
          a.shift == b.shift &&
          a.alt == b.alt;
    }
    return identical(a, b);
  }
}
