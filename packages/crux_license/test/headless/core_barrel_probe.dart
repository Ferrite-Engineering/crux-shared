// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Headless probe for the Flutter-free `crux_license_core.dart` barrel.
//
// This is NOT a test file (no `_test.dart` suffix, so `flutter test` ignores
// it). It is a plain Dart entry point that
// `test/crux_license_core_barrel_test.dart` executes with the standalone Dart
// VM. The VM has no `dart:ui`, so if any edit puts Flutter back into the
// barrel's transitive import closure this program fails to load — which is the
// same failure mode a product's `dart build cli` would hit, reproduced in
// three seconds instead of at release time.
//
// It touches a symbol from every export so tree-shaking cannot make the
// probe vacuous.
import 'dart:io';

import 'package:crux_license/crux_license_core.dart';

void main() {
  final results = <String>[
    'tier=${LicenseTier.pro.name}',
    'equivalent=${LicenseTier.edu.featureEquivalent.name}',
    'gate=${FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.openCore)}',
    'satisfies=${FeatureGate.satisfiesTier(LicenseTier.pro, LicenseTier.pro)}',
    'beta=$kBetaPeriod',
    'ai=$kAiExperimental',
    'expiry=${betaExpiryStatusFor(DateTime.utc(2030)).name}',
    'days=${daysUntilBetaExpiry(DateTime.utc(2030))}',
    'trusted=${trustedBetaExpiryNow(DateTime.utc(2030)).year}',
    'validator=${const NoopLicenseValidator().name}',
    'fingerprint=${mintInstallFingerprint().length}',
    'marker=${const NoMachineReleaseMarker().runtimeType}',
  ];
  // The exit code is what the guard asserts on; the output is what a human
  // reads when it fails. `stdout` rather than `print` because this is a CLI
  // entry point, not test code.
  stdout.writeln(results.join(' '));
}
