// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The working precision of Python's default decimal context, which
/// LibreLane's metric comparison runs under: 28 significant digits, rounding
/// half to even.
const int pythonDecimalPrecision = 28;

final BigInt _ten = BigInt.from(10);
final BigInt _two = BigInt.two;
final BigInt _five = BigInt.from(5);

BigInt _pow10(int n) => _ten.pow(n);

int _digits(BigInt v) => v == BigInt.zero ? 1 : v.abs().toString().length;

/// A decimal number held exactly: `unscaled * 10^-scale`.
///
/// LibreLane loads metrics with `parse_float=Decimal` and compares them in
/// decimal arithmetic. Doing the same here, rather than in binary floating
/// point, is what makes a delta of `0.3 - 0.1` print as `0.2000` the way
/// upstream prints it.
@immutable
final class ExactDecimal implements Comparable<ExactDecimal> {
  const ExactDecimal._(this.unscaled, this.scale);

  /// [value] exactly.
  factory ExactDecimal.fromInt(int value) =>
      ExactDecimal._(BigInt.from(value), 0);

  /// The decimal a JSON writer meant by [value].
  ///
  /// A double decoded from JSON text is the nearest binary value to that
  /// text; its shortest round-trip form is the text again for every number
  /// written by a shortest-round-trip writer (Python's `json`, which wrote
  /// every LibreLane metrics file). Throws [ArgumentError] for a non-finite
  /// value.
  factory ExactDecimal.fromJsonDouble(double value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
    return ExactDecimal.parse(value.toString());
  }

