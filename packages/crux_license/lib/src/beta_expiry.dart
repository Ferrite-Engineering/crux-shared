// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/beta_period.dart';

/// Hard build-expiry mechanism for public-beta builds of the EDACrux suite.
///
/// Unlike [kBetaPeriod] — which controls *feature gating* (badges visible,
/// gates open) and flips once at the beta-to-production transition — this
/// mechanism enforces a *per-release shelf life* on each beta build so old
/// betas stop running and users are pushed onto the current build.
///
/// ## Build-time injection
///
/// The expiry date is injected per release via
/// `--dart-define=BETA_EXPIRY=<yyyymmdd>` (e.g. `BETA_EXPIRY=20260901`).
/// This lets each beta drop carry its own date — Beta 1 expires on date X,
/// Beta 2 on X+Y — with no source edit per release. Absent or `0` means the
/// build never expires, so day-to-day developer builds (and every post-beta
/// production build, where [kBetaPeriod] is `false`) are unaffected.
///
/// The warning window is likewise a build-time constant
/// ([kBetaExpiryWarningDays], default 7), overridable via
/// `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`.
///
/// ## Semantics
///
/// - Expiry only applies while [kBetaPeriod] is `true`. A non-beta
///   (production) build never expires regardless of `BETA_EXPIRY`.
/// - The status is a pure function of the current wall-clock date and the
///   injected expiry date — see [betaExpiryStatusFor] / [daysUntilBetaExpiry].
///   The host app reads it at startup and on app resume, never mid-session,
///   so a session in progress is never interrupted.
/// - Expiry is reckoned in whole calendar days. A build with
///   `BETA_EXPIRY=20260901` is [BetaExpiryStatus.active] (or
///   [BetaExpiryStatus.expiringSoon] inside the warning window) through
///   2026-08-31 and becomes [BetaExpiryStatus.expired] at the start of
///   2026-09-01.
///
/// ## Clock-tampering note
///
/// The device clock alone is not trusted: [trustedBetaExpiryNow] takes the
/// later of the device clock and the most recent authoritative server time the
/// app has observed (delivered by the update-manifest check and persisted by
/// the host), so winding the clock *back* cannot defer expiry below that
/// watermark. A user who has never been online since install, or who moves the
/// clock forward, is still reckoned by the device clock — accepted, because the
/// mechanism exists to retire stale builds rather than to resist a determined
/// attacker.

/// Raw `yyyymmdd` integer injected at build time, or `0` when absent.
const int _betaExpiryRaw = int.fromEnvironment('BETA_EXPIRY');

/// Number of days before [kBetaExpiry] at which the host app starts showing
/// the dismissible "beta expires soon" warning. Defaults to 7, overridable at
/// build time via `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`.
const int kBetaExpiryWarningDays = int.fromEnvironment(
  'BETA_EXPIRY_WARNING_DAYS',
  defaultValue: 7,
);

/// The build-injected hard-expiry date, or `null` when this build never
/// expires.
///
/// `null` when `BETA_EXPIRY` is absent/`0`, when the injected value is not a
/// valid `yyyymmdd` date, or when [kBetaPeriod] is `false` (production builds
/// never expire). Time-of-day is always midnight local — expiry is reckoned in
/// whole calendar days.
final DateTime? kBetaExpiry = kBetaPeriod
    ? parseBetaExpiryDate(_betaExpiryRaw)
    : null;

/// Parses a `yyyymmdd` integer (e.g. `20260901`) into a local midnight
/// [DateTime], or returns `null` when [yyyymmdd] is `0`, negative, or does not
/// describe a real calendar date (e.g. month 13, day 32, or 2026-02-30).
///
/// Exposed (not private) so the build-injection contract can be unit-tested
/// directly without relying on `--dart-define` in the test runner.
DateTime? parseBetaExpiryDate(int yyyymmdd) {
  if (yyyymmdd <= 0) return null;

  final year = yyyymmdd ~/ 10000;
  final month = (yyyymmdd ~/ 100) % 100;
  final day = yyyymmdd % 100;

  if (year < 2000 || year > 9999) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;

  final parsed = DateTime(year, month, day);
  // Reject values DateTime would silently normalize (e.g. 2026-02-30 → Mar 2).
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// Whole calendar days from [now] until the build's hard-expiry date, or
/// `null` when the build never expires.
///
/// Positive while the build is still valid, `0` on the expiry date itself, and
/// negative once past it. Both [now] and the expiry are truncated to date
/// (midnight local) before differencing, so the result is independent of
/// time-of-day. Pass [expiry] explicitly to test boundaries without relying on
/// the build-injected [kBetaExpiry].
int? daysUntilBetaExpiry(DateTime now, {DateTime? expiry}) {
  final target = expiry ?? kBetaExpiry;
  if (target == null) return null;

  final today = DateTime(now.year, now.month, now.day);
  final expiryDate = DateTime(target.year, target.month, target.day);
  return expiryDate.difference(today).inDays;
}

/// Where this build sits relative to its hard-expiry date.
enum BetaExpiryStatus {
  /// The build never expires — `BETA_EXPIRY` was absent/`0`/invalid, or this
  /// is a production build ([kBetaPeriod] is `false`). The host shows nothing.
  notApplicable,

  /// Expiry is set and still more than [kBetaExpiryWarningDays] days away. The
  /// host shows nothing.
  active,

  /// Expiry is within the warning window (`1..kBetaExpiryWarningDays` days
  /// away). The host shows a dismissible "expires soon" banner.
  expiringSoon,

  /// The expiry date has arrived or passed. The host shows a blocking,
  /// non-dismissable "download the latest build" modal.
  expired,
}

/// Computes the [BetaExpiryStatus] for the wall-clock instant [now].
///
/// Pure: given the same [now], [expiry], and [warningDays] it always returns
/// the same status. Defaults read the build-injected [kBetaExpiry] and
/// [kBetaExpiryWarningDays]; pass them explicitly to exercise the
/// active/expiringSoon/expired boundaries in tests.
BetaExpiryStatus betaExpiryStatusFor(
  DateTime now, {
  DateTime? expiry,
  int? warningDays,
}) {
  final days = daysUntilBetaExpiry(now, expiry: expiry);
  if (days == null) return BetaExpiryStatus.notApplicable;

  if (days <= 0) return BetaExpiryStatus.expired;
  if (days <= (warningDays ?? kBetaExpiryWarningDays)) {
    return BetaExpiryStatus.expiringSoon;
  }
  return BetaExpiryStatus.active;
}

/// Resolves the trusted "now" used to reckon beta expiry, hardening the
/// device-clock check against rollback.
///
/// Returns the **later** of [deviceNow] and [observedServerTime] — the most
/// recently observed authoritative server clock (delivered by the update
/// manifest's `server_time`). Because expiry is reckoned forward in time,
/// taking the maximum means setting the device clock *back* can never defer
/// expiry below the last server time the app has seen. When no server time has
/// been observed yet ([observedServerTime] is `null`), this returns [deviceNow]
/// unchanged, so the pre-hardening behavior is preserved on a fresh / offline
/// install that has never reached the manifest endpoint.
///
/// Pure: the result depends only on its two arguments. Feed the result into
/// [betaExpiryStatusFor] / [daysUntilBetaExpiry].
DateTime trustedBetaExpiryNow(
  DateTime deviceNow, {
  DateTime? observedServerTime,
}) {
  if (observedServerTime == null) return deviceNow;
  return observedServerTime.isAfter(deviceNow) ? observedServerTime : deviceNow;
}
