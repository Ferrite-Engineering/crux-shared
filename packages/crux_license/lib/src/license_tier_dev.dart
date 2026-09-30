// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';

/// Build-time name of the tier to force, for walking the gated app as a
/// particular tier without a licence.
///
/// Set with `--dart-define=LICENSE_TIER=pro`. Accepted values are the
/// [LicenseTier] enum names, case-insensitively: `openCore`, `edu`, `pro`,
/// `enterprise`. Empty — the default — means no override.
///
/// Do not combine it with `--dart-define=BETA_PERIOD=true`: `FeatureGate`
/// short-circuits on `kBetaPeriod` before it reads the tier at all, so
/// forcing a tier while the beta flag is `true` changes nothing visible.
///
/// This is a *compile-time* constant, which is what makes it safe to leave in
/// shipped code: a release built without the define contains no override, and
/// no runtime input can introduce one. It is a build affordance, not a
/// backdoor.
const String kLicenseTierOverrideName = String.fromEnvironment('LICENSE_TIER');

/// [kLicenseTierOverrideName] resolved to a tier, or `null` when unset.
///
/// Throws [ArgumentError] on a value that is not a tier name. A silent
/// fallback would be worse than a crash here: a typo like `LICENSE_TIER=proo`
/// would leave you walking the app as Open Core while believing you were
/// testing Pro, and every conclusion drawn from that session would be wrong.
LicenseTier? get licenseTierOverride {
  if (kLicenseTierOverrideName.isEmpty) return null;
  final wanted = kLicenseTierOverrideName.toLowerCase();
  for (final tier in LicenseTier.values) {
    if (tier.name.toLowerCase() == wanted) return tier;
  }
  throw ArgumentError.value(
    kLicenseTierOverrideName,
    'LICENSE_TIER',
    'not a tier name; expected one of '
        '${LicenseTier.values.map((t) => t.name).join(', ')}',
  );
}

/// Applies [licenseTierOverride] on top of a tier resolved from a real
/// licence, returning [resolved] when no override is set.
///
/// Every site that decides the value of `licenseTierProvider` should route
/// through this rather than reading the dart-define itself. The Pro
/// overlays override the provider wholesale, so a build-time override applied
/// only inside the provider's own default would be discarded in exactly the
/// builds where it is most useful.
LicenseTier applyLicenseTierOverride(LicenseTier resolved) =>
    licenseTierOverride ?? resolved;
