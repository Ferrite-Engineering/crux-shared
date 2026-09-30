// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Allocation / complexity guards for the theme registry and codec.
///
/// These assert on *work done*, not wall-clock time, so they are stable
/// in CI. The pattern follows NetCrux's `analysis_complexity_guard_test`.
void main() {
  CruxColorTheme themeOf(String id, Color color) => CruxColorTheme(
    id: id,
    displayName: id,
    brightness: Brightness.dark,
    tokens: {
      'canvas': {
        for (var i = 0; i < 22; i++) 'token$i': color,
      },
      'chrome': {
        for (var i = 0; i < 14; i++) 'chrome$i': color,
      },
    },
  );

  group('CruxThemeExtension.lerp (item 4)', () {
    setUp(CruxThemeExtension.resetLerpPlanCacheForTesting);

    test('builds the key-union plan ONCE for a whole transition', () {
      final from = CruxThemeExtension(
        theme: themeOf('a', const Color(0xFF000000)),
      );
      final to = CruxThemeExtension(
        theme: themeOf('b', const Color(0xFFFFFFFF)),
      );

      // A MaterialApp theme transition is ~12 frames at 200ms/60fps;
      // ThemeData.lerp calls this once per frame. Before the fix each
      // of those frames rebuilt a category-key Set plus a token-key Set
      // per category.
      for (var frame = 1; frame < 60; frame++) {
        from.lerp(to, frame / 60);
      }

      expect(
        CruxThemeExtension.lerpPlanBuildCount,
        1,
        reason: 'the key unions are invariant in t and must be cached',
      );
    });

    test('a different theme pair rebuilds the plan', () {
      final a = CruxThemeExtension(
        theme: themeOf('a', const Color(0xFF000000)),
      );
      final b = CruxThemeExtension(
        theme: themeOf('b', const Color(0xFFFFFFFF)),
      );
      final c = CruxThemeExtension(
        theme: themeOf('c', const Color(0xFF808080)),
      );
      a
        ..lerp(b, 0.5)
        ..lerp(c, 0.5);
      expect(CruxThemeExtension.lerpPlanBuildCount, 2);
    });

    test('interpolates correctly — caching must not change results', () {
      final from = CruxThemeExtension(
        theme: themeOf('a', const Color(0xFF000000)),
      );
      final to = CruxThemeExtension(
        theme: themeOf('b', const Color(0xFFFFFFFF)),
      );
      final mid = from.lerp(to, 0.5);
      expect(
        mid.color('canvas', 'token0'),
        Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), 0.5),
      );
      // Metadata flips with the perceived theme past the midpoint.
      expect(from.lerp(to, 0.4).theme.id, 'a');
      expect(from.lerp(to, 0.6).theme.id, 'b');
    });

    test('endpoints and identity still short-circuit', () {
      final from = CruxThemeExtension(
        theme: themeOf('a', const Color(0xFF000000)),
      );
      final to = CruxThemeExtension(
        theme: themeOf('b', const Color(0xFFFFFFFF)),
      );
      expect(identical(from.lerp(to, 0), from), isTrue);
      expect(identical(from.lerp(to, 1), to), isTrue);
      expect(CruxThemeExtension.lerpPlanBuildCount, 0);
    });

    test('carries through tokens present on only one side', () {
      final left = CruxColorTheme(
        id: 'l',
        displayName: 'l',
        brightness: Brightness.dark,
        tokens: const {
          'canvas': {'only.left': Color(0xFF010101)},
        },
      );
      final right = CruxColorTheme(
        id: 'r',
        displayName: 'r',
        brightness: Brightness.dark,
        tokens: const {
          'chrome': {'only.right': Color(0xFF020202)},
        },
      );
      final mid = CruxThemeExtension(
        theme: left,
      ).lerp(CruxThemeExtension(theme: right), 0.5);
      expect(mid.color('canvas', 'only.left'), const Color(0xFF010101));
      expect(mid.color('chrome', 'only.right'), const Color(0xFF020202));
    });

    test('the lerp result is still a usable, correct theme', () {
      final from = CruxThemeExtension(
        theme: themeOf('a', const Color(0xFF000000)),
      );
      final to = CruxThemeExtension(
        theme: themeOf('b', const Color(0xFFFFFFFF)),
      );
      final mid = from.lerp(to, 0.5);
      expect(mid.theme.tokens.length, 2);
      expect(mid.hasToken('canvas', 'token5'), isTrue);
      expect(
        mid.colorOr('canvas', 'nope', const Color(0xFF123456)),
        const Color(0xFF123456),
      );
    });
  });

  group('cached hashCode (item 10)', () {
    // The caching itself (`late final int hashCode`) is a language-level
    // guarantee and not observably testable — asserting `identical` on two
    // reads of an int is vacuously true for any implementation. What IS
    // testable is that the cached value stays consistent with ==.
    test('equal themes still hash equally', () {
      expect(
        themeOf('a', const Color(0xFF000000)).hashCode,
        themeOf('a', const Color(0xFF000000)).hashCode,
      );
    });

    test('different themes still hash differently', () {
      expect(
        themeOf('a', const Color(0xFF000000)).hashCode,
        isNot(themeOf('a', const Color(0xFFFFFFFF)).hashCode),
      );
    });

    test('ThemePack.hashCode is stable and consistent with ==', () {
      ThemePack packOf() => ThemePack(
        id: 'p',
        displayName: 'P',
        brightness: Brightness.dark,
        tokens: const {
          'chrome': {'a': Color(0xFF010101), 'b': Color(0xFF020202)},
        },
      );
      final a = packOf();
      final b = packOf();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, a.hashCode);
    });
  });

  group('ThemeRegistry view caching (item 11)', () {
    setUp(ThemeRegistry.instance.resetForTesting);
    tearDown(ThemeRegistry.instance.resetForTesting);

    const category = ThemeTokenCategory(
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

    test('registeredCategories returns the same instance until a '
        'registration', () {
      ThemeRegistry.instance.registerCategory(category);
      final first = ThemeRegistry.instance.registeredCategories;
      expect(
        identical(ThemeRegistry.instance.registeredCategories, first),
        isTrue,
      );

      ThemeRegistry.instance.registerCategory(
        const ThemeTokenCategory(
          id: 'other',
          displayName: 'Other',
          tokens: [
            ThemeTokenDescriptor(
              id: 'x',
              displayName: 'X',
              lightDefault: Color(0xFFFFFFFF),
              darkDefault: Color(0xFF000000),
            ),
          ],
        ),
      );
      expect(
        identical(ThemeRegistry.instance.registeredCategories, first),
        isFalse,
      );
      expect(ThemeRegistry.instance.registeredCategories.length, 2);
    });

    test('allRegisteredTokens is cached the same way', () {
      ThemeRegistry.instance.registerCategory(category);
      final first = ThemeRegistry.instance.allRegisteredTokens;
      expect(
        identical(ThemeRegistry.instance.allRegisteredTokens, first),
        isTrue,
      );
      expect(first.keys, ['canvas.background']);
    });

    test('cached views are still unmodifiable', () {
      ThemeRegistry.instance.registerCategory(category);
      expect(
        () => ThemeRegistry.instance.registeredCategories.add(category),
        throwsUnsupportedError,
      );
    });
  });
}
