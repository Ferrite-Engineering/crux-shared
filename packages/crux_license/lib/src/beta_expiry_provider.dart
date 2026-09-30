// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/beta_expiry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The most recently observed authoritative server time, or `null` when none
/// has been seen yet.
///
/// Defaults to `null` (no server time observed → the beta-expiry clock uses
/// the device clock unchanged, exactly as before). The host overrides this
/// with the `server_time` its update-manifest check returns — persisted, so a
/// later offline launch still benefits — which is what makes the expiry clock
/// resistant to rollback: [betaExpiryStatusProvider] and
/// [betaExpiryDaysRemainingProvider] reckon expiry against
/// `trustedBetaExpiryNow(DateTime.now(), observedServerTime: …)`, so setting
/// the device clock *back* can no longer defer expiry below the last server
/// time the app has seen.
///
/// ```dart
/// // In the host's root ProviderScope:
/// observedServerTimeProvider.overrideWith(
///   (ref) => ref.watch(myPersistedServerTimeProvider),
/// ),
/// ```
final observedServerTimeProvider = Provider<DateTime?>(
  (_) => null,
  name: 'observedServerTimeProvider',
);

/// Riverpod-overridable view of the build's hard-expiry status for tests and
/// the host's startup/resume check.
///
/// The build-time values [kBetaExpiry] / [kBetaExpiryWarningDays] remain the
/// production source of truth, and [betaExpiryStatusFor] is the pure function
/// that derives the status. This provider exists so the host app can read the
/// status reactively (it re-checks at launch and on app resume by invalidating
/// the provider, never mid-session) and so tests can drive each
/// [BetaExpiryStatus] without setting `--dart-define` on the test runner:
///
/// ```dart
/// final container = ProviderContainer(
///   overrides: [
///     betaExpiryStatusProvider.overrideWithValue(BetaExpiryStatus.expired),
///   ],
/// );
/// ```
///
/// The default reads the current wall-clock instant (hardened against rollback
/// via [observedServerTimeProvider]), so in an unconfigured build (no
/// `BETA_EXPIRY`) it resolves to [BetaExpiryStatus.notApplicable]. Because the
/// value is captured when the provider is first read, the host invalidates it
/// (`ref.invalidate(betaExpiryStatusProvider)`) on app resume to re-evaluate
/// against the latest clock reading.
///
/// Distinct from `kBetaPeriod`, which governs feature *gating* and flips once
/// at the beta-to-production transition. This governs one build's shelf life
/// and moves with every beta drop.
final betaExpiryStatusProvider = Provider<BetaExpiryStatus>(
  (ref) => betaExpiryStatusFor(
    trustedBetaExpiryNow(
      DateTime.now(),
      observedServerTime: ref.watch(observedServerTimeProvider),
    ),
  ),
  name: 'betaExpiryStatusProvider',
);

/// Riverpod-overridable view of whole calendar days remaining until the
/// build's hard-expiry date, or `null` when the build never expires.
///
/// Drives the day count shown in the host's "expires soon" banner. Mirrors
/// [betaExpiryStatusProvider]: the default reads the current wall-clock instant
/// (hardened via [observedServerTimeProvider]) and the host invalidates it on
/// app resume. Tests override it with a fixed value to render a deterministic
/// banner.
final betaExpiryDaysRemainingProvider = Provider<int?>(
  (ref) => daysUntilBetaExpiry(
    trustedBetaExpiryNow(
      DateTime.now(),
      observedServerTime: ref.watch(observedServerTimeProvider),
    ),
  ),
  name: 'betaExpiryDaysRemainingProvider',
);
