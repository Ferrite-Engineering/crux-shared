// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:meta/meta.dart';

/// How long each tier keeps working after the issuer stops confirming it.
///
/// The load-bearing feature for almost every licensing failure mode: a renewal
/// failure, a customer on a plane, and a
/// Keygen outage are the same event from the app's point of view, and grace is
/// what makes all three survivable without a support ticket.
///
/// **Grace is decided in the app, not by the billing bridge.** The bridge
/// deliberately does not suspend a licence on `past_due`, because Stripe's
/// dunning is still running at that point — so the app is the only place that
/// knows how long to keep going.
@immutable
class LicenseGracePolicy {
  /// Create a policy with an explicit window per tier.
  const LicenseGracePolicy({
    this.pro = const Duration(days: 30),
    this.edu = const Duration(days: 60),
    this.enterprise = const Duration(days: 90),
  });

  /// The suite's policy: 30 days Pro, 60 EDU, 90 Enterprise.
  ///
  /// Enterprise is longest because of the airgapped and
  /// semiconductor-customer profile the tier is sold into; EDU sits between
  /// because its renewal is an annual email round trip a student can easily
  /// miss over a summer.
  static const LicenseGracePolicy standard = LicenseGracePolicy();

  /// Grace granted to a Pro licence.
  final Duration pro;

  /// Grace granted to an Educational licence.
  final Duration edu;

  /// Grace granted to an Enterprise licence.
  final Duration enterprise;

  /// The window for [tier]. Open Core has no licence to be in grace over.
  Duration forTier(LicenseTier tier) => switch (tier) {
    LicenseTier.pro => pro,
    LicenseTier.edu => edu,
    LicenseTier.enterprise => enterprise,
    LicenseTier.openCore => Duration.zero,
  };

  /// When grace runs out for a licence of [tier] that expired at [expiry].
  DateTime endsAfter(DateTime expiry, LicenseTier tier) =>
      expiry.add(forTier(tier));

  /// Whether a licence of [tier] that expired at [expiry] is still inside its
  /// grace window at [now].
  bool covers({
    required DateTime expiry,
    required LicenseTier tier,
    required DateTime now,
  }) => now.isBefore(endsAfter(expiry, tier));
}
