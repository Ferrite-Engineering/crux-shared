// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/src/bit_ref.dart';
import 'package:crux_netlist/src/port_direction.dart';
import 'package:meta/meta.dart';

/// A module-level port: a named input/output/inout pin on the module
/// boundary.
///
/// The bit order follows Yosys's convention: index 0 is the LSB of the
/// vector. Single-bit ports have a single-element [bits] list.
@immutable
class Port {
  /// Creates a port. [bits] must be non-empty.
  const Port({
    required this.name,
    required this.direction,
    required this.bits,
  });

  /// Parses a port from the JSON shape Yosys writes under
  /// `modules.<m>.ports.<name>`.
  factory Port.fromJson(String name, Map<String, Object?> json) {
    final direction = PortDirection.fromJson(json['direction']! as String);
    final rawBits = json['bits'] as List<Object?>? ?? const <Object?>[];
    final bits = <BitRef>[
      for (final bit in rawBits) BitRef.fromJson(bit),
    ];
    return Port(name: name, direction: direction, bits: bits);
  }

  /// Port name as declared in the source HDL.
  final String name;

  /// Direction (input/output/inout) at the module boundary.
  final PortDirection direction;

  /// Bits making up this port, in LSB-first order.
  final List<BitRef> bits;

  /// Width of the port in bits — equal to `bits.length`.
  int get width => bits.length;

  /// Returns a copy with the given fields replaced.
  Port copyWith({
    String? name,
    PortDirection? direction,
    List<BitRef>? bits,
  }) {
    return Port(
      name: name ?? this.name,
      direction: direction ?? this.direction,
      bits: bits ?? this.bits,
    );
  }

  /// Yosys-compatible JSON map: `{direction, bits}`. Does not include the
  /// port's name (that key lives one level up in the enclosing map).
  Map<String, Object?> toJson() => <String, Object?>{
    'direction': direction.toJsonString(),
    'bits': <Object>[for (final bit in bits) bit.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Port) return false;
    if (other.name != name) return false;
    if (other.direction != direction) return false;
    if (other.bits.length != bits.length) return false;
    for (var i = 0; i < bits.length; i++) {
      if (other.bits[i] != bits[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(name, direction, Object.hashAll(bits));

  @override
  String toString() =>
      'Port(name: $name, direction: $direction, width: $width)';
}
