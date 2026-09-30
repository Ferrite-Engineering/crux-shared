// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _descriptor = ThemeTokenDescriptor(
  id: 'background',
  displayName: 'Background',
  lightDefault: Color(0xFFFFFFFF),
  darkDefault: Color(0xFF000000),
  description: 'The base canvas color.',
);

const _category = ThemeTokenCategory(
  id: 'canvas',
  displayName: 'Canvas',
  tokens: [_descriptor],
);

CruxColorTheme _emptyDarkTheme() => CruxColorTheme(
  id: 'test',
  displayName: 'Test',
  brightness: Brightness.dark,
  tokens: const {},
);

CruxColorTheme _overriddenDarkTheme() => CruxColorTheme(
  id: 'test',
  displayName: 'Test',
  brightness: Brightness.dark,
  tokens: const {
    'canvas': {'background': Color(0xFF112233)},
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

  group('TokenEditor', () {
    testWidgets('renders displayName and description', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _emptyDarkTheme()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          const TokenEditor(
            categoryId: 'canvas',
            descriptor: _descriptor,
          ),
        ),
      );
      expect(find.text('Background'), findsOneWidget);
      expect(find.text('The base canvas color.'), findsOneWidget);
    });

    testWidgets('reset button is disabled when no override is active', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _emptyDarkTheme()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          const TokenEditor(
            categoryId: 'canvas',
            descriptor: _descriptor,
          ),
        ),
      );
      final iconButton = tester.widget<IconButton>(
        find.byType(IconButton),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('reset button is enabled and clears the override on tap', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          cruxColorThemeProvider.overrideWith(
            () => CruxColorThemeNotifier(initial: _overriddenDarkTheme()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          const TokenEditor(
            categoryId: 'canvas',
            descriptor: _descriptor,
          ),
        ),
      );
      final beforeIcon = tester.widget<IconButton>(find.byType(IconButton));
      expect(beforeIcon.onPressed, isNotNull);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      final theme = container.read(cruxColorThemeProvider);
      expect(theme.hasToken('canvas', 'background'), isFalse);
    });
  });
}
