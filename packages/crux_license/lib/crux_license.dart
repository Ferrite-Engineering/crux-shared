// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite license tier, beta-period gating, Riverpod tier provider,
/// and tier-badge widgets for the EDACrux suite.
///
/// One package, shared by WaveCrux, NetCrux, LintCrux and SimCrux.
/// Every product wires the same primitives into its open-core build and its
/// Pro overlay so a single signed license key issued at Pro or Enterprise tier
/// unlocks the corresponding feature set across the entire suite.
///
/// Surface today:
///
/// - `LicenseTier` enum + `LicenseTierFeatures` extension — the four-value
///   tier vocabulary every product shares (`openCore` / `edu` / `pro` /
///   `enterprise`) with the EDU-as-Pro-feature-equivalent mapping.
/// - `kBetaPeriod` + `betaPeriodProvider` — the build-time public-beta
///   flag and its Riverpod-overridable view for tests.
/// - `kAiExperimental` + `aiExperimentalBuildFlagProvider` +
///   `aiExperimentalUserToggleProvider` + `aiExperimentalEnabledProvider` —
///   the Experimental AI Waveform Assistant gate. The build flag
///   (`--dart-define=AI_EXPERIMENTAL=false` to omit; default `true`)
///   governs whether AI exists in the build; combined with a persisted,
///   off-by-default user opt-in, `aiExperimentalEnabledProvider` is the
///   single gate every AI surface checks. Both must be on.
/// - `kBetaExpiry` + `kBetaExpiryWarningDays` + `BetaExpiryStatus` +
///   `betaExpiryStatusFor` / `daysUntilBetaExpiry` — the per-release hard
///   build-expiry mechanism. The expiry date is injected per beta drop via
///   `--dart-define=BETA_EXPIRY=<yyyymmdd>` (absent/`0` ⇒ never expires);
///   only applies while `kBetaPeriod` is on. The host reads the status at
///   startup and on resume to show an "expires soon" banner or a blocking
///   "download the latest build" modal. Distinct from `kBetaPeriod`, which
///   governs feature *gating*, not build shelf life.
/// - `betaExpiryStatusProvider` + `betaExpiryDaysRemainingProvider` — the
///   Riverpod-overridable views of the expiry status and days remaining for
///   the host's startup/resume check and for tests.
/// - `FeatureGate` — pure utility that short-circuits to `true` while
///   `kBetaPeriod` is on and otherwise compares the active tier (via
///   `featureEquivalent`) against the gate's required tier.
/// - `licenseTierProvider` — Riverpod provider exposing the active tier.
///   Defaults to `LicenseTier.openCore`; each product's Pro overlay
///   overrides it from the `CruxLicenseController` it constructs.
/// - `LicenseValidator` + `CruxLicenseValidator` + `NoopLicenseValidator` —
///   the real Ed25519 validator, and the seam it plugs into. It verifies
///   against a **set** of trusted issuers (Keygen is issuer one, the second
///   slot is reserved and empty) and resolves a credential
///   onto a `LicenseGrant` — a tier plus the products it covers. It lives
///   here, in the open half, because the private signing key is Keygen's and
///   never ships; what a build carries is an account id and a public verify
///   key, neither of which is a secret.
/// - `CruxProduct`, `LicenseClaims`, `LicenseGrant`, `LicenseValidation` —
///   the vocabulary of that answer. Validation is total: every malformed,
///   tampered, expired or wrong-product credential is an outcome to render,
///   never an exception to catch.
/// - `KeygenLicenseIssuer` + `kKeygenPolicies` — issuer one, and the policy
///   table that resolves a bare licence key offline. A Keygen key carries a
///   policy id and NO entitlements, so the table generated from the SKU
///   catalog is what turns it back
///   into a tier and a product set with no network. A Keygen *licence file*
///   embeds entitlements and resolves without the table; a Keygen *machine
///   file* does the same and is bound to the fingerprint of the install it
///   was checked out for, which is what makes it the airgap artefact.
/// - `SharedInstallFingerprint` + `InstallFingerprintFile` +
///   `MachineReleaseMarker` — the machine's one fingerprint, shared by every
///   product on it through a plain file so a suite licence's seats count
///   machines rather than installs, and the note one product leaves for the
///   others when it releases the machine's seat.
/// - `LicenseBadgeStrings` + `LicenseBadgeStringsEn` — the caller-supplied
///   localization surface for the chip widgets.
/// - `FeatureTierBadge` / `EditionBadge` widgets — the PRO/ENT feature-tier
///   chips and the EDU license-edition chip every product renders on its
///   feature surfaces and license-status surfaces.
/// - `CruxUpgradeDialog` + `CruxUpgradeDialogStrings` — the suite-standard
///   tier-denied dialog shown when a gated activation is refused post-beta,
///   naming the feature and the tier that unlocks it.
/// - `CruxGatedSettingsBody` + `cruxGatedSettingsCategory` — the tier gate
///   for a Pro overlay's `pro.*` Settings categories: the real body when
///   the tier unlocks it, otherwise a locked panel that names the feature,
///   the tier, and the way to buy it. The License category never goes
///   through it.
library;

export 'src/ai_experimental.dart';
export 'src/ai_experimental_provider.dart';
export 'src/audit_recorder.dart';
export 'src/beta_expiry.dart';
export 'src/beta_expiry_provider.dart';
export 'src/beta_period.dart';
export 'src/beta_period_provider.dart';
export 'src/crux_product.dart';
export 'src/feature_gate.dart';
export 'src/install_fingerprint.dart';
export 'src/keygen_client.dart';
export 'src/keygen_issuer.dart';
export 'src/keygen_policy.dart';
export 'src/keygen_policy_table.dart';
export 'src/license_actions.dart';
export 'src/license_claims.dart';
export 'src/license_controller.dart';
export 'src/license_credential.dart';
export 'src/license_edition_line.dart';
export 'src/license_grace.dart';
export 'src/license_grant.dart';
export 'src/license_issuer.dart';
export 'src/license_panel_providers.dart';
export 'src/license_status.dart';
export 'src/license_tier.dart';
export 'src/license_tier_dev.dart';
export 'src/license_tier_provider.dart';
export 'src/license_validation.dart';
export 'src/license_validator.dart';
export 'src/machine_release_marker.dart';
export 'src/policy_binding.dart';
export 'src/widgets/beta_expiry_banner.dart';
export 'src/widgets/beta_expiry_banner_strings.dart';
export 'src/widgets/edition_badge.dart';
export 'src/widgets/feature_tier_badge.dart';
export 'src/widgets/gated_settings_body.dart';
export 'src/widgets/gated_settings_category.dart';
export 'src/widgets/license_badge_strings.dart';
export 'src/widgets/license_panel.dart';
export 'src/widgets/license_panel_strings.dart';
export 'src/widgets/license_settings_category.dart';
export 'src/widgets/upgrade_dialog.dart';
export 'src/widgets/upgrade_dialog_strings.dart';
