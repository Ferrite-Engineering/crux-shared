// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cruxColorThemeProvider', () {
    test('default factory yields the canonical default preset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final theme = container.read(cruxColorThemeProvider);
      expect(theme.id, defaultBuiltinPreset().id);
    });

    test('overrideWith honors a caller-supplied initial theme', () {
      final initial = builtinPresets()['solarized-dark']!;
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: initial),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(cruxColorThemeProvider).id, 'solarized-dark');
    });

    test('activate replaces the active theme', () {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(
              initial: builtinPresets()['crux-dark']!,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(cruxColorThemeProvider.notifier)
          .activate(builtinPresets()['oscilloscope']!);
      expect(container.read(cruxColorThemeProvider).id, 'oscilloscope');
    });

    test('applyOverrides layers onto current state', () {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(
              initial: builtinPresets()['crux-dark']!,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(cruxColorThemeProvider.notifier).applyOverrides({
        'canvas.background': const Color(0xFFFF0000),
      });
      expect(
        container.read(cruxColorThemeProvider).color('canvas', 'background'),
        const Color(0xFFFF0000),
      );
    });

    test('applyOverrides is a no-op for empty map', () {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(
              initial: builtinPresets()['crux-dark']!,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final before = container.read(cruxColorThemeProvider);
      container.read(cruxColorThemeProvider.notifier).applyOverrides(const {});
      final after = container.read(cruxColorThemeProvider);
      expect(identical(before, after), isTrue);
    });

    test('reset returns to the initial theme', () {
      final initial = builtinPresets()['crux-dark']!;
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: initial),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(cruxColorThemeProvider.notifier)
        ..activate(builtinPresets()['oscilloscope']!)
        ..applyOverrides({'canvas.background': const Color(0xFFFF00FF)})
        ..reset();

      final restored = container.read(cruxColorThemeProvider);
      expect(restored.id, initial.id);
      expect(
        restored.color('canvas', 'background'),
        initial.color('canvas', 'background'),
      );
    });
  });
}
