// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:crux_theme/src/widgets/preset_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _seed = Color(0xFF4F5BD5);

ThemeData _theme(Brightness brightness, {bool highContrast = false}) =>
    ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
        contrastLevel: highContrast ? 1 : 0,
      ),
    );

List<Color?> _swatchColors(WidgetTester tester) {
  final swatches = find.descendant(
    of: find.byType(Wrap),
    matching: find.byType(Container),
  );
  return [
    for (final element in swatches.evaluate())
      ((element.widget as Container).decoration! as BoxDecoration).color,
  ];
}

Future<void> _pump(
  WidgetTester tester,
  CruxColorTheme preset, {
  required ThemeMode mode,
  bool highContrast = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: MaterialApp(
        themeMode: mode,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        highContrastTheme: _theme(Brightness.light, highContrast: true),
        highContrastDarkTheme: _theme(Brightness.dark, highContrast: true),
        home: Scaffold(body: PresetPreview(theme: preset)),
      ),
    ),
  );
}

void main() {
  setUp(() {
    ThemeRegistry.instance.resetForTesting();
    registerCruxThemeChromeTokens();
  });

  tearDown(ThemeRegistry.instance.resetForTesting);

  group('PresetPreview built-in presets', () {
    for (final (id, brightness) in [
      (cruxDarkPresetId, Brightness.dark),
      (cruxLightPresetId, Brightness.light),
    ]) {
      for (final highContrast in [false, true]) {
        for (final mode in [ThemeMode.light, ThemeMode.dark]) {
          testWidgets('$id swatches match the resolved scheme '
              '(app ${mode.name}, highContrast: $highContrast)', (
            tester,
          ) async {
            final preset = builtinPresets()[id]!;
            await _pump(tester, preset, mode: mode, highContrast: highContrast);
            final colors = _swatchColors(tester);
            expect(colors, hasLength(8));
            for (final c in colors) {
              expect(c, isNotNull);
              expect(c!.a, greaterThan(0));
            }
            // The swatches show the product scheme for the preset's own
            // brightness and the platform contrast, whatever the app mode.
            final expected = _theme(brightness, highContrast: highContrast);
            final scheme = expected.colorScheme;
            expect(colors[0], expected.scaffoldBackgroundColor);
            expect(colors[1], scheme.surface);
            expect(colors[2], scheme.surfaceContainerHighest);
            expect(colors[3], scheme.onSurface);
            expect(colors[6], scheme.primary);
          });
        }
      }
    }

    testWidgets('a slot carrying the active preset tokens is not trusted', (
      tester,
    ) async {
      // The app's dark slot is recoloured for an active branded preset;
      // Crux Dark's swatches must not pick that up.
      final solarized = builtinPresets()['solarized-dark']!;
      final polluted = applyChromeTokens(
        _theme(Brightness.dark),
        CruxThemeExtension(theme: solarized),
      );
      await tester.pumpWidget(
        MaterialApp(
          themeMode: ThemeMode.dark,
          theme: _theme(Brightness.light),
          darkTheme: polluted,
          home: Scaffold(
            body: PresetPreview(theme: builtinPresets()[cruxDarkPresetId]!),
          ),
        ),
      );
      final colors = _swatchColors(tester);
      for (final c in colors) {
        expect(c!.a, greaterThan(0));
      }
      expect(colors[4], isNot(const Color(0xFF002B36)));
      expect(colors[6], isNot(const Color(0xFFB58900)));
    });

    testWidgets('explicit-token presets keep their own colours', (
      tester,
    ) async {
      final solarized = builtinPresets()['solarized-dark']!;
      await _pump(tester, solarized, mode: ThemeMode.light);
      final colors = _swatchColors(tester);
      expect(colors[0], const Color(0xFF002B36));
      expect(colors[1], const Color(0xFF073642));
      expect(colors[6], const Color(0xFFB58900));
    });
  });
}
