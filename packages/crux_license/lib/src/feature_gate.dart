// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/beta_period.dart';
import 'package:crux_license/src/license_tier.dart';

/// Pure utility for runtime feature-tier checks shared across the EDACrux
/// suite.
///
/// Callers read the active tier from `licenseTierProvider` and pass it as
/// `current`; the `required` tier is the minimum tier the feature is gated
/// behind (typically `LicenseTier.pro` or `LicenseTier.enterprise`).
///
/// During the public-beta period ([kBetaPeriod] is `true`), every check
/// returns `true` regardless of `current` — the suite-wide beta policy is
/// *badge but do not block*. Tier badges still render to communicate the
/// future pricing model, but activation is never denied.
///
/// Post-beta, the comparison uses `featureEquivalent` on `current` so the
/// Educational tier ([LicenseTier.edu]) satisfies any Pro-tier gate (EDU is
/// feature-equivalent to Pro). Because [LicenseTier] is otherwise ordered
/// (`openCore` < `pro` < `enterprise`), Enterprise licenses satisfy Pro-tier
/// gates and so on.
///
/// `required` should always be one of `{openCore, pro, enterprise}` —
/// gating a feature on `LicenseTier.edu` specifically is meaningless because
/// every feature available to EDU is also available to Pro and Enterprise;
/// use `LicenseTier.pro` as the requirement instead.
class FeatureGate {
  const FeatureGate._();

  /// Returns `true` when [current] satisfies the [required] tier and the
  /// gated feature should activate. During the beta period, returns `true`
  /// unconditionally.
  static bool isAvailable(LicenseTier required, LicenseTier current) {
    if (kBetaPeriod) return true;
    return satisfiesTier(required, current);
  }

  /// The post-beta tier-ordering check, independent of [kBetaPeriod].
  ///
  /// [isAvailable] delegates here once the beta period ends. It is exposed
  /// separately so the production gating order (`edu` feature-equivalent to
  /// `pro`; `openCore` < `pro` < `enterprise`) is unit-testable regardless
  /// of the compile-time [kBetaPeriod] value — otherwise the post-beta
  /// branch would be dead code in every beta build, which is exactly the
  /// coverage gap that let the vacuous `if (kBetaPeriod) return;` tests
  /// ship. It is also the tier half of the provider-aware gate feature code
  /// uses: `ref.watch(betaPeriodProvider) || FeatureGate.satisfiesTier(...)`.
  static bool satisfiesTier(LicenseTier required, LicenseTier current) {
    return current.featureEquivalent.index >= required.index;
  }
}
