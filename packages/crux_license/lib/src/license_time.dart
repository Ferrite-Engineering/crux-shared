// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The earliest year a licence date may name.
const int kLicenseTimeMinYear = 1970;

/// The latest year a licence date may name: the last four-digit year, which
/// is as far as an ISO 8601 date without an expanded year reaches.
const int kLicenseTimeMaxYear = 9999;

/// How a date field in an issuer's payload reads.
sealed class LicenseTimeField {
  const LicenseTimeField();
}

/// The field is absent or JSON `null`.
final class LicenseTimeAbsent extends LicenseTimeField {
  /// The absent reading.
  const LicenseTimeAbsent();
}

/// The field is present and is not a date this build can read.
final class LicenseTimeUnreadable extends LicenseTimeField {
  /// The unreadable reading.
  const LicenseTimeUnreadable();
}

/// The field is a readable date.
final class LicenseTimeValue extends LicenseTimeField {
  /// A readable date, in UTC.
  const LicenseTimeValue(this.at);

  /// The date, in UTC.
  final DateTime at;
}

final RegExp _leadingYear = RegExp(r'^\s*([+-]?)(\d{4,})-');

/// Reads a date field from an issuer's payload.
///
/// Anything present that is not a string `DateTime.tryParse` accepts, with a
/// year from [kLicenseTimeMinYear] to [kLicenseTimeMaxYear], is
/// [LicenseTimeUnreadable]: a number, an object, an empty string, a date in
/// another format, and a year outside the range. The range check reads the
/// year from the text as well as from the parsed value, because
/// `DateTime.tryParse` does not refuse a year past what `DateTime` holds
/// (±275760); it wraps it, so a far-future date could read as a far-past one
/// and the reverse.
LicenseTimeField readLicenseTime(Object? value) {
  if (value == null) return const LicenseTimeAbsent();
  if (value is! String) return const LicenseTimeUnreadable();
  final match = _leadingYear.firstMatch(value);
  if (match == null) return const LicenseTimeUnreadable();
  final digits = match.group(2)!;
  // More digits than any year in range is out of range, however many.
  if (digits.length > 4) return const LicenseTimeUnreadable();
  final year = int.parse(digits) * (match.group(1) == '-' ? -1 : 1);
  if (year < kLicenseTimeMinYear || year > kLicenseTimeMaxYear) {
    return const LicenseTimeUnreadable();
  }
  final DateTime? parsed;
  try {
    parsed = DateTime.tryParse(value);
  } on Object {
    return const LicenseTimeUnreadable();
  }
  if (parsed == null) return const LicenseTimeUnreadable();
  final utc = parsed.toUtc();
  // A time-zone offset can move the first or last instant of the range
  // across a year boundary; the bound is on the year as written, so allow
  // one year either side of it after conversion, and nothing further.
  if (utc.year < kLicenseTimeMinYear - 1 ||
      utc.year > kLicenseTimeMaxYear + 1) {
    return const LicenseTimeUnreadable();
  }
  return LicenseTimeValue(utc);
}

/// [readLicenseTime] where an unreadable date and an absent one are both
/// unknown, for informational fields (`created`, an issuer's reported
/// expiry, which only ever extends what the signed credential says).
DateTime? readLicenseTimeOrNull(Object? value) => switch (readLicenseTime(
  value,
)) {
  LicenseTimeValue(:final at) => at,
  _ => null,
};
