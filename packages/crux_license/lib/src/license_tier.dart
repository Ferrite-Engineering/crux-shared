// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Product tier enum used throughout the licensing and feature-gating system
/// across the EDACrux suite.
///
/// Pure-Dart domain enum (no Flutter imports). The four tier values represent
/// the documented tiers shared by every product in the suite:
///
/// - [openCore] — free open-source baseline.
/// - [edu] — Educational/non-commercial license. **Feature-equivalent to
///   [pro]** (all Pro features unlock); the EDU distinction is in licensing
///   terms (non-commercial use, annual renewal, educational-status
///   verification), not in feature access. See [LicenseTierFeatures] below
///   for the gating semantics.
/// - [pro] — paid individual tier.
/// - [enterprise] — paid organizational tier; superset of [pro].
///
/// Open-core builds of each product resolve their `licenseTierProvider` to
/// [openCore]. The closed-source Pro overlay for each product overrides
/// the provider with a value derived from the validated license key.
///
/// Which specific features sit behind which tier is a per-product decision;
/// this enum only fixes the shared vocabulary and the ordering that
/// `FeatureGate` compares against.
enum LicenseTier {
  /// Free, open-source tier. The complete core product with all built-in
  /// open-core features.
  openCore,

  /// Educational/non-commercial license. Feature-equivalent to [pro] (all
  /// Pro features unlock); requires annual renewal with `.edu` email
  /// verification of continued enrollment. Grace period of 60 days on
  /// expiration before the app falls back to Open Core.
  ///
  /// EDU is *not* a higher tier than [pro] in feature terms — they unlock
  /// the same Pro feature set. The distinction is licensing terms only
  /// (non-commercial use, renewal cadence, audience).
  edu,

  /// Paid individual tier.
  pro,

  /// Paid organizational tier. Superset of [pro]. Adds SSO, seat-based
  /// licensing, audit logging, managed update channels, and product-specific
  /// Enterprise features (e.g. WaveCrux Collaborative Viewing).
  enterprise,
}

/// Feature-gating semantics for [LicenseTier] values.
extension LicenseTierFeatures on LicenseTier {
  /// The Pro/Enterprise feature set this tier unlocks.
  ///
  /// [LicenseTier.edu] returns [LicenseTier.pro] because EDU users have
  /// full Pro feature access; the EDU distinction is in licensing terms,
  /// not feature access. Other tiers map to themselves. Used by
  /// `FeatureGate.isAvailable` so EDU satisfies any Pro-tier feature gate
  /// (and equivalently does not satisfy an Enterprise-tier feature gate).
  ///
  /// No feature should ever be gated on [LicenseTier.edu] specifically —
  /// any feature available to EDU is also available to Pro and Enterprise,
  /// so the gate should be expressed as `LicenseTier.pro` instead.
  LicenseTier get featureEquivalent => switch (this) {
    LicenseTier.edu => LicenseTier.pro,
    _ => this,
  };

  /// Whether this tier represents an Educational/non-commercial license.
  ///
  /// Used by license-status UI (About box, Welcome screen) to render an
  /// "EDU" edition badge alongside the user's tier label. Distinct from
  /// the per-feature tier badge, which labels features by their required
  /// tier — EDU is not a feature-required tier (see [featureEquivalent]).
  bool get isEducational => this == LicenseTier.edu;
}
