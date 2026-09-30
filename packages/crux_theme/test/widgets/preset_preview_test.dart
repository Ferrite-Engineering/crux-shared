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
    ThemeTokenDescriptor(
      id: 'cursor.primary',
      displayName: 'Primary cursor',
      lightDefault: Color(0xFF886600),
      darkDefault: Color(0xFFFFFF00),
    ),
  ],
);

CruxColorTheme _theme() => CruxColorTheme(
  id: 't',
  displayName: 'T',
  brightness: Brightness.dark,
  tokens: const {
    'canvas': {
      'background': Color(0xFF111111),
      'cursor.primary': Color(0xFF222222),
    },
  },
);

void main() {
  setUp(() {
    ThemeRegistry.instance.resetForTesting();
    ThemeRegistry.instance.registerCategory(_category);
  });

  tearDown(ThemeRegistry.instance.resetForTesting);

  group('PresetPreview', () {
    testWidgets('renders a swatch per registered token by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PresetPreview(theme: _theme())),
          ),
        ),
      );
      // Two registered tokens → two Container swatches inside the Wrap.
      final wrap = find.byType(Wrap);
      expect(wrap, findsOneWidget);
      final swatches = find.descendant(
        of: wrap,
        matching: find.byType(Container),
      );
      expect(swatches, findsNWidgets(2));
    });

    testWidgets('honors an explicit token list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PresetPreview(
                theme: _theme(),
                tokens: const [('canvas', 'background')],
              ),
            ),
          ),
        ),
      );
      final wrap = find.byType(Wrap);
      final swatches = find.descendant(
        of: wrap,
        matching: find.byType(Container),
      );
      expect(swatches, findsOneWidget);
    });

    testWidgets('falls back to a background swatch when no tokens resolve', (
      tester,
    ) async {
      ThemeRegistry.instance.resetForTesting();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PresetPreview(theme: _theme())),
          ),
        ),
      );
      // No Wrap (empty path) and a single Container fallback.
      expect(find.byType(Wrap), findsNothing);
    });
  });
}
