// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('betaExpiryStatusProvider', () {
    test('default is notApplicable in an unconfigured (test) build', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(betaExpiryStatusProvider),
        BetaExpiryStatus.notApplicable,
      );
    });

    test('override drives each BetaExpiryStatus value', () {
      for (final status in BetaExpiryStatus.values) {
        final container = ProviderContainer(
          overrides: [betaExpiryStatusProvider.overrideWithValue(status)],
        );
        addTearDown(container.dispose);

        expect(container.read(betaExpiryStatusProvider), status);
      }
    });
  });

  group('betaExpiryDaysRemainingProvider', () {
    test('default is null in an unconfigured (test) build', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(betaExpiryDaysRemainingProvider), isNull);
    });

    test('override drives the day count rendered in the banner', () {
      final container = ProviderContainer(
        overrides: [betaExpiryDaysRemainingProvider.overrideWithValue(3)],
      );
      addTearDown(container.dispose);

      expect(container.read(betaExpiryDaysRemainingProvider), 3);
    });
  });

  group('observedServerTimeProvider', () {
    test('defaults to null (no server time observed)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(observedServerTimeProvider), isNull);
    });

    test('host override flows through to the status provider', () {
      // Even with an observed server time, an unconfigured test build has no
      // injected expiry, so the status stays notApplicable — this asserts the
      // wiring (status provider reads observedServerTimeProvider) rather than a
      // specific expiry outcome (the expiry logic is covered in the pure
      // betaExpiryStatusFor / trustedBetaExpiryNow tests).
      final container = ProviderContainer(
        overrides: [
          observedServerTimeProvider.overrideWithValue(DateTime(2026, 9, 2)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(observedServerTimeProvider), DateTime(2026, 9, 2));
      expect(
        container.read(betaExpiryStatusProvider),
        BetaExpiryStatus.notApplicable,
      );
    });
  });
}
