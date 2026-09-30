// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('betaPeriodProvider', () {
    test('default value matches kBetaPeriod', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(betaPeriodProvider), kBetaPeriod);
    });

    test('override to false reflects post-beta gating', () {
      final container = ProviderContainer(
        overrides: [betaPeriodProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);

      expect(container.read(betaPeriodProvider), isFalse);
    });

    test('override to true reflects beta-period gating', () {
      final container = ProviderContainer(
        overrides: [betaPeriodProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(container.read(betaPeriodProvider), isTrue);
    });
  });
}
