// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeatureGate.isAvailable', () {
    // isAvailable reads the compile-time kBetaPeriod, which no provider
    // override reaches, so each branch can only run in the build it
    // describes. Rather than return early and pass without asserting
    // anything, the branch that does not apply is reported as skipped.
    //
    // A build with no define has ended the beta, so the delegation test is
    // the one every default run executes. The beta short-circuit is pinned
    // by define in crux_license_core_test.dart, which runs the headless probe
    // under BETA_PERIOD=true as well as false, so neither branch depends on
    // how the suite happens to be invoked.
    test(
      'returns true for every input in a beta build',
      () {
        expect(
          FeatureGate.isAvailable(LicenseTier.pro, LicenseTier.openCore),
          isTrue,
        );
        expect(
          FeatureGate.isAvailable(LicenseTier.enterprise, LicenseTier.openCore),
          isTrue,
        );
        expect(
          FeatureGate.isAvailable(LicenseTier.enterprise, LicenseTier.edu),
          isTrue,
        );
      },
      skip: kBetaPeriod
          ? false
          : 'needs --dart-define=BETA_PERIOD=true; the headless probe in '
                'crux_license_core_test.dart runs it that way on every run',
    );

    test(
      'delegates to satisfiesTier once beta is off',
      () {
        for (final required in LicenseTier.values) {
          for (final current in LicenseTier.values) {
            expect(
              FeatureGate.isAvailable(required, current),
              FeatureGate.satisfiesTier(required, current),
            );
          }
        }
      },
      skip: kBetaPeriod ? 'this build defines BETA_PERIOD=true' : false,
    );
  });

  // The post-beta tier ordering, tested directly against satisfiesTier so it
  // runs in EVERY build — not gated behind `if (kBetaPeriod) return;`, which
  // was the vacuous pattern this suite used to ship. These assertions are the
  // production gating contract the moment beta flips off.
  group('FeatureGate.satisfiesTier (post-beta tier ordering)', () {
    test('openCore satisfies only openCore', () {
      expect(
        FeatureGate.satisfiesTier(LicenseTier.openCore, LicenseTier.openCore),
        isTrue,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.pro, LicenseTier.openCore),
        isFalse,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.enterprise, LicenseTier.openCore),
        isFalse,
      );
    });

    test('pro satisfies openCore + pro, not enterprise', () {
      expect(
        FeatureGate.satisfiesTier(LicenseTier.openCore, LicenseTier.pro),
        isTrue,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.pro, LicenseTier.pro),
        isTrue,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.enterprise, LicenseTier.pro),
        isFalse,
      );
    });

    test('enterprise satisfies everything', () {
      expect(
        FeatureGate.satisfiesTier(
          LicenseTier.enterprise,
          LicenseTier.enterprise,
        ),
        isTrue,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.pro, LicenseTier.enterprise),
        isTrue,
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.openCore, LicenseTier.enterprise),
        isTrue,
      );
    });

    test('EDU satisfies the Pro gate but not the Enterprise gate', () {
      expect(
        FeatureGate.satisfiesTier(LicenseTier.pro, LicenseTier.edu),
        isTrue,
        reason: 'EDU is feature-equivalent to Pro',
      );
      expect(
        FeatureGate.satisfiesTier(LicenseTier.enterprise, LicenseTier.edu),
        isFalse,
        reason: 'EDU does not unlock Enterprise features',
      );
    });
  });

  // The provider-aware gate pattern documented on betaPeriodProvider and used
  // verbatim by every product's feature code:
  //   ref.watch(betaPeriodProvider)
  //     || FeatureGate.satisfiesTier(required, tier)
  // Overriding betaPeriodProvider(false) exercises the real post-beta gate
  // through Riverpod without a rebuild — the mechanism the whole suite's
  // gate-closed tests rely on.
  group('provider-aware gate (betaPeriodProvider override)', () {
    bool gateOpen(ProviderContainer c, LicenseTier required) {
      final beta = c.read(betaPeriodProvider);
      final tier = c.read(licenseTierProvider);
      return beta || FeatureGate.satisfiesTier(required, tier);
    }

    test('beta=true admits every tier regardless of required', () {
      final c = ProviderContainer(
        overrides: [
          betaPeriodProvider.overrideWithValue(true),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        ],
      );
      addTearDown(c.dispose);
      expect(gateOpen(c, LicenseTier.pro), isTrue);
      expect(gateOpen(c, LicenseTier.enterprise), isTrue);
    });

    test('beta=false + openCore denies a Pro gate', () {
      final c = ProviderContainer(
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        ],
      );
      addTearDown(c.dispose);
      expect(gateOpen(c, LicenseTier.pro), isFalse);
    });

    test('beta=false + pro admits a Pro gate, denies Enterprise', () {
      final c = ProviderContainer(
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.pro),
        ],
      );
      addTearDown(c.dispose);
      expect(gateOpen(c, LicenseTier.pro), isTrue);
      expect(gateOpen(c, LicenseTier.enterprise), isFalse);
    });

    test('beta=false + edu admits a Pro gate (feature-equivalent)', () {
      final c = ProviderContainer(
        overrides: [
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.edu),
        ],
      );
      addTearDown(c.dispose);
      expect(gateOpen(c, LicenseTier.pro), isTrue);
      expect(gateOpen(c, LicenseTier.enterprise), isFalse);
    });
  });
}
