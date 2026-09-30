// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The Flutter-free half of `crux_license`.
///
/// ### Why this is a separate entry point
///
/// The main `crux_license.dart` barrel exports `FeatureTierBadge`,
/// `EditionBadge` and `CruxUpgradeDialog`, which import
/// `package:flutter/material.dart`, and the Riverpod provider seams, which
/// import `package:flutter_riverpod/flutter_riverpod.dart`. *Any* import of
/// that barrel therefore drags `dart:ui` into the compilation unit.
///
/// For a Flutter app that is free. For a headless entry point compiled with
/// `dart build cli` / `dart compile exe` it is fatal: `dart:ui` has no
/// implementation outside the Flutter engine, and the compile dies inside the
/// FFI transformer with `type 'InvalidType' is not a subtype of type
/// 'FunctionType'` — no source location, no named library. LintCrux's Pro CLI
/// hit exactly that and had to reach into `package:crux_license/src/` behind
/// an `implementation_imports` ignore. Every product in the suite ships (or
/// will ship) a headless binary that gates Pro subcommands, so the seam
/// belongs here rather than in each product's workaround.
///
/// This library is the tier vocabulary and the gating arithmetic with no
/// Flutter, no Riverpod and no `dart:ui` anywhere in its transitive import
/// closure — a property enforced by
/// `test/crux_license_core_barrel_test.dart`, not by inspection.
///
/// ```dart
/// import 'package:crux_license/crux_license.dart';       // Flutter hosts
/// import 'package:crux_license/crux_license_core.dart';  // headless hosts
/// ```
///
/// It is the pattern `crux_sqlite`'s test-support barrels follow too: the main
/// barrel stays the one a Flutter host imports, and the
/// constrained-environment subset gets its own import.
///
/// ### What is here, and what is deliberately not
///
/// Here: `LicenseTier` (+ `LicenseTierFeatures`), `FeatureGate`, the
/// `kBetaPeriod` / `kBetaExpiry` / `kAiExperimental` build flags, the
/// beta-expiry state machine (`BetaExpiryStatus`, `betaExpiryStatusFor`,
/// `daysUntilBetaExpiry`, `trustedBetaExpiryNow`), and the whole licensing
/// stack — `LicenseValidator` / `CruxLicenseValidator`, `CruxProduct`,
/// `LicenseClaims`, `LicenseGrant`, `LicenseValidation`, the credential
/// parser, `KeygenLicenseIssuer` and the generated policy table. That is
/// everything a CLI needs to answer "is this subcommand allowed?" and "has
/// this beta build expired?" — a headless Pro binary validates the very same
/// key the desktop app does, which is why the validator is pure Dart and
/// lives on this barrel rather than the Flutter one. The shared machine
/// fingerprint (`SharedInstallFingerprint`, `InstallFingerprintFile`) is here
/// for the same reason: a machine file resolves only on the machine whose
/// fingerprint it names, so a headless run has to read the same file the
/// desktop app does.
///
/// Not here, and not because of Flutter: `LicenseBadgeStrings` and
/// `CruxUpgradeDialogStrings` are pure Dart, but they exist only to feed the
/// badge and dialog widgets. Exporting them from a headless barrel would add
/// public surface with no headless consumer. They stay on the main barrel.
///
/// Also not here: every `*_provider.dart` seam
/// (`licenseTierProvider`, `betaPeriodProvider`, `betaExpiryStatusProvider`,
/// `aiExperimentalEnabledProvider`, …). Riverpod is a Flutter dependency in
/// this package, and a process with no `ProviderContainer` has nothing to read
/// them with — a headless host passes the active tier to
/// `FeatureGate.isAvailable` directly.
///
/// Everything exported here is also exported by `crux_license.dart`, so a
/// Flutter host never needs both imports and the two barrels cannot drift
/// apart in meaning.
library;

export 'src/ai_experimental.dart';
export 'src/beta_expiry.dart';
export 'src/beta_period.dart';
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
export 'src/license_grace.dart';
export 'src/license_grant.dart';
export 'src/license_issuer.dart';
export 'src/license_status.dart';
export 'src/license_tier.dart';
export 'src/license_tier_dev.dart';
export 'src/license_validation.dart';
export 'src/license_validator.dart';
export 'src/machine_release_marker.dart';
