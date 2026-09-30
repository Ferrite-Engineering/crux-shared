// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// A stable signature string for a [ShortcutActivator] so two activators that
/// trigger on the same chord compare equal (Flutter's [SingleActivator] has no
/// value equality). Non-[SingleActivator] activators get a per-instance
/// signature and therefore never collide.
String activatorSignature(ShortcutActivator activator) {
  if (activator is! SingleActivator) return 'other:${activator.hashCode}';
  return '${activator.trigger.keyId}'
      '|c=${activator.control}'
      '|m=${activator.meta}'
      '|s=${activator.shift}'
      '|a=${activator.alt}';
}

/// Returns, for each action that collides with at least one other, the list of
/// other actions sharing its chord. A colliding group whose entire membership
/// is contained in one of [intentionalShadows] is omitted (those are by-design
/// keyboard shadows, e.g. WaveCrux's Close File / Close Tab on Cmd/Ctrl+W).
///
/// Used by a product's keyboard-shortcut editor to surface a live conflict
/// warning when a rebind makes two actions share a chord.
Map<A, List<A>> findShortcutConflicts<A>(
  Map<A, ShortcutActivator> bindings, {
  Set<Set<A>> intentionalShadows = const {},
}) {
  final bySignature = <String, List<A>>{};
  bindings.forEach((action, activator) {
    bySignature
        .putIfAbsent(activatorSignature(activator), () => [])
        .add(action);
  });

  final conflicts = <A, List<A>>{};
  for (final group in bySignature.values) {
    if (group.length < 2) continue;
    final asSet = group.toSet();
    final intentional = intentionalShadows.any(
      (pair) => pair.containsAll(asSet),
    );
    if (intentional) continue;
    for (final action in group) {
      conflicts[action] = group
          .where((other) => other != action)
          .toList(growable: false);
    }
  }
  return conflicts;
}

/// The conflict view for one action caught in a (non-intentional) chord
/// collision: every [others] action sharing its chord, and the single [winner]
/// that actually fires at runtime. When `winner` equals the action this entry
/// is keyed by, that row is the one that fires; otherwise the row is *shadowed*
/// and its binding will not fire until the conflict is resolved.
@immutable
class ShortcutConflictEntry<A> {
  /// Creates a conflict entry.
  const ShortcutConflictEntry({required this.others, required this.winner});

  /// The other actions sharing this action's chord (this action excluded).
  final List<A> others;

  /// The one action in the colliding group that actually fires at runtime.
  final A winner;
}

/// The result of resolving a binding set against its defaults: the runtime
/// activator map (at most one action per chord) **plus** the per-action
/// conflict view the editor renders. Both are produced by the *same* precedence
/// pass, so the editor's "X wins / Y is shadowed" labels can never disagree
/// with which action the runtime [effectiveBindings] map actually fires.
@immutable
class ShortcutConflictResolution<A> {
  /// Creates a resolution result.
  const ShortcutConflictResolution({
    required this.effectiveBindings,
    required this.conflicts,
  });

  /// The activators to install at runtime, deduplicated so a chord maps to
  /// exactly one action (the [ShortcutConflictEntry.winner]); shadowed losers
  /// are removed. Feed this — not the raw bindings — to Flutter's `Shortcuts`,
  /// so precedence is deterministic instead of depending on map/enum iteration
  /// order.
  final Map<A, ShortcutActivator> effectiveBindings;

  /// Per-action conflict view for the editor, keyed by every action involved in
  /// a non-intentional collision. Intentional shadows are excluded (resolved in
  /// [effectiveBindings] but never surfaced as warnings).
  final Map<A, ShortcutConflictEntry<A>> conflicts;

  /// The number of distinct chords with a (non-intentional) collision — i.e.
  /// the count to show in a summary badge. Each colliding chord has exactly one
  /// winner, and an action owns a single chord, so distinct winners == distinct
  /// colliding chords.
  int get conflictChordCount =>
      conflicts.values.map((e) => e.winner).toSet().length;
}

/// Resolves [bindings] against [defaults] into a deterministic runtime map plus
/// an editor-facing conflict view (see [ShortcutConflictResolution]).
///
/// **Precedence within a colliding chord** (which action fires):
/// 1. A *customized* binding (one the user moved onto the chord — its activator
///    differs from that action's default) beats a binding the action holds *by
///    default*. This makes the user's most recent remap win, instead of the
///    previous behavior where the action declared later in the enum silently
///    won and a fresh remap appeared to do nothing.
/// 2. Ties (all default, or all customized) break by **later position in
///    [order]** — preserving prior last-wins behavior, including intentional
///    shadows (e.g. Close Tab winning Cmd/Ctrl+W over Close File). [order]
///    defaults to the iteration order of [bindings].
///
/// [intentionalShadows] groups are still resolved into
/// [ShortcutConflictResolution.effectiveBindings] but are omitted from
/// [ShortcutConflictResolution.conflicts] so the editor does
/// not warn about by-design shadows.
ShortcutConflictResolution<A> resolveShortcutConflicts<A>(
  Map<A, ShortcutActivator> bindings,
  Map<A, ShortcutActivator> defaults, {
  Iterable<A>? order,
  Set<Set<A>> intentionalShadows = const {},
}) {
  final orderList = (order ?? bindings.keys).toList();
  int rankOf(A a) => orderList.indexOf(a);

  bool isDefault(A a) {
    final cur = bindings[a];
    final def = defaults[a];
    if (cur == null || def == null) return cur == def;
    return activatorSignature(cur) == activatorSignature(def);
  }

  // `a` should win the chord over the current best `b`.
  bool beats(A a, A b) {
    final aCustom = !isDefault(a);
    final bCustom = !isDefault(b);
    if (aCustom != bCustom) return aCustom; // customized beats default
    return rankOf(a) > rankOf(b); // later declaration wins on a tie
  }

  final bySignature = <String, List<A>>{};
  bindings.forEach((action, activator) {
    bySignature
        .putIfAbsent(activatorSignature(activator), () => [])
        .add(action);
  });

  final effective = Map<A, ShortcutActivator>.of(bindings);
  final conflicts = <A, ShortcutConflictEntry<A>>{};

  for (final group in bySignature.values) {
    if (group.length < 2) continue;

    var winner = group.first;
    for (final a in group) {
      if (beats(a, winner)) winner = a;
    }

    // Runtime: only the winner keeps the chord; drop the shadowed losers so the
    // installed Shortcuts map has no ambiguous duplicate key.
    for (final a in group) {
      if (a != winner) effective.remove(a);
    }

    // UI: skip groups that are entirely a declared intentional shadow.
    final asSet = group.toSet();
    if (intentionalShadows.any((pair) => pair.containsAll(asSet))) continue;

    for (final a in group) {
      conflicts[a] = ShortcutConflictEntry<A>(
        others: group.where((o) => o != a).toList(growable: false),
        winner: winner,
      );
    }
  }

  return ShortcutConflictResolution<A>(
    effectiveBindings: effective,
    conflicts: conflicts,
  );
}
