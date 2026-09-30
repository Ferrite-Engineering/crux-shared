// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart';
import 'package:test/test.dart';

/// [BitRef] and [PortDirection] parsing, which had no coverage until 2026-08.
///
/// These two carry the only real decision-making in the netlist value types:
/// Yosys encodes a bit reference three different ways in the same array, and
/// a wrong reading here silently produces the wrong netlist rather than an
/// error — a constant driver read as a net id, or vice versa, changes what the
/// schematic shows without anything failing.
void main() {
  group('BitRef.fromJson', () {
    test('an integer is a net id', () {
      expect(BitRef.fromJson(0), const NetBit(0));
      expect(BitRef.fromJson(42), const NetBit(42));
    });

    test('a numeric string is also a net id', () {
      // Yosys emits ints, but hand-written and round-tripped JSON has been
      // seen carrying them as strings.
      expect(BitRef.fromJson('42'), const NetBit(42));
    });

    test('the four constant literals map to constants, not net ids', () {
      // The trap this pins: '0' and '1' are CONSTANT DRIVERS, not nets 0 and 1.
      // Reading them as net ids would wire a constant to whatever net happens
      // to carry that id.
      expect(BitRef.fromJson('0'), const ConstantBit(ConstantBitValue.zero));
      expect(BitRef.fromJson('1'), const ConstantBit(ConstantBitValue.one));
      expect(BitRef.fromJson('x'), const ConstantBit(ConstantBitValue.x));
      expect(BitRef.fromJson('z'), const ConstantBit(ConstantBitValue.z));
    });

    test('constant literals are case-insensitive for x and z', () {
      expect(BitRef.fromJson('X'), const ConstantBit(ConstantBitValue.x));
      expect(BitRef.fromJson('Z'), const ConstantBit(ConstantBitValue.z));
    });

    test('anything else throws rather than guessing', () {
      for (final bad in <Object?>[
        null,
        'q',
        '',
        <Object?>[],
        <String, Object?>{},
        1.5,
        true,
      ]) {
        expect(
          () => BitRef.fromJson(bad),
          throwsA(isA<FormatException>()),
          reason: 'bit reference: $bad',
        );
      }
    });

    test('round-trips through toJson', () {
      expect(const NetBit(7).toJson(), 7);
      expect(BitRef.fromJson(const NetBit(7).toJson()), const NetBit(7));
      for (final v in ConstantBitValue.values) {
        final bit = ConstantBit(v);
        expect(
          BitRef.fromJson(bit.toJson()),
          bit,
          reason: 'constant $v must survive a round trip',
        );
      }
    });

    test('value equality holds across separately-constructed instances', () {
      expect(const NetBit(3) == const NetBit(3), isTrue);
      expect(const NetBit(3) == const NetBit(4), isFalse);
      expect(
        const ConstantBit(ConstantBitValue.x) ==
            const ConstantBit(ConstantBitValue.x),
        isTrue,
      );
      expect(
        const ConstantBit(ConstantBitValue.x) ==
            const ConstantBit(ConstantBitValue.z),
        isFalse,
      );
      // A net id and a constant must never compare equal.
      expect(
        const NetBit(0) == const ConstantBit(ConstantBitValue.zero),
        isFalse,
      );
    });

    test('hashCode agrees with ==', () {
      expect(const NetBit(9).hashCode, const NetBit(9).hashCode);
      expect(
        const ConstantBit(ConstantBitValue.one).hashCode,
        const ConstantBit(ConstantBitValue.one).hashCode,
      );
    });
  });

  group('PortDirection.fromJson', () {
    test('parses the three Yosys directions', () {
      expect(PortDirection.fromJson('input'), PortDirection.input);
      expect(PortDirection.fromJson('output'), PortDirection.output);
      expect(PortDirection.fromJson('inout'), PortDirection.inout);
    });

    test('is case-insensitive', () {
      expect(PortDirection.fromJson('INPUT'), PortDirection.input);
      expect(PortDirection.fromJson('Output'), PortDirection.output);
    });

    test('an unrecognised direction degrades to inout', () {
      // Documented behaviour, and the safe default: inout makes no claim
      // about direction, so an unknown string cannot invent a driver
      // relationship the design does not have.
      expect(PortDirection.fromJson('sideways'), PortDirection.inout);
      expect(PortDirection.fromJson(''), PortDirection.inout);
    });

    test('round-trips through toJsonString', () {
      for (final d in PortDirection.values) {
        expect(PortDirection.fromJson(d.toJsonString()), d);
      }
    });
  });
}
