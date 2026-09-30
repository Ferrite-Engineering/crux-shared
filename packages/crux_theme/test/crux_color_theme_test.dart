// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CruxColorTheme makeTheme({
    String id = 'test',
    String displayName = 'Test',
    Brightness brightness = Brightness.dark,
    Map<String, Map<String, Color>>? tokens,
  }) {
    return CruxColorTheme(
      id: id,
      displayName: displayName,
      brightness: brightness,
      tokens:
          tokens ??
          {
            'canvas': {
              'background': const Color(0xFF1A1A1A),
              'foreground': const Color(0xFFE0E0E0),
            },
            'chrome': {
              'scaffold': const Color(0xFF202020),
            },
          },
    );
  }

  group('CruxColorTheme', () {
    test('stores all fields', () {
      final theme = makeTheme();
      expect(theme.id, 'test');
      expect(theme.displayName, 'Test');
      expect(theme.brightness, Brightness.dark);
      expect(theme.tokens.length, 2);
    });

    test('token map is unmodifiable', () {
      final mutable = {
        'canvas': {'background': const Color(0xFF000000)},
      };
      final theme = makeTheme(tokens: mutable);
      expect(
        () => theme.tokens['canvas'] = {'background': const Color(0xFFFFFFFF)},
        throwsUnsupportedError,
      );
      expect(
        () => theme.tokens['canvas']!['background'] = const Color(0xFFFFFFFF),
        throwsUnsupportedError,
      );
    });

    test('mutating the source map after construction does not leak', () {
      final source = <String, Map<String, Color>>{
        'canvas': {'background': const Color(0xFF1A1A1A)},
      };
      final theme = CruxColorTheme(
        id: 'x',
        displayName: 'X',
        brightness: Brightness.dark,
        tokens: source,
      );
      source['canvas']!['background'] = const Color(0xFFFF0000);
      source['extra'] = {'foo': const Color(0xFF00FF00)};
      expect(theme.color('canvas', 'background'), const Color(0xFF1A1A1A));
      expect(theme.hasToken('extra', 'foo'), isFalse);
    });

    test('color returns stored value or null', () {
      final theme = makeTheme();
      expect(theme.color('canvas', 'background'), const Color(0xFF1A1A1A));
      expect(theme.color('canvas', 'missing'), isNull);
      expect(theme.color('missing', 'background'), isNull);
    });

    test('colorOr falls back when token absent', () {
      final theme = makeTheme();
      expect(
        theme.colorOr('canvas', 'background', const Color(0xFFAA0000)),
        const Color(0xFF1A1A1A),
      );
      expect(
        theme.colorOr('canvas', 'missing', const Color(0xFFAA0000)),
        const Color(0xFFAA0000),
      );
    });

    test('hasToken reports presence', () {
      final theme = makeTheme();
      expect(theme.hasToken('canvas', 'background'), isTrue);
      expect(theme.hasToken('canvas', 'missing'), isFalse);
      expect(theme.hasToken('missing', 'background'), isFalse);
    });

    test('copyWith replaces selected fields', () {
      final theme = makeTheme();
      final copy = theme.copyWith(
        id: 'copy',
        displayName: 'Copy',
        brightness: Brightness.light,
      );
      expect(copy.id, 'copy');
      expect(copy.displayName, 'Copy');
      expect(copy.brightness, Brightness.light);
      expect(copy.color('canvas', 'background'), const Color(0xFF1A1A1A));
    });

    test('copyWith preserves tokens when null', () {
      final theme = makeTheme();
      final copy = theme.copyWith(id: 'copy');
      expect(copy.tokens, equals(theme.tokens));
    });

    test('copyWith replaces tokens when supplied', () {
      final theme = makeTheme();
      final copy = theme.copyWith(
        tokens: {
          'severity': {'error': const Color(0xFFFF0000)},
        },
      );
      expect(copy.hasToken('canvas', 'background'), isFalse);
      expect(copy.color('severity', 'error'), const Color(0xFFFF0000));
    });

    test('mergeTokens layers overrides on top', () {
      final theme = makeTheme();
      final merged = theme.mergeTokens({
        'canvas.background': const Color(0xFF222222),
        'severity.error': const Color(0xFFFF0000),
      });
      expect(merged.color('canvas', 'background'), const Color(0xFF222222));
      expect(merged.color('canvas', 'foreground'), const Color(0xFFE0E0E0));
      expect(merged.color('severity', 'error'), const Color(0xFFFF0000));
    });

    test('mergeTokens returns identical instance when overrides empty', () {
      final theme = makeTheme();
      expect(identical(theme.mergeTokens(const {}), theme), isTrue);
    });

    test('mergeTokens silently ignores malformed dotted ids', () {
      final theme = makeTheme();
      final merged = theme.mergeTokens({
        'nodot': const Color(0xFFFFFFFF),
        '.leading-dot': const Color(0xFFFFFFFF),
        'trailing-dot.': const Color(0xFFFFFFFF),
        'canvas.foreground': const Color(0xFF111111),
      });
      expect(merged.color('canvas', 'foreground'), const Color(0xFF111111));
      expect(merged.tokens['nodot'], isNull);
      expect(merged.tokens[''], isNull);
    });

    test('equality is value-based across token tables', () {
      final a = makeTheme();
      final b = makeTheme();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality detects token differences', () {
      final a = makeTheme();
      final b = makeTheme(
        tokens: {
          'canvas': {
            'background': const Color(0xFF1A1A1A),
            'foreground': const Color(0xFFFF0000),
          },
          'chrome': {
            'scaffold': const Color(0xFF202020),
          },
        },
      );
      expect(a, isNot(equals(b)));
    });

    test('dottedId / splitDottedId round-trip', () {
      const dotted = 'canvas.background';
      expect(CruxColorTheme.dottedId('canvas', 'background'), dotted);
      expect(CruxColorTheme.splitDottedId(dotted), ('canvas', 'background'));
    });

    test('splitDottedId handles dot in token id', () {
      expect(
        CruxColorTheme.splitDottedId('canvas.signal.x.fill'),
        ('canvas', 'signal.x.fill'),
      );
    });

    test('splitDottedId returns null for malformed input', () {
      expect(CruxColorTheme.splitDottedId('nodot'), isNull);
      expect(CruxColorTheme.splitDottedId('.leading'), isNull);
      expect(CruxColorTheme.splitDottedId('trailing.'), isNull);
      expect(CruxColorTheme.splitDottedId(''), isNull);
    });

    test('toString includes id, brightness, and token count', () {
      final theme = makeTheme();
      expect(theme.toString(), contains('test'));
      expect(theme.toString(), contains('dark'));
      expect(theme.toString(), contains('3 tokens'));
    });
  });
}
