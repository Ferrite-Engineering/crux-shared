// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/src/cell.dart';
import 'package:crux_netlist/src/net.dart';
import 'package:crux_netlist/src/port.dart';
import 'package:meta/meta.dart';

/// One module in an elaborated Yosys netlist.
///
/// Modules in Yosys JSON live under `modules.<name>` and own a flat set of
/// [ports] (module boundary), [cells] (internal instances), and [nets]
/// (`netnames` in Yosys-speak — named wires). [attributes] surfaces the
/// `attributes` map at the module level (typically `src`, `top`, `keep`).
@immutable
class Module {
  /// Creates a module.
  const Module({
    required this.name,
    required this.attributes,
    required this.ports,
    required this.cells,
    required this.nets,
  });

  /// Parses a module from the JSON shape Yosys writes at
  /// `modules.<name>`.
  factory Module.fromJson(String name, Map<String, Object?> json) {
    final attributesRaw =
        json['attributes'] as Map<String, Object?>? ?? const {};
    final attributes = <String, String>{
      for (final entry in attributesRaw.entries)
        entry.key: entry.value?.toString() ?? '',
    };
    final portsRaw = json['ports'] as Map<String, Object?>? ?? const {};
    final ports = <String, Port>{
      for (final entry in portsRaw.entries)
        entry.key: Port.fromJson(
          entry.key,
          entry.value! as Map<String, Object?>,
        ),
    };
    final cellsRaw = json['cells'] as Map<String, Object?>? ?? const {};
    final cells = <String, Cell>{
      for (final entry in cellsRaw.entries)
        entry.key: Cell.fromJson(
          entry.key,
          entry.value! as Map<String, Object?>,
        ),
    };
    final netsRaw = json['netnames'] as Map<String, Object?>? ?? const {};
    final nets = <String, Net>{
      for (final entry in netsRaw.entries)
        entry.key: Net.fromJson(
          entry.key,
          entry.value! as Map<String, Object?>,
        ),
    };
    return Module(
      name: name,
      attributes: attributes,
      ports: ports,
      cells: cells,
      nets: nets,
    );
  }

  /// Module name.
  final String name;

  /// Attributes attached to the module (e.g. `top: '1'`).
  final Map<String, String> attributes;

  /// Module-boundary ports, keyed by port name.
  final Map<String, Port> ports;

  /// Cell instances inside the module, keyed by cell instance name.
  final Map<String, Cell> cells;

  /// Named nets inside the module, keyed by net name. Anonymous nets (bits
  /// not assigned to any named net) are not represented here.
  final Map<String, Net> nets;

  /// True when Yosys marked this module as the top of the design hierarchy
  /// (`top` attribute set to a non-zero value).
  ///
  /// Yosys writes the attribute as a binary string whose width depends on
  /// the version: 8 bits in older releases (`"00000001"`), 32 bits in 0.65+
  /// (`"00000000000000000000000000000001"`), or sometimes a plain `"1"`.
  /// Match any non-empty string whose bits sum to non-zero so the
  /// "this is the top" signal survives across Yosys versions without us
  /// having to track every encoding tweak.
  bool get isTop => _attributeIsSet('top');

  /// Whether this module is a black box: a cell-library primitive whose body
  /// is not part of the design, such as the `SB_LUT4` and `SB_DFF` modules a
  /// `synth_ice40` run leaves behind from reading the iCE40 cell library, or
  /// any module marked `(* blackbox *)` / `(* whitebox *)`.
  ///
  /// A black box is a leaf: its instances are cells to draw and trace, not
  /// scopes to push into, and its own ports and specify blocks are not a
  /// schematic anyone wants. Read from the `blackbox` and `whitebox`
  /// attributes with the same encoding tolerance as [isTop].
  bool get isBlackBox =>
      _attributeIsSet('blackbox') || _attributeIsSet('whitebox');

  bool _attributeIsSet(String key) {
    final raw = attributes[key];
    if (raw == null || raw.isEmpty) return false;
    // Strip non-digits (just in case) and read as a number — a plain
    // "1" / "00000001" / "00...01" / "5" all signal top. Zero values
    // (empty `top: "0"` or `top: ""`) read as false.
    for (final code in raw.codeUnits) {
      // ASCII '0' = 0x30. Any character other than '0' makes the
      // attribute non-zero. Yosys never writes whitespace into the
      // binary string, so we can take the cheap path.
      if (code != 0x30) return true;
    }
    return false;
  }

  /// Returns a copy with the given fields replaced.
  Module copyWith({
    String? name,
    Map<String, String>? attributes,
    Map<String, Port>? ports,
    Map<String, Cell>? cells,
    Map<String, Net>? nets,
  }) {
    return Module(
      name: name ?? this.name,
      attributes: attributes ?? this.attributes,
      ports: ports ?? this.ports,
      cells: cells ?? this.cells,
      nets: nets ?? this.nets,
    );
  }

  /// Yosys-compatible JSON map. Does not include the module's name (that
  /// key lives one level up in the enclosing map).
  Map<String, Object?> toJson() => <String, Object?>{
    'attributes': attributes,
    'ports': <String, Object?>{
      for (final entry in ports.entries) entry.key: entry.value.toJson(),
    },
    'cells': <String, Object?>{
      for (final entry in cells.entries) entry.key: entry.value.toJson(),
    },
    'netnames': <String, Object?>{
      for (final entry in nets.entries) entry.key: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Module) return false;
    if (other.name != name) return false;
    if (!_mapEquals(other.attributes, attributes)) return false;
    if (!_mapEquals(other.ports, ports)) return false;
    if (!_mapEquals(other.cells, cells)) return false;
    if (!_mapEquals(other.nets, nets)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    _mapHash(attributes),
    _mapHash(ports),
    _mapHash(cells),
    _mapHash(nets),
  );

  @override
  String toString() =>
      'Module(name: $name, ports: ${ports.length}, '
      'cells: ${cells.length}, nets: ${nets.length})';
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