  /// The binary value of [value], expanded exactly: what Python's
  /// `Decimal(float)` produces. Throws [ArgumentError] for a non-finite
  /// value.
  factory ExactDecimal.fromDoubleExact(double value) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
    final bits = ByteData(8)..setFloat64(0, value);
    final hi = bits.getUint32(0);
    final lo = bits.getUint32(4);
    final negative = (hi >> 31) == 1;
    final exponentBits = (hi >> 20) & 0x7FF;
    var mantissa = (BigInt.from(hi & 0xFFFFF) << 32) | BigInt.from(lo);
    int exponent;
    if (exponentBits == 0) {
      exponent = -1074;
    } else {
      mantissa |= BigInt.one << 52;
      exponent = exponentBits - 1075;
    }
    if (negative) mantissa = -mantissa;
    if (exponent >= 0) return ExactDecimal._(mantissa << exponent, 0);
    return ExactDecimal._trimmed(
      mantissa * _five.pow(-exponent),
      -exponent,
      0,
    );
  }

  /// [unscaled] at [scale] with trailing zero digits removed while the scale
  /// stays above [floor]: the shortest form Python gives an exact result.
  factory ExactDecimal._trimmed(BigInt unscaled, int scale, int floor) {
    var u = unscaled;
    var s = scale;
    while (s > floor && s > 0 && u.remainder(_ten) == BigInt.zero) {
      u = u ~/ _ten;
      s--;
    }
    return ExactDecimal._(u, s);
  }

  /// Parses a decimal literal: an optional sign, digits with an optional
  /// fraction, and an optional exponent. Throws [FormatException] otherwise.
  factory ExactDecimal.parse(String text) {
    final match = _literal.firstMatch(text);
    if (match == null) throw FormatException('not a decimal', text);
    final negative = match.group(1) == '-';
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    final exponent = match.group(4) == null ? 0 : int.parse(match.group(4)!);
    var unscaled = BigInt.parse('$whole$fraction');
    if (negative) unscaled = -unscaled;
    final scale = fraction.length - exponent;
    if (scale < 0) return ExactDecimal._(unscaled * _pow10(-scale), 0);
    return ExactDecimal._(unscaled, scale);
  }

  /// [value] at [scale] rounded half to even to [precision] digits.
  factory ExactDecimal._rounded(BigInt value, int scale, int precision) {
    final result = ExactDecimal._roundedMagnitude(
      value.abs(),
      scale,
      precision,
      sticky: false,
    );
    return value.isNegative
        ? ExactDecimal._(-result.unscaled, result.scale)
        : result;
  }

  /// [magnitude] at [scale] rounded half to even to [precision] digits;
  /// [sticky] says digits below [magnitude] were already discarded and were
  /// not all zero.
  factory ExactDecimal._roundedMagnitude(
    BigInt magnitude,
    int scale,
    int precision, {
    required bool sticky,
  }) {
    final excess = _digits(magnitude) - precision;
    // The one caller passing sticky supplies more than precision digits, so
    // an inexact value always reaches the rounding below.
    if (excess <= 0) return ExactDecimal._normalised(magnitude, scale);
    final divisor = _pow10(excess);
    var head = magnitude ~/ divisor;
    final rest = magnitude.remainder(divisor);
    final twice = rest * _two;
    final roundUp =
        twice > divisor || (twice == divisor && (sticky || head.isOdd));
    if (roundUp) head += BigInt.one;
    return ExactDecimal._normalised(head, scale - excess);
  }

  factory ExactDecimal._normalised(BigInt unscaled, int scale) {
    if (scale >= 0) return ExactDecimal._(unscaled, scale);
    return ExactDecimal._(unscaled * _pow10(-scale), 0);
  }

  static final RegExp _literal = RegExp(
    r'^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  );

  /// The digits, without the decimal point.
  final BigInt unscaled;

  /// Digits after the decimal point; never negative.
  final int scale;

  /// Whether this is zero.
  bool get isZero => unscaled == BigInt.zero;

  /// Whether this is below zero.
  bool get isNegative => unscaled.isNegative;

  /// This and [other] brought to a common scale.
  (BigInt, BigInt, int) _aligned(ExactDecimal other) {
    if (scale == other.scale) return (unscaled, other.unscaled, scale);
    if (scale > other.scale) {
      return (unscaled, other.unscaled * _pow10(scale - other.scale), scale);
    }
    return (
      unscaled * _pow10(other.scale - scale),
      other.unscaled,
      other.scale,
    );
  }

  /// This minus [other], rounded to Python's working precision.
  ExactDecimal operator -(ExactDecimal other) {
    final (a, b, s) = _aligned(other);
    return ExactDecimal._rounded(a - b, s, pythonDecimalPrecision);
  }

  /// This plus [other], rounded to Python's working precision.
  ExactDecimal operator +(ExactDecimal other) {
    final (a, b, s) = _aligned(other);
    return ExactDecimal._rounded(a + b, s, pythonDecimalPrecision);
  }

  /// This times [factor], rounded to Python's working precision.
  ExactDecimal timesInt(int factor) => ExactDecimal._rounded(
    unscaled * BigInt.from(factor),
    scale,
    pythonDecimalPrecision,
  );

  /// This divided by [divisor], rounded half to even to [precision]
  /// significant digits, as Python's decimal division does. Throws
  /// [ArgumentError] when [divisor] is zero.
  ExactDecimal dividedBy(
    ExactDecimal divisor, {
    int precision = pythonDecimalPrecision,
  }) {
    if (divisor.isZero) throw ArgumentError.value(divisor, 'divisor');
    if (isZero) return ExactDecimal._(BigInt.zero, 0);
    final negative = unscaled.isNegative != divisor.unscaled.isNegative;
    // value = (|u1| * 10^s2) / (|u2| * 10^s1)
    final numerator = unscaled.abs() * _pow10(divisor.scale);
    final denominator = divisor.unscaled.abs() * _pow10(scale);
    // Enough extra digits that the integer quotient carries more than
    // [precision] significant digits.
    final shift = (precision + 2 - (_digits(numerator) - _digits(denominator)))
        .clamp(0, 1 << 20);
    final scaled = numerator * _pow10(shift);
    final quotient = scaled ~/ denominator;
    final sticky = scaled.remainder(denominator) != BigInt.zero;
    var result = ExactDecimal._roundedMagnitude(
      quotient,
      shift,
      precision,
      sticky: sticky,
    );
    if (!sticky) {
      // An exact quotient takes Python's ideal scale: the dividend's minus
      // the divisor's, never more digits than the value needs.
      result = ExactDecimal._trimmed(
        result.unscaled,
        result.scale,
        scale - divisor.scale,
      );
    }
    return negative ? ExactDecimal._(-result.unscaled, result.scale) : result;
  }

  /// This rendered with exactly [places] digits after the point, rounded
  /// half to even: Python's `f"{value:.{places}f}"` for a `Decimal`. A
  /// negative value that rounds to zero keeps its sign, as Python's does.
  String toFixed(int places) {
    BigInt magnitude;
    if (scale <= places) {
      magnitude = unscaled.abs() * _pow10(places - scale);
    } else {
      final divisor = _pow10(scale - places);
      magnitude = unscaled.abs() ~/ divisor;
      final rest = unscaled.abs().remainder(divisor);
      final twice = rest * _two;
      if (twice > divisor || (twice == divisor && magnitude.isOdd)) {
        magnitude += BigInt.one;
      }
    }
    var digits = magnitude.toString();
    if (places > 0) {
      if (digits.length <= places) digits = digits.padLeft(places + 1, '0');
      final point = digits.length - places;
      digits = '${digits.substring(0, point)}.${digits.substring(point)}';
    }
    return unscaled.isNegative ? '-$digits' : digits;
  }

  /// The nearest double.
  double toDouble() => double.parse(toString());

  /// The integer part, truncated toward zero: Python's `int(Decimal)`.
  int truncateToInt() => (unscaled ~/ _pow10(scale)).toInt();

  @override
  int compareTo(ExactDecimal other) {
    final (a, b, _) = _aligned(other);
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) =>
      other is ExactDecimal && compareTo(other) == 0;

  @override
  int get hashCode {
    var u = unscaled;
    var s = scale;
    while (s > 0 && u.remainder(_ten) == BigInt.zero) {
      u = u ~/ _ten;
      s--;
    }
    return Object.hash(u, s);
  }

  /// Plain decimal notation, every digit kept.
  @override
  String toString() {
    if (scale == 0) return unscaled.toString();
    final digits = unscaled.abs().toString().padLeft(scale + 1, '0');
    final point = digits.length - scale;
    final text = '${digits.substring(0, point)}.${digits.substring(point)}';
    return unscaled.isNegative ? '-$text' : text;
  }
}
