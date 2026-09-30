// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Build-time flag for the public-beta period, during which every feature is
/// unlocked regardless of product tier.
///
/// **The public beta has ended, and the flag defaults to `false`.** A build
/// that passes no define gates features by tier: `FeatureGate` checks
/// `licenseTierProvider` before a gated feature activates, beta expiry
/// (`kBetaExpiry`) is off, and telemetry follows the user's consent.
///
/// While the flag is `true` the suite-wide beta policy is *badge but do not
/// block*: tier badges (the PRO/ENT chips) stay visible to communicate the
/// pricing model, while `FeatureGate` short-circuits to allow any feature
/// regardless of tier.
///
/// A single source of truth in code, shared across every Crux product. Ending
/// the beta was a one-line change to the default here, not a sweep across
/// every gated feature or every product repo. Each product's release pipeline
/// reads this default from source, so keep the declaration's shape:
/// `bool.fromEnvironment('BETA_PERIOD', defaultValue: <bool>)`.
///
/// Overridable at build time. To restore beta behaviour in a local build:
///
/// ```sh
/// flutter run --dart-define=BETA_PERIOD=true
/// ```
///
/// To walk the gated app as a particular tier, set `LICENSE_TIER`
/// (`kLicenseTierOverrideName`) instead:
///
/// ```sh
/// flutter run --dart-define=LICENSE_TIER=pro
/// ```
///
/// A tier set together with `BETA_PERIOD=true` changes nothing visible,
/// because `FeatureGate` short-circuits on this flag before it ever reads the
/// tier. A release build passes no `BETA_PERIOD` define; the default alone
/// decides it.
const bool kBetaPeriod = bool.fromEnvironment(
  'BETA_PERIOD',
  // Spelled out although it matches the language default: the release gate
  // reads the default from this line, and a reader should not have to know
  // that an omitted one means false.
  // ignore: avoid_redundant_argument_values
  defaultValue: false,
);
