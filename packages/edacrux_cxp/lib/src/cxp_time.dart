// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The longest `time` value accepted, in characters (CXP §9.3.3).
const int kCxpTimeMaxLength = 48;

/// The `time` grammar of CXP §9.3.3: up to 24 digits, an optional fraction of
/// up to 24 digits, an optional unit. The same grammar as a `wavecrux://`
/// link's `t`, so a link's value can be forwarded verbatim.
final RegExp _timePattern = RegExp(
  r'^([0-9]{1,24})(?:\.([0-9]{1,24}))?(fs|ps|ns|us|µs|μs|ms|s)?$',
);

/// The units a sender writes, largest first, with their power of ten in
/// seconds. `µs` and `μs` are read as `us` and never written.
const List<(int, String)> _units = <(int, String)>[
  (0, 's'),
  (-3, 'ms'),
  (-6, 'us'),
  (-9, 'ns'),
  (-12, 'ps'),
  (-15, 'fs'),
];

/// A point in simulation time on a signal cross-probe: the optional `time`
/// field of `request_highlight` and `notify_selection` (CXP §9.3.3,
/// specification revision 11).
///
/// Either a time with a unit, kept exact as [mantissa] × 10^[exponent]
/// seconds counted from the start of the simulation, or, when [isTicks] is
/// true, a whole number of ticks ([mantissa]) of the timescale of the trace
/// the receiver has open. On the wire it is a JSON string: `"1500ns"`,
/// `"1.5us"`, `"2s"`, or a bare tick count such as `"42"`.
///
/// The value is never a JSON number and a unit is never guessed: a value
/// outside the grammar is refused, by [CxpTime.parse] with a
/// [FormatException] and by a receiver with `malformed_payload`.
@immutable
final class CxpTime {
  const CxpTime._(this.mantissa, this.exponent, {required this.isTicks});

  /// A time of [mantissa] × 10^[exponent] seconds from the start of the
  /// simulation: `CxpTime.seconds(BigInt.from(1500), -9)` is 1500 ns.
  ///
  /// Throws an [ArgumentError] when [mantissa] is negative or the time cannot
  /// be written in the grammar (more than 24 digits either side of the point
  /// in femtoseconds, or more than [kCxpTimeMaxLength] characters).
  factory CxpTime.seconds(BigInt mantissa, int exponent) {
    if (mantissa.isNegative) {
      throw ArgumentError.value(mantissa, 'mantissa', 'must not be negative');
    }
    var m = mantissa;
    var e = exponent;
    if (m == BigInt.zero) {
      e = 0;
    } else {
      while (m % _ten == BigInt.zero) {
        m ~/= _ten;
        e++;
      }
    }
    final time = CxpTime._(m, e, isTicks: false);
    if (tryParse(time.toJson()) != time) {
      throw ArgumentError.value(
        '${mantissa}e$exponent',
        'time',
        'cannot be written as a CXP time',
      );
    }
    return time;
  }

  /// A time of [picoseconds] from the start of the simulation, the unit of
  /// the `crux.time_ps` metadata key (CXP §9.3.2).
  factory CxpTime.picoseconds(int picoseconds) {
    if (picoseconds < 0) {
      throw ArgumentError.value(
        picoseconds,
        'picoseconds',
        'must not be negative',
      );
    }
    return CxpTime.seconds(BigInt.from(picoseconds), -12);
  }

  /// A whole number of ticks of the timescale of the trace the receiver has
  /// open. Send a time with a unit instead whenever the unit is known: a tick
  /// count means what the sender intends only when both programs read the
  /// same trace.
  ///
  /// Throws an [ArgumentError] when [count] is negative.
  factory CxpTime.ticks(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    return CxpTime._(BigInt.from(count), 0, isTicks: true);
  }

  /// Parses a `time` value, or throws a [FormatException] when [text] is not
  /// one (CXP §9.3.3).
  factory CxpTime.parse(String text) {
    final time = tryParse(text);
    if (time == null) {
      throw FormatException('Not a CXP time: "$text"', text);
    }
    return time;
  }

