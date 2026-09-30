// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CruxColorTheme makeTheme({
    String id = 'a',
    Map<String, Map<String, Color>>? tokens,
    Brightness brightness = Brightness.dark,
  }) {
    return CruxColorTheme(
      id: id,
      displayName: id.toUpperCase(),
      brightness: brightness,
      tokens:
          tokens ??
          {
            'canvas': {'background': const Color(0xFF111111)},
          },
    );
  }

  group('CruxThemeExtension', () {
    test('wraps the supplied theme', () {
      final theme = makeTheme();
      final ext = CruxThemeExtension(theme: theme);
      expect(ext.theme, theme);
    });

    test('color delegates to the wrapped theme', () {
      final ext = CruxThemeExtension(theme: makeTheme());
      expect(ext.color('canvas', 'background'), const Color(0xFF111111));
      expect(ext.color('canvas', 'missing'), isNull);
    });

    test('colorOr falls back', () {
      final ext = CruxThemeExtension(theme: makeTheme());
      expect(
        ext.colorOr('canvas', 'background', const Color(0xFFFFFFFF)),
        const Color(0xFF111111),
      );
      expect(
        ext.colorOr('canvas', 'missing', const Color(0xFFFFFFFF)),
        const Color(0xFFFFFFFF),
      );
    });

    test('hasToken reflects presence', () {
      final ext = CruxThemeExtension(theme: makeTheme());
      expect(ext.hasToken('canvas', 'background'), isTrue);
      expect(ext.hasToken('canvas', 'missing'), isFalse);
    });

    test('copyWith replaces the wrapped theme', () {
      final ext = CruxThemeExtension(theme: makeTheme());
      final replacement = makeTheme(id: 'b');
      final copy = ext.copyWith(theme: replacement);
      expect(copy.theme, replacement);
    });

    test('copyWith preserves theme when null', () {
      final theme = makeTheme();
      final ext = CruxThemeExtension(theme: theme);
      expect(ext.copyWith().theme, theme);
    });

    test('equality is value-based on the wrapped theme', () {
      final a = CruxThemeExtension(theme: makeTheme());
      final b = CruxThemeExtension(theme: makeTheme());
      final c = CruxThemeExtension(theme: makeTheme(id: 'b'));
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('CruxThemeExtension.lerp', () {
    final left = CruxThemeExtension(
      theme: makeTheme(
        id: 'left',
        tokens: const {
          'canvas': {
            'background': Color(0xFF000000),
            'foreground': Color(0xFF000000),
          },
        },
      ),
    );
    final right = CruxThemeExtension(
      theme: makeTheme(
        id: 'right',
        tokens: const {
          'canvas': {
            'background': Color(0xFFFFFFFF),
            'foreground': Color(0xFFFFFFFF),
          },
        },
      ),
    );

    test('t=0 returns the left instance', () {
      expect(identical(left.lerp(right, 0), left), isTrue);
    });

    test('t=1 returns the right instance', () {
      expect(identical(left.lerp(right, 1), right), isTrue);
    });

    test('t=0.5 produces a midpoint color', () {
      final mid = left.lerp(right, 0.5);
      final color = mid.color('canvas', 'background')!;
      // Color.lerp(black, white, 0.5) ≈ 0xFF7F7F7F.
      // Use a tight tolerance to keep the test stable across SDK
      // versions where rounding may differ by 1 in any channel.
      const expected = 0x7F;
      expect((color.r * 255).round(), closeTo(expected, 1));
      expect((color.g * 255).round(), closeTo(expected, 1));
      expect((color.b * 255).round(), closeTo(expected, 1));
    });

    test('returns this when other is null', () {
      expect(identical(left.lerp(null, 0.5), left), isTrue);
    });

    test('carries through tokens absent from the other side', () {
      final extendedLeft = CruxThemeExtension(
        theme: makeTheme(
          id: 'left',
          tokens: const {
            'canvas': {
              'background': Color(0xFF000000),
              'left-only': Color(0xFF112233),
            },
          },
        ),
      );
      final mid = extendedLeft.lerp(right, 0.5);
      expect(mid.color('canvas', 'left-only'), const Color(0xFF112233));
    });

    test('destination identity flips at the midpoint', () {
      final before = left.lerp(right, 0.49);
      final after = left.lerp(right, 0.51);
      expect(before.theme.id, 'left');
      expect(after.theme.id, 'right');
    });

    test('handles entirely new categories on either side', () {
      final extendedRight = CruxThemeExtension(
        theme: makeTheme(
          id: 'right',
          tokens: const {
            'canvas': {'background': Color(0xFFFFFFFF)},
            'severity': {'error': Color(0xFFFF0000)},
          },
        ),
      );
      final mid = left.lerp(extendedRight, 0.5);
      expect(mid.color('severity', 'error'), const Color(0xFFFF0000));
    });
  });
}
