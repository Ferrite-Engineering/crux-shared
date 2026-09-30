// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/src/license_tier.dart';
import 'package:crux_license/src/license_tier_dev.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod provider exposing the user's currently active product tier.
///
/// Open-core builds of every Crux product resolve this to
/// [LicenseTier.openCore]. Each product's Pro
/// overlay overrides the provider with a value derived from the validated
/// license key:
///
/// ```dart
/// // In the Pro overlay's override list, once a LicenseService exists.
/// // Route through applyLicenseTierOverride so --dart-define=LICENSE_TIER
/// // still works in the builds that actually contain the paid features.
/// licenseTierProvider.overrideWith(
///   (ref) => applyLicenseTierOverride(
///     ref.watch(licenseServiceProvider).activeTier,
///   ),
/// ),
///
/// // Before then, or in tests, a fixed tier is enough:
/// licenseTierProvider.overrideWithValue(LicenseTier.pro),
/// ```
///
/// UI elements that gate behavior on tier (feature gates, tier badges,
/// settings sections, About-box edition labels) read from this provider
/// via `ref.watch`.
///
/// Declared as a manual `Provider` rather than a `@Riverpod`-codegen
/// function so cross-suite consumers don't have to wire build_runner just
/// to depend on this primitive — and to avoid the invariant-generics
/// footguns the codegen variant occasionally introduces at the override
/// site.
final licenseTierProvider = Provider<LicenseTier>(
  (ref) => applyLicenseTierOverride(LicenseTier.openCore),
  name: 'licenseTierProvider',
);
