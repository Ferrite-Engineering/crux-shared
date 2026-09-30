// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CruxThemeExtension _chromeExt(Map<String, Color> chrome) => CruxThemeExtension(
  theme: CruxColorTheme(
    id: 'test',
    displayName: 'Test',
    brightness: Brightness.dark,
    tokens: <String, Map<String, Color>>{
      chromeCategoryId: chrome,
    },
  ),
);

void main() {
  group('applyChromeTokens', () {
    test('passes through base when no chrome tokens supplied', () {
      final base = ThemeData(
        scaffoldBackgroundColor: const Color(0xFF101010),
      );
      final result = applyChromeTokens(base, _chromeExt(const {}));
      expect(result.scaffoldBackgroundColor, const Color(0xFF101010));
      expect(result.colorScheme, base.colorScheme);
    });

    test('overrides scaffoldBackgroundColor from chrome token', () {
      final base = ThemeData(
        scaffoldBackgroundColor: const Color(0xFF101010),
      );
      final result = applyChromeTokens(
        base,
        _chromeExt(const {
          ChromeTokens.scaffoldBackground: Color(0xFF002B36),
        }),
      );
      expect(result.scaffoldBackgroundColor, const Color(0xFF002B36));
    });

    test('overrides ColorScheme.surface from panelBackground token', () {
      final base = ThemeData(
        colorScheme: const ColorScheme.dark(),
      );
      final result = applyChromeTokens(
        base,
        _chromeExt(const {
          ChromeTokens.panelBackground: Color(0xFF073642),
        }),
      );
      expect(result.colorScheme.surface, const Color(0xFF073642));
    });

    test('overrides AppBarTheme.backgroundColor from toolbar token', () {
      final base = ThemeData();
      final result = applyChromeTokens(
        base,
        _chromeExt(const {
          ChromeTokens.toolbarBackground: Color(0xFF002B36),
        }),
      );
      expect(result.appBarTheme.backgroundColor, const Color(0xFF002B36));
    });

    test('ignores fully transparent sentinel tokens', () {
      final base = ThemeData(
        scaffoldBackgroundColor: const Color(0xFF101010),
      );
      final result = applyChromeTokens(
        base,
        _chromeExt(const {
          ChromeTokens.scaffoldBackground: Color(0x00FF0000),
        }),
      );
      expect(result.scaffoldBackgroundColor, const Color(0xFF101010));
    });

    test('preserves the base ThemeData extensions on the result', () {
      final chrome = _chromeExt(const {
        ChromeTokens.toolbarBackground: Color(0xFF002B36),
      });
      final base = ThemeData(extensions: <ThemeExtension<dynamic>>[chrome]);
      final result = applyChromeTokens(base, chrome);
      expect(result.extension<CruxThemeExtension>(), chrome);
    });
  });

  // The eight tokens Material has no slot for travel on CruxChromeColors. Each
  // must land in its own field: a token read into the wrong field, or not at
  // all, is the "setting that silently does nothing" this guards against.
  group('applyChromeTokens → CruxChromeColors', () {
    final fieldOf = <String, Color? Function(CruxChromeColors)>{
      ChromeTokens.toolbarIconActive: (c) => c.toolbarIconActive,
      ChromeTokens.statusBarBackground: (c) => c.statusBarBackground,
      ChromeTokens.statusBarForeground: (c) => c.statusBarForeground,
      ChromeTokens.splitter: (c) => c.splitter,
      ChromeTokens.splitterHover: (c) => c.splitterHover,
      ChromeTokens.tabBarBackground: (c) => c.tabBarBackground,
      ChromeTokens.tabBarSelected: (c) => c.tabBarSelected,
      ChromeTokens.tabBarLabel: (c) => c.tabBarLabel,
    };

    test('covers every catalog token the Material overrides do not', () {
      const material = {
        ChromeTokens.scaffoldBackground,
        ChromeTokens.panelBackground,
        ChromeTokens.panelHeaderBackground,
        ChromeTokens.panelHeaderForeground,
        ChromeTokens.toolbarBackground,
        ChromeTokens.toolbarIcon,
      };
      expect(
        chromeTokens.tokens.map((t) => t.id).toSet(),
        {...material, ...fieldOf.keys},
        reason:
            'A chrome token that neither becomes a Material override nor a '
            'CruxChromeColors field is offered in Settings and paints nothing.',
      );
    });

    for (final entry in fieldOf.entries) {
      test('${entry.key} lands in its own field and no other', () {
        const color = Color(0xFF123456);
        final colors = applyChromeTokens(
          ThemeData(),
          _chromeExt({entry.key: color}),
        ).extension<CruxChromeColors>()!;
        for (final other in fieldOf.entries) {
          expect(
            other.value(colors),
            other.key == entry.key ? color : isNull,
            reason: '${entry.key} set; reading ${other.key}',
          );
        }
      });
    }

    test('a theme with none of them installs an empty extension', () {
      final colors = applyChromeTokens(
        ThemeData(),
        _chromeExt(const {}),
      ).extension<CruxChromeColors>();
      expect(colors, isNotNull);
      expect(colors!.isEmpty, isTrue);
    });

    test('the transparent sentinel leaves the field unset', () {
      final colors = applyChromeTokens(
        ThemeData(),
        _chromeExt(const {ChromeTokens.statusBarBackground: Color(0x00FF0000)}),
      ).extension<CruxChromeColors>()!;
      expect(colors.statusBarBackground, isNull);
    });

    test('a translucent token keeps its alpha', () {
      final colors = applyChromeTokens(
        ThemeData(),
        _chromeExt(const {ChromeTokens.statusBarForeground: Color(0xBF93A1A1)}),
      ).extension<CruxChromeColors>()!;
      expect(colors.statusBarForeground, const Color(0xBF93A1A1));
    });

    test('an unset token keeps the base theme value; a set one wins', () {
      const base = CruxChromeColors(
        splitter: Color(0xFF0000AA),
        tabBarLabel: Color(0xFF0000BB),
      );
      final result = applyChromeTokens(
        ThemeData(extensions: const [base]),
        _chromeExt(const {ChromeTokens.tabBarLabel: Color(0xFF0000CC)}),
      );
      final colors = result.extension<CruxChromeColors>()!;
      expect(colors.splitter, const Color(0xFF0000AA));
      expect(colors.tabBarLabel, const Color(0xFF0000CC));
      expect(
        result.extensions.values.whereType<CruxChromeColors>(),
        hasLength(1),
      );
    });

    // Riverpod rebuilds the app on a theme edit, and Theme's inherited
    // widget only notifies its dependents when the ThemeData changes. That
    // comparison reaches the extension through its `==`.
    test('a token edit changes the resulting ThemeData', () {
      final before = applyChromeTokens(ThemeData(), _chromeExt(const {}));
      final after = applyChromeTokens(
        ThemeData(),
        _chromeExt(const {ChromeTokens.splitterHover: Color(0xFF00FF00)}),
      );
      final same = applyChromeTokens(ThemeData(), _chromeExt(const {}));
      expect(after, isNot(before));
      expect(same, before);
    });
  });

  group('themeModeFromBrightness', () {
    test('light brightness → ThemeMode.light', () {
      final theme = CruxColorTheme(
        id: 't',
        displayName: 't',
        brightness: Brightness.light,
        tokens: const {},
      );
      expect(themeModeFromBrightness(theme), ThemeMode.light);
    });

    test('dark brightness → ThemeMode.dark', () {
      final theme = CruxColorTheme(
        id: 't',
        displayName: 't',
        brightness: Brightness.dark,
        tokens: const {},
      );
      expect(themeModeFromBrightness(theme), ThemeMode.dark);
    });
  });
}
