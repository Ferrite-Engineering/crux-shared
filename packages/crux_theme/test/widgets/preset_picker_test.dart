// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _category = ThemeTokenCategory(
  id: 'canvas',
  displayName: 'Canvas',
  tokens: [
    ThemeTokenDescriptor(
      id: 'background',
      displayName: 'Background',
      lightDefault: Color(0xFFFFFFFF),
      darkDefault: Color(0xFF000000),
    ),
  ],
);

final _presetA = CruxColorTheme(
  id: 'a',
  displayName: 'A',
  brightness: Brightness.dark,
  tokens: const {
    'canvas': {'background': Color(0xFF111111)},
  },
);

final _presetB = CruxColorTheme(
  id: 'b',
  displayName: 'B',
  brightness: Brightness.light,
  tokens: const {
    'canvas': {'background': Color(0xFFFFFFFF)},
  },
);

Widget _wrap(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    ThemeRegistry.instance.resetForTesting();
    ThemeRegistry.instance.registerCategory(_category);
  });

  tearDown(ThemeRegistry.instance.resetForTesting);

  group('PresetPicker', () {
    testWidgets('renders one PresetCard per preset', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _presetA),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          PresetPicker(presets: [_presetA, _presetB]),
        ),
      );
      expect(find.byType(PresetCard), findsNWidgets(2));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('renders empty-state message when presets is empty', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _presetA),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(container, const PresetPicker(presets: [])),
      );
      const strings = ThemeAppearanceStringsEn();
      expect(find.text(strings.noPresetsAvailableMessage), findsOneWidget);
    });

    testWidgets('tapping a card activates the corresponding preset', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _presetA),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          PresetPicker(presets: [_presetA, _presetB]),
        ),
      );
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(container.read(cruxColorThemeProvider).id, 'b');
    });
  });
}
