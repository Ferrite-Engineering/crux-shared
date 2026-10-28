// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart' show Module;
import 'package:crux_netlist/src/json_shape.dart';
import 'package:crux_netlist/src/module.dart' show Module;
import 'package:meta/meta.dart';

/// A memory declared in a [Module]: an entry of Yosys's `memories` section,
/// which `write_json` emits for a design that has been through `proc` but not
/// yet through the `memory` passes (afterwards the memory is a `$mem_v2`
/// cell and this section is empty).
///
/// Its accesses are `$memrd` and `$memwr` cells naming it by their `MEMID`
/// parameter; this holds the declaration: its name, shape and source span.
@immutable
class Memory {
  /// Creates a memory.
  const Memory({
    required this.name,
    this.width = 0,
    this.size = 0,
    this.startOffset = 0,
    this.attributes = const <String, String>{},
    this.hideName = false,
  });

  /// Parses a memory from the JSON shape Yosys writes under
  /// `modules.<m>.memories.<name>`.
  ///
  /// Throws [FormatException], naming the field, when a field has the wrong
  /// JSON type.
  factory Memory.fromJson(String name, Map<String, Object?> json) {
    final attributesRaw = optionalJsonObject(json, 'attributes');
    return Memory(
      name: name,
      width: _readInt(json['width']),
      size: _readInt(json['size']),
      startOffset: _readInt(json['start_offset']),
      attributes: <String, String>{
        for (final entry in attributesRaw.entries)
          entry.key: jsonScalarString(entry.value, 'attributes.${entry.key}'),
      },
      hideName: readHideName(json),
    );
  }

  /// Memory name as declared in the source HDL (or auto-generated when
  /// [hideName] is true).
  final String name;

  /// Bits per word.
  final int width;

  /// Number of words.
  final int size;

  /// The address of the first word.
  final int startOffset;

  /// Source attributes attached to the declaration (e.g. `src`).
  final Map<String, String> attributes;

  /// Whether Yosys auto-generated the name (true) or it came from the
  /// source HDL (false).
  final bool hideName;

  /// Yosys-compatible JSON map. Does not include the memory's name (that key
  /// lives one level up in the enclosing map).
  Map<String, Object?> toJson() => <String, Object?>{
    'hide_name': hideName ? 1 : 0,
    'attributes': attributes,
    'width': width,
    'start_offset': startOffset,
    'size': size,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Memory) return false;
    if (other.name != name ||
        other.width != width ||
        other.size != size ||
        other.startOffset != startOffset ||
        other.hideName != hideName ||
        other.attributes.length != attributes.length) {
      return false;
    }
    for (final entry in attributes.entries) {
      if (other.attributes[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var attributesHash = 0;
    for (final entry in attributes.entries) {
      attributesHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(
      name,
      width,
      size,
      startOffset,
      hideName,
      attributesHash,
    );
  }

  @override
  String toString() => 'Memory(name: $name, width: $width, size: $size)';
}

/// An integer Yosys wrote as a JSON number, or tolerated as a numeric string;
/// 0 for anything else.
int _readInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v) ?? 0,
  _ => 0,
};
