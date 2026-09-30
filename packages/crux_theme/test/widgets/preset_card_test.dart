// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
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

CruxColorTheme _theme({Brightness brightness = Brightness.dark}) =>
    CruxColorTheme(
      id: 'preset-1',
      displayName: 'Preset One',
      brightness: brightness,
      tokens: const {
        'canvas': {'background': Color(0xFF111111)},
      },
    );

void main() {
  setUp(() {
    ThemeRegistry.instance.resetForTesting();
    ThemeRegistry.instance.registerCategory(_category);
  });

  tearDown(ThemeRegistry.instance.resetForTesting);

  group('PresetCard', () {
    testWidgets('renders displayName and brightness icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PresetCard(
                theme: _theme(),
                isActive: false,
                onActivate: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Preset One'), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    });

    testWidgets('renders light_mode icon for a light brightness theme', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PresetCard(
                theme: _theme(brightness: Brightness.light),
                isActive: false,
                onActivate: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.light_mode), findsOneWidget);
    });

    testWidgets('tap dispatches onActivate', (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PresetCard(
                theme: _theme(),
                isActive: false,
                onActivate: () => activations++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PresetCard));
      await tester.pump();
      expect(activations, 1);
    });

    testWidgets('isActive renders a Semantics node marked selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PresetCard(
                theme: _theme(),
                isActive: true,
                onActivate: () {},
              ),
            ),
          ),
        ),
      );
      const strings = ThemeAppearanceStringsEn();
      expect(
        find.bySemanticsLabel(strings.activePresetIndicatorLabel),
        findsOneWidget,
      );
    });
  });
}
