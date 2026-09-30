// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ThemePack makePack({
    String id = 'pack',
    String displayName = 'Pack',
    Brightness brightness = Brightness.dark,
    Uri? sourceUri,
    Map<String, Map<String, Color>>? tokens,
  }) {
    return ThemePack(
      id: id,
      displayName: displayName,
      brightness: brightness,
      sourceUri: sourceUri,
      tokens:
          tokens ??
          {
            'canvas': {'background': const Color(0xFF1A1A1A)},
          },
    );
  }

  group('ThemePack', () {
    test('stores all fields', () {
      final uri = Uri.parse('file:///themes/pack.crux-theme.json');
      final pack = makePack(sourceUri: uri);
      expect(pack.id, 'pack');
      expect(pack.displayName, 'Pack');
      expect(pack.brightness, Brightness.dark);
      expect(pack.sourceUri, uri);
      expect(pack.color('canvas', 'background'), const Color(0xFF1A1A1A));
    });

    test('color returns null when token absent', () {
      final pack = makePack();
      expect(pack.color('chrome', 'background'), isNull);
    });

    test('token map is unmodifiable', () {
      final pack = makePack();
      expect(
        () => pack.tokens['canvas'] = {'foo': const Color(0xFFFFFFFF)},
        throwsUnsupportedError,
      );
    });

    test('toTheme produces equivalent CruxColorTheme', () {
      final pack = makePack();
      final theme = pack.toTheme();
      expect(theme.id, pack.id);
      expect(theme.displayName, pack.displayName);
      expect(theme.brightness, pack.brightness);
      expect(theme.color('canvas', 'background'), const Color(0xFF1A1A1A));
    });

    test('toHeader produces a small summary', () {
      final uri = Uri.parse('file:///themes/pack.crux-theme.json');
      final pack = makePack(sourceUri: uri);
      final header = pack.toHeader();
      expect(header.id, pack.id);
      expect(header.displayName, pack.displayName);
      expect(header.brightness, pack.brightness);
      expect(header.sourceUri, uri);
    });

    test('copyWith replaces selected fields', () {
      final pack = makePack();
      final copy = pack.copyWith(id: 'other', displayName: 'Other');
      expect(copy.id, 'other');
      expect(copy.displayName, 'Other');
      expect(copy.brightness, pack.brightness);
    });

    test('equality is value-based', () {
      final a = makePack();
      final b = makePack();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equality detects sourceUri differences', () {
      final a = makePack(sourceUri: Uri.parse('file:///a'));
      final b = makePack(sourceUri: Uri.parse('file:///b'));
      expect(a, isNot(equals(b)));
    });
  });

  group('ThemePackHeader', () {
    test('stores all fields', () {
      const header = ThemePackHeader(
        id: 'pack',
        displayName: 'Pack',
        brightness: Brightness.dark,
      );
      expect(header.id, 'pack');
      expect(header.displayName, 'Pack');
      expect(header.brightness, Brightness.dark);
      expect(header.sourceUri, isNull);
    });

    test('equality is value-based', () {
      const a = ThemePackHeader(
        id: 'pack',
        displayName: 'Pack',
        brightness: Brightness.dark,
      );
      const b = ThemePackHeader(
        id: 'pack',
        displayName: 'Pack',
        brightness: Brightness.dark,
      );
      const different = ThemePackHeader(
        id: 'pack',
        displayName: 'Pack',
        brightness: Brightness.light,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(different)));
    });
  });

  group('ThemePackValidation', () {
    test('ok wraps a pack and is valid', () {
      final pack = ThemePack(
        id: 'p',
        displayName: 'P',
        brightness: Brightness.dark,
        tokens: const {},
      );
      final result = ThemePackValidation.ok(pack);
      expect(result.isValid, isTrue);
      expect(result.pack, pack);
      expect(result.errors, isEmpty);
    });

    test('failed wraps errors and is invalid', () {
      final result = ThemePackValidation.failed(
        const ['missing id', 'unknown schema version'],
      );
      expect(result.isValid, isFalse);
      expect(result.pack, isNull);
      expect(result.errors, ['missing id', 'unknown schema version']);
    });

    test('failed errors list is unmodifiable', () {
      final result = ThemePackValidation.failed(const ['oops']);
      expect(() => result.errors.add('more'), throwsUnsupportedError);
    });
  });
}
