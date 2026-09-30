// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _strings = ThemeAppearanceStringsEn();

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

final _preset = CruxColorTheme(
  id: 'preset-a',
  displayName: 'Preset A',
  brightness: Brightness.dark,
  tokens: const {
    'canvas': {'background': Color(0xFF111111)},
  },
);

Widget _wrap({
  required ProviderContainer container,
  required Widget child,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

ProviderContainer _container() => ProviderContainer(
  overrides: [
    cruxColorThemeProvider.overrideWith(
      () => CruxColorThemeNotifier(initial: _preset),
    ),
  ],
);

void main() {
  setUp(() async {
    ThemeRegistry.instance.resetForTesting();
    ThemeRegistry.instance.registerCategory(_category);
  });

  tearDown(() async {
    ThemeRegistry.instance.resetForTesting();
  });

  group('ThemeAppearanceSection', () {
    testWidgets('renders title, subtitle, and every section heading', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container: container,
          child: ThemeAppearanceSection(
            presets: [_preset],
            store: InMemoryThemePackStore(),
            pickPackDocument: () async => null,
            savePackDocument: (_) async => null,
          ),
        ),
      );
      await tester.pump();
      expect(find.text(_strings.sectionTitle), findsOneWidget);
      expect(find.text(_strings.sectionSubtitle), findsOneWidget);
      expect(find.text(_strings.presetSectionHeading), findsOneWidget);
      expect(find.text(_strings.tokenOverridesSectionHeading), findsOneWidget);
      expect(
        find.text(_strings.themePackBrowserSectionHeading),
        findsOneWidget,
      );
    });

    testWidgets('composes the three core surfaces in default order', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container: container,
          child: ThemeAppearanceSection(
            presets: [_preset],
            store: InMemoryThemePackStore(),
            pickPackDocument: () async => null,
            savePackDocument: (_) async => null,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(PresetPicker), findsOneWidget);
      expect(find.byType(TokenCategorySection), findsOneWidget);
      expect(find.byType(ThemePackBrowser), findsOneWidget);
    });

    testWidgets('showAdvancedOverrides: false hides the token override block', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container: container,
          child: ThemeAppearanceSection(
            presets: [_preset],
            store: InMemoryThemePackStore(),
            pickPackDocument: () async => null,
            savePackDocument: (_) async => null,
            showAdvancedOverrides: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TokenCategorySection), findsNothing);
      expect(
        find.text(_strings.tokenOverridesSectionHeading),
        findsNothing,
      );
    });

    testWidgets('trailingActions render below the pack browser', (
      tester,
    ) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _wrap(
          container: container,
          child: ThemeAppearanceSection(
            presets: [_preset],
            store: InMemoryThemePackStore(),
            pickPackDocument: () async => null,
            savePackDocument: (_) async => null,
            trailingActions: const [
              Text('trailing-marker'),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.text('trailing-marker'), findsOneWidget);
    });
  });
}
