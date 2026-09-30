// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('licenseTierProvider', () {
    test('default value is LicenseTier.openCore', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(licenseTierProvider), LicenseTier.openCore);
    });

    test('override returns the supplied tier', () {
      final container = ProviderContainer(
        overrides: [
          licenseTierProvider.overrideWith((_) => LicenseTier.pro),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(licenseTierProvider), LicenseTier.pro);
    });

    test('override accepts every tier value', () {
      for (final tier in LicenseTier.values) {
        final container = ProviderContainer(
          overrides: [
            licenseTierProvider.overrideWith((_) => tier),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(licenseTierProvider), tier);
      }
    });
  });
}
