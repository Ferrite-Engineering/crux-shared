// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart' show Module;
import 'package:crux_netlist/src/bit_ref.dart';
import 'package:crux_netlist/src/module.dart' show Module;
import 'package:meta/meta.dart';

/// A named net inside a [Module] — the Yosys equivalent of a `wire` /
/// `signal`. Carries a vector of [bits] in LSB-first order and any source
/// attributes attached to the declaration.
@immutable
class Net {
  /// Creates a named net.
  const Net({
    required this.name,
    required this.bits,
    required this.attributes,
    this.hideName = false,
  });

  /// Parses a net from the JSON shape Yosys writes under
  /// `modules.<m>.netnames.<name>`.
  factory Net.fromJson(String name, Map<String, Object?> json) {
    final hideName = (json['hide_name'] as int? ?? 0) != 0;
    final rawBits = json['bits'] as List<Object?>? ?? const <Object?>[];
    final bits = <BitRef>[
      for (final bit in rawBits) BitRef.fromJson(bit),
    ];
    final attributesRaw =
        json['attributes'] as Map<String, Object?>? ?? const {};
    final attributes = <String, String>{
      for (final entry in attributesRaw.entries)
        entry.key: entry.value?.toString() ?? '',
    };
    return Net(
      name: name,
      bits: bits,
      attributes: attributes,
      hideName: hideName,
    );
  }

  /// Net name as declared in the source HDL (or auto-generated when
  /// [hideName] is true).
  final String name;

  /// Bits making up this net, in LSB-first order.
  final List<BitRef> bits;

  /// Source attributes attached to the net (e.g. `src`, `keep`).
  final Map<String, String> attributes;

  /// Whether Yosys auto-generated the name (true) or it came from the
  /// source HDL (false).
  final bool hideName;

  /// Width of the net in bits.
  int get width => bits.length;

  /// Returns a copy with the given fields replaced.
  Net copyWith({
    String? name,
    List<BitRef>? bits,
    Map<String, String>? attributes,
    bool? hideName,
  }) {
    return Net(
      name: name ?? this.name,
      bits: bits ?? this.bits,
      attributes: attributes ?? this.attributes,
      hideName: hideName ?? this.hideName,
    );
  }

  /// Yosys-compatible JSON map. Does not include the net's name (that key
  /// lives one level up in the enclosing map).
  Map<String, Object?> toJson() => <String, Object?>{
    'hide_name': hideName ? 1 : 0,
    'bits': <Object>[for (final bit in bits) bit.toJson()],
    'attributes': attributes,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Net) return false;
    if (other.name != name) return false;
    if (other.hideName != hideName) return false;
    if (other.bits.length != bits.length) return false;
    for (var i = 0; i < bits.length; i++) {
      if (other.bits[i] != bits[i]) return false;
    }
    if (other.attributes.length != attributes.length) return false;
    for (final entry in attributes.entries) {
      if (other.attributes[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    hideName,
    Object.hashAll(bits),
    _mapHash(attributes),
  );

  @override
  String toString() => 'Net(name: $name, width: $width)';
}

int _mapHash<K, V>(Map<K, V> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
