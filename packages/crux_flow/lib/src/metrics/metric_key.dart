// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One `name:value` modifier of a METRICS2.1 key, such as `corner:nom_tt`.
@immutable
class MetricModifier {
  /// Creates a modifier.
  const MetricModifier(this.name, this.value);

  /// The modifier's name (`corner`, `iter`).
  final String name;

  /// Its value (`nom_tt_025C_1v80`, `3`).
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MetricModifier && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);

  @override
  String toString() => '$name:$value';
}

/// A METRICS2.1 metric name split into its base and its modifiers.
///
/// `timing__setup__ws__corner:nom_tt_025C_1v80` is the base
/// `timing__setup__ws` with the modifier `corner` = `nom_tt_025C_1v80`.
/// Parsing follows upstream LibreLane's `parse_metric_modifiers` exactly:
/// trailing `__`-separated segments that contain a colon are modifiers, each
/// split at its first colon, and they keep their left-to-right order.
@immutable
class MetricKey {
  /// Creates a key.
  const MetricKey(this.base, [this.modifiers = const <MetricModifier>[]]);

  /// Parses [name], or returns null when it has no base: every segment is a
  /// modifier, which upstream's parser cannot read either.
  ///
  /// A name that repeats a modifier keeps one entry for it, in the position
  /// of its rightmost occurrence with the value of its leftmost, because
  /// that is what upstream's dictionary does; [format] then differs from
  /// [name]. Real metrics never repeat a modifier.
  static MetricKey? tryParse(String name) {
    final segments = name.split('__');
    // Popped right to left, as upstream does, into an insertion-ordered map:
    // a repeated name keeps its first (rightmost) slot and takes the later
    // (leftmost) value.
    final popped = <String, String>{};
    while (segments.isNotEmpty && segments.last.contains(':')) {
      final segment = segments.removeLast();
      final colon = segment.indexOf(':');
      popped[segment.substring(0, colon)] = segment.substring(colon + 1);
    }
    if (segments.isEmpty) return null;
    final names = popped.keys.toList().reversed;
    return MetricKey(segments.join('__'), [
      for (final n in names) MetricModifier(n, popped[n]!),
    ]);
  }

  /// The base metric name, the key into the metric definition table.
  final String base;

  /// The modifiers, in the order they appear in the name.
  final List<MetricModifier> modifiers;

  /// Whether the key carries any modifier. A key without one is a final,
  /// already-aggregated value.
  bool get isModified => modifiers.isNotEmpty;

  /// The value of the modifier called [name], or null.
  String? modifier(String name) {
    for (final m in modifiers) {
      if (m.name == name) return m.value;
    }
    return null;
  }

  /// The key in METRICS2.1 form: upstream's `Metric.modified_name`.
  String format() => [base, for (final m in modifiers) '$m'].join('__');

  @override
  bool operator ==(Object other) {
    if (other is! MetricKey || other.base != base) return false;
    if (other.modifiers.length != modifiers.length) return false;
    for (var i = 0; i < modifiers.length; i++) {
      if (other.modifiers[i] != modifiers[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(base, Object.hashAll(modifiers));

  @override
  String toString() => format();
}