  /// Parses a `time` value, or returns null when [text] is not one.
  ///
  /// `1500ns`, `1.5us` and `2s` are times; `µs` (U+00B5) and `μs` (U+03BC)
  /// are read as `us`. A value with no unit is a whole number of ticks; a
  /// fraction with no unit is refused, because a fraction of a tick names no
  /// instant. Refused as well: a sign, an exponent, white space, a unit in
  /// another case (`NS`, `Ms`), a leading or trailing point, the empty
  /// string, and anything longer than [kCxpTimeMaxLength] characters.
  static CxpTime? tryParse(String text) {
    if (text.length > kCxpTimeMaxLength) return null;
    final match = _timePattern.firstMatch(text);
    if (match == null) return null;
    final whole = match.group(1)!;
    final fraction = match.group(2) ?? '';
    final unit = match.group(3);
    if (unit == null) {
      if (fraction.isNotEmpty) return null;
      return CxpTime._(BigInt.parse(whole), 0, isTicks: true);
    }
    final unitExponent = switch (unit) {
      'fs' => -15,
      'ps' => -12,
      'ns' => -9,
      'us' || 'µs' || 'μs' => -6,
      'ms' => -3,
      _ => 0,
    };
    var m = BigInt.parse('$whole$fraction');
    var e = unitExponent - fraction.length;
    if (m == BigInt.zero) {
      e = 0;
    } else {
      while (m % _ten == BigInt.zero) {
        m ~/= _ten;
        e++;
      }
    }
    return CxpTime._(m, e, isTicks: false);
  }

  /// Decodes the `time` field of a payload: null when it is absent or JSON
  /// `null`, the time when it is a string in the grammar.
  ///
  /// Throws a [FormatException] for anything else, a JSON number included
  /// (`42` could mean ticks or picoseconds, and a unit is never guessed), so
  /// the receiver answers `malformed_payload` (CXP §9.3.3).
  static CxpTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is! String) {
      throw FormatException(
        'The "time" field must be a string such as "1500ns", not $json.',
      );
    }
    return CxpTime.parse(json);
  }

  /// For a time with a unit: the digits of the value, trailing zeros moved
  /// into [exponent]. For a tick count: the count.
  final BigInt mantissa;

  /// The power of ten [mantissa] is scaled by, in seconds. Zero for a tick
  /// count and for time zero.
  final int exponent;

  /// Whether this is a bare tick count rather than a time with a unit.
  final bool isTicks;

  /// The value as it goes on the wire.
  ///
  /// A tick count is its decimal digits. A time with a unit is a whole number
  /// in the largest unit that keeps it whole (`1.5us` is written `1500ns`,
  /// time zero `0s`), or femtoseconds with a fraction when it is finer than
  /// one. Always ASCII: `us`, never `µs`.
  String toJson() {
    if (isTicks) return mantissa.toString();
    if (mantissa == BigInt.zero) return '0s';
    for (final (unitExponent, unit) in _units) {
      if (exponent >= unitExponent) {
        return '${mantissa * _ten.pow(exponent - unitExponent)}$unit';
      }
    }
    final fractionDigits = -15 - exponent;
    final digits = mantissa.toString().padLeft(fractionDigits + 1, '0');
    final point = digits.length - fractionDigits;
    return '${digits.substring(0, point)}.${digits.substring(point)}fs';
  }

  /// This time as a tick of a trace whose timescale is [factor] ×
  /// 10^[unitExponent] seconds (a `10ns` timescale is factor 10, unit
  /// exponent -9), rounded to the nearest tick with a half rounded up, or
  /// null when [factor] is not positive.
  ///
  /// A tick count is returned as it is. Not clamped to the trace's range: the
  /// receiver does that, so it can say so (CXP §9.3.2).
  BigInt? toTicks({required int unitExponent, required int factor}) {
    if (isTicks) return mantissa;
    if (factor <= 0) return null;
    final shift = exponent - unitExponent;
    var numerator = mantissa;
    var denominator = BigInt.from(factor);
    if (shift >= 0) {
      numerator *= _ten.pow(shift);
    } else {
      denominator *= _ten.pow(-shift);
    }
    // Round half up: (2n + d) / 2d.
    return (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  }

  @override
  bool operator ==(Object other) =>
      other is CxpTime &&
      other.mantissa == mantissa &&
      other.exponent == exponent &&
      other.isTicks == isTicks;

  @override
  int get hashCode => Object.hash(mantissa, exponent, isTicks);

  @override
  String toString() => 'CxpTime(${toJson()})';
}

final BigInt _ten = BigInt.from(10);
