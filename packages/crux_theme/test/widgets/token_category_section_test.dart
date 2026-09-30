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
    ThemeTokenDescriptor(
      id: 'cursor.primary',
      displayName: 'Primary cursor',
      lightDefault: Color(0xFF886600),
      darkDefault: Color(0xFFFFFF00),
    ),
  ],
);

const _emptyCategory = ThemeTokenCategory(
  id: 'empty',
  displayName: 'Empty Category',
  // Tokens list must not be empty per the registration API, but the
  // widget still defends against an empty render path for robustness.
  tokens: [
    ThemeTokenDescriptor(
      id: 'placeholder',
      displayName: 'Placeholder',
      lightDefault: Color(0xFFFFFFFF),
      darkDefault: Color(0xFF000000),
    ),
  ],
);

CruxColorTheme _emptyDarkTheme() => CruxColorTheme(
  id: 'test',
  displayName: 'Test',
  brightness: Brightness.dark,
  tokens: const {},
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
    ThemeRegistry.instance.registerCategory(_emptyCategory);
  });

  tearDown(ThemeRegistry.instance.resetForTesting);

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        cruxColorThemeProvider.overrideWith(
          () => CruxColorThemeNotifier(initial: _emptyDarkTheme()),
        ),
      ],
    );
  }

  group('TokenCategorySection', () {
    testWidgets('starts collapsed by default — does not render editors', (
      tester,
    ) async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          const TokenCategorySection(category: _category),
        ),
      );
      expect(find.text('Canvas'), findsOneWidget);
      expect(find.text('Background'), findsNothing);
      expect(find.text('Primary cursor'), findsNothing);
    });

    testWidgets('initiallyExpanded renders every editor', (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container,
          const TokenCategorySection(
            category: _category,
            initiallyExpanded: true,
          ),
        ),
      );
      expect(find.text('Background'), findsOneWidget);
      expect(find.text('Primary cursor'), findsOneWidget);
    });

    testWidgets('tapping the header toggles and fires onExpansionChanged', (
      tester,
    ) async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final reports = <bool>[];
      await tester.pumpWidget(
        _wrap(
          container,
          TokenCategorySection(
            category: _category,
            onExpansionChanged: reports.add,
          ),
        ),
      );
      // Body hidden initially.
      expect(find.text('Background'), findsNothing);

      await tester.tap(find.text('Canvas'));
      await tester.pump();
      expect(reports, [true]);
      expect(find.text('Background'), findsOneWidget);

      await tester.tap(find.text('Canvas'));
      await tester.pump();
      expect(reports, [true, false]);
      expect(find.text('Background'), findsNothing);
    });
  });
}
