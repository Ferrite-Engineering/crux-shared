// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/metrics/exact_decimal.dart';
import 'package:test/test.dart';

ExactDecimal _d(String text) => ExactDecimal.parse(text);

/// Expected strings below are Python's own `decimal` output for the same
/// operation (`f"{Decimal(x):.4f}"` and friends), the arithmetic upstream's
/// comparison runs on.
void main() {
  group('parse and print', () {
    test('plain, fractional, signed and exponent forms', () {
      expect('${_d('0')}', '0');
      expect('${_d('12.50')}', '12.50');
      expect('${_d('-0.001')}', '-0.001');
      expect('${_d('+7')}', '7');
      expect('${_d('1E+3')}', '1000');
      expect('${_d('1.5e-3')}', '0.0015');
      expect('${_d('5.')}', '5');
    });

    test('refuses what is not a decimal literal', () {
      for (final bad in ['', '.5', 'abc', '1..2', '1e', '0x10', 'NaN']) {
        expect(() => _d(bad), throwsFormatException, reason: bad);
      }
    });

    test('a JSON double means the text that was written', () {
      expect('${ExactDecimal.fromJsonDouble(0.1)}', '0.1');
      expect('${ExactDecimal.fromJsonDouble(-2.5e-7)}', '-0.00000025');
      expect('${ExactDecimal.fromJsonDouble(1e21)}', '1000000000000000000000');
      expect(
        () => ExactDecimal.fromJsonDouble(double.nan),
        throwsArgumentError,
      );
    });

    test('a double expanded exactly, as Decimal(float)', () {
      expect(
        '${ExactDecimal.fromDoubleExact(0.1)}',
        '0.1000000000000000055511151231257827021181583404541015625',
      );
      expect('${ExactDecimal.fromDoubleExact(10)}', '10');
      expect('${ExactDecimal.fromDoubleExact(-0.5)}', '-0.5');
      expect('${ExactDecimal.fromDoubleExact(0)}', '0');
      expect(
        ExactDecimal.fromDoubleExact(5e-324).compareTo(_d('0')),
        greaterThan(0),
      );
      expect(
        () => ExactDecimal.fromDoubleExact(double.infinity),
        throwsArgumentError,
      );
    });
  });

  group('toFixed rounds half to even, as Python', () {
    test('ties go to the even digit', () {
      expect(_d('0.00005').toFixed(4), '0.0000');
      expect(_d('0.00015').toFixed(4), '0.0002');
      expect(_d('2.5').toFixed(0), '2');
      expect(_d('3.5').toFixed(0), '4');
      expect(ExactDecimal.fromDoubleExact(0.03125).toFixed(4), '0.0312');
    });

    test('pads, keeps a negative zero sign, and widens exponents', () {
      expect(_d('2500').toFixed(4), '2500.0000');
      expect(_d('-0.00001').toFixed(4), '-0.0000');
      expect(_d('1E+3').toFixed(4), '1000.0000');
      expect(_d('0.5').toFixed(4), '0.5000');
      expect(_d('0.000049').toFixed(4), '0.0000');
      expect(_d('0.123456').toFixed(4), '0.1235');
    });
  });

  group('arithmetic', () {
    test('decimal subtraction and addition are exact', () {
      expect('${_d('0.3') - _d('0.1')}', '0.2');
      expect(_d('0.0013') - _d('0.0012'), _d('0.0001'));
      expect('${_d('0.1') + _d('0.2')}', '0.3');
      expect((_d('-1.5') - _d('-1.5')).isZero, isTrue);
    });

    test('division rounds to 28 significant digits', () {
      expect(
        _d('1').dividedBy(_d('3')).toFixed(30),
        '0.333333333333333333333333333300',
      );
      expect('${_d('2').dividedBy(_d('3'))}', '0.6666666666666666666666666667');
      expect(
        '${_d('1').dividedBy(_d('7')).timesInt(100)}',
        '14.28571428571428571428571429',
      );
      expect('${_d('-0.05').dividedBy(_d('-0.1'))}', '0.5');
      expect('${_d('0.05').dividedBy(_d('-0.1'))}', '-0.5');
      expect(_d('0').dividedBy(_d('3')).isZero, isTrue);
      expect(() => _d('1').dividedBy(_d('0')), throwsArgumentError);
    });

    test('a tie at the last kept digit rounds to even', () {
      // At two digits 1/16 = 0.0625 is a tie and goes down to the even 2.
      final q = _d('1').dividedBy(_d('16'), precision: 3);
      expect('$q', '0.0625');
      expect('${_d('1').dividedBy(_d('16'), precision: 2)}', '0.062');
      expect('${_d('3').dividedBy(_d('16'), precision: 2)}', '0.19');
    });

    test('precision rounding applies to large sums', () {
      final big = _d('1E+30');
      final sum = big + _d('1');
      expect(sum, big);
    });

    test('comparison, equality and hash ignore trailing zeros', () {
      expect(_d('1.0'), _d('1'));
      expect(_d('1.0').hashCode, _d('1').hashCode);
      expect(_d('0.0').hashCode, _d('0').hashCode);
      expect(_d('-2').compareTo(_d('1.5')), lessThan(0));
      expect(_d('2').isNegative, isFalse);
      expect(_d('-2').isNegative, isTrue);
    });

    test('integer truncation and conversion back to double', () {
      expect(_d('0.05').truncateToInt(), 0);
      expect(_d('-7.9').truncateToInt(), -7);
      expect(_d('1234.5').toDouble(), 1234.5);
      expect(ExactDecimal.fromInt(-3).toDouble(), -3.0);
    });
  });
}
