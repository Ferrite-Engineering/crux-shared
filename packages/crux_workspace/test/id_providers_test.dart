// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tabIdProvider', () {
    test('throws when read at the root scope', () {
      final container = ProviderContainer();
      expect(
        () => container.read(tabIdProvider),
        throwsA(anything),
      );
      container.dispose();
    });

    test('resolves when overridden per tab', () {
      final id = TabId.generate();
      final container = ProviderContainer(
        overrides: [tabIdProvider.overrideWithValue(id)],
      );
      expect(container.read(tabIdProvider), equals(id));
      container.dispose();
    });
  });

  group('paneIdProvider', () {
    test('throws when read at the root scope', () {
      final container = ProviderContainer();
      expect(
        () => container.read(paneIdProvider),
        throwsA(anything),
      );
      container.dispose();
    });

    test('resolves when overridden per pane', () {
      final id = PaneId.generate();
      final container = ProviderContainer(
        overrides: [paneIdProvider.overrideWithValue(id)],
      );
      expect(container.read(paneIdProvider), equals(id));
      container.dispose();
    });
  });
}
