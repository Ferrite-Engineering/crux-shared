// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// These cover both states of a *compile-time* flag, so the suite is
/// meaningful whether or not `--dart-define=LICENSE_TIER` was passed. Run it
/// both ways; CI runs the undefined case, and the defined case is what you
/// exercise locally before trusting a tier walkthrough:
///
/// ```sh
/// flutter test --dart-define=LICENSE_TIER=enterprise
/// ```
void main() {
  group('licenseTierOverride', () {
    test('is null exactly when the define is absent', () {
      if (kLicenseTierOverrideName.isEmpty) {
        expect(licenseTierOverride, isNull);
      } else {
        expect(licenseTierOverride, isNotNull);
      }
    });

    test('resolves to the tier whose name was given', () {
      if (kLicenseTierOverrideName.isEmpty) return;
      expect(
        licenseTierOverride!.name.toLowerCase(),
        kLicenseTierOverrideName.toLowerCase(),
      );
    });
  });

  group('applyLicenseTierOverride', () {
    test('is the identity when no override is set', () {
      if (kLicenseTierOverrideName.isNotEmpty) return;
      for (final tier in LicenseTier.values) {
        expect(applyLicenseTierOverride(tier), tier);
      }
    });

    test('wins over the resolved tier when set', () {
      if (kLicenseTierOverrideName.isEmpty) return;
      for (final tier in LicenseTier.values) {
        expect(applyLicenseTierOverride(tier), licenseTierOverride);
      }
    });
  });

  test('the override is independent of the beta flag', () {
    // In a BETA_PERIOD=true build a tier override does not, on its own, make
    // gating bite: FeatureGate short-circuits on kBetaPeriod first.
    // Documenting that here so nobody "fixes" the flags after a walkthrough
    // that appeared to do nothing.
    expect(
      FeatureGate.isAvailable(LicenseTier.enterprise, LicenseTier.openCore),
      kBetaPeriod ? isTrue : isFalse,
    );
  });
}
