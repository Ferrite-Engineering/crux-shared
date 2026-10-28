// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `yyyy-MM-dd`, in local time. Deliberately not localized through `intl`:
/// the package is dependency-light on purpose, and an ISO date is unambiguous
/// in every locale the suite ships, which a numeric locale-specific format is
/// not.
///
/// One formatter for the licence panel and the expiry banner, so the two
/// always show a licence's date the same way.
String formatLicenseDate(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

/// [formatLicenseDate] plus `HH:mm`, in local time.
String formatLicenseDateTime(DateTime at) {
  final local = at.toLocal();
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  return '${formatLicenseDate(local)} $time';
}

String _two(int value) => value.toString().padLeft(2, '0');
