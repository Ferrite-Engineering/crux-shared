// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart' show Net;
import 'package:crux_netlist/src/net.dart' show Net;
import 'package:meta/meta.dart';

/// A reference to a single bit in a Yosys netlist.
///
/// In Yosys's `write_json` output a bit is either a numeric net identifier
/// (e.g. `42`) referring to a [Net], or a string literal representing a
/// constant value (`"0"`, `"1"`, `"x"`, or `"z"`). This sealed type is the
/// canonical Dart representation: every parsed bit is exactly one of the
/// two variants below.
@immutable
sealed class BitRef {
  const BitRef._();

  /// Parses one element of a Yosys `bits` array.
  ///
  /// Accepts:
  ///   * `int` → [NetBit] with `netId == value`.
  ///   * `String` of `"0"|"1"|"x"|"z"` → [ConstantBit].
  ///   * Numeric strings (`"42"`) → [NetBit] after parsing.
  ///
  /// Anything else throws [FormatException] so corrupt JSON surfaces at the
  /// parser layer rather than silently producing the wrong netlist.
  factory BitRef.fromJson(Object? value) {
    if (value is int) {
      return NetBit(value);
    }
    if (value is String) {
      switch (value) {
        case '0':
          return const ConstantBit(ConstantBitValue.zero);
        case '1':
          return const ConstantBit(ConstantBitValue.one);
        case 'x':
        case 'X':
          return const ConstantBit(ConstantBitValue.x);
        case 'z':
        case 'Z':
          return const ConstantBit(ConstantBitValue.z);
      }
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return NetBit(parsed);
      }
    }
    throw FormatException('Unrecognized Yosys bit reference: $value');
  }

  /// Serializes back to the Yosys-compatible JSON representation.
  Object toJson();
}

/// A bit that refers to a net by its integer net id.
@immutable
final class NetBit extends BitRef {
  /// Creates a net-bit reference.
  const NetBit(this.netId) : super._();

  /// The integer net id used by Yosys to identify the carrier wire/net.
  final int netId;

  @override
  Object toJson() => netId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is NetBit && other.netId == netId);

  @override
  int get hashCode => Object.hash(NetBit, netId);

  @override
  String toString() => 'NetBit($netId)';
}

/// A bit driven by a constant value (`0`, `1`, `x`, or `z`).
@immutable
final class ConstantBit extends BitRef {
  /// Creates a constant-bit reference.
  const ConstantBit(this.value) : super._();

  /// The constant value carried by this bit.
  final ConstantBitValue value;

  @override
  Object toJson() {
    switch (value) {
      case ConstantBitValue.zero:
        return '0';
      case ConstantBitValue.one:
        return '1';
      case ConstantBitValue.x:
        return 'x';
      case ConstantBitValue.z:
        return 'z';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ConstantBit && other.value == value);

  @override
  int get hashCode => Object.hash(ConstantBit, value);

  @override
  String toString() => 'ConstantBit(${toJson()})';
}

/// The four constant values a bit can take in a Yosys netlist.
enum ConstantBitValue {
  /// Logic 0.
  zero,

  /// Logic 1.
  one,

  /// Unknown (X).
  x,

  /// High-impedance (Z).
  z,
}
