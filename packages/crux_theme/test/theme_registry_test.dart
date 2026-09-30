// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const canvas = ThemeTokenCategory(
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
        id: 'foreground',
        displayName: 'Foreground',
        lightDefault: Color(0xFF111111),
        darkDefault: Color(0xFFEEEEEE),
      ),
    ],
  );

  const severity = ThemeTokenCategory(
    id: 'severity',
    displayName: 'Severity',
    tokens: [
      ThemeTokenDescriptor(
        id: 'error',
        displayName: 'Error',
        lightDefault: Color(0xFFFF0000),
        darkDefault: Color(0xFFFF5555),
      ),
    ],
  );

  setUp(ThemeRegistry.instance.resetForTesting);

  tearDown(ThemeRegistry.instance.resetForTesting);

  group('registerCategory', () {
    test('records a category', () {
      ThemeRegistry.instance.registerCategory(canvas);
      expect(ThemeRegistry.instance.hasCategory('canvas'), isTrue);
      expect(ThemeRegistry.instance.category('canvas'), canvas);
    });

    test('re-registering an IDENTICAL category is a no-op', () {
      // The registry is process-wide but product startup is not: a
      // second window, a re-run of bootstrap() in the same isolate, or
      // a widget test that boots the app twice all re-register the same
      // catalog. Throwing there crashed the app for no reason.
      ThemeRegistry.instance
        ..registerCategory(canvas)
        ..registerCategory(canvas);
      expect(ThemeRegistry.instance.registeredCategories.length, 1);
      expect(ThemeRegistry.instance.category('canvas'), canvas);
    });

    test('re-registering an equal-but-not-identical instance is also a '
        'no-op', () {
      ThemeRegistry.instance.registerCategory(canvas);
      const twin = ThemeTokenCategory(
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
            id: 'foreground',
            displayName: 'Foreground',
            lightDefault: Color(0xFF111111),
            darkDefault: Color(0xFFEEEEEE),
          ),
        ],
      );
      expect(twin, canvas, reason: 'test fixture must match the original');
      expect(
        () => ThemeRegistry.instance.registerCategory(twin),
        returnsNormally,
      );
      expect(ThemeRegistry.instance.registeredCategories.length, 1);
    });

    test('a CONFLICTING duplicate id still throws loudly', () {
      // Two products claiming one category id is a genuine programming
      // error, and silently keeping one would make the Settings editor
      // disagree with the renderer.
      ThemeRegistry.instance.registerCategory(canvas);
      expect(
        () => ThemeRegistry.instance.registerCategory(
          const ThemeTokenCategory(
            id: 'canvas',
            displayName: 'A different canvas',
            tokens: [
              ThemeTokenDescriptor(
                id: 'different',
                displayName: 'Different',
                lightDefault: Color(0xFFFFFFFF),
                darkDefault: Color(0xFF000000),
              ),
            ],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects empty ids', () {
      const bad = ThemeTokenCategory(
        id: '',
        displayName: 'Empty',
        tokens: [
          ThemeTokenDescriptor(
            id: 'x',
            displayName: 'X',
            lightDefault: Color(0xFF000000),
            darkDefault: Color(0xFFFFFFFF),
          ),
        ],
      );
      expect(
        () => ThemeRegistry.instance.registerCategory(bad),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('registeredCategories', () {
    test('returns categories in registration order', () {
      ThemeRegistry.instance.registerCategory(canvas);
      ThemeRegistry.instance.registerCategory(severity);
      final list = ThemeRegistry.instance.registeredCategories;
      expect(list.length, 2);
      expect(list.first.id, 'canvas');
      expect(list.last.id, 'severity');
    });

    test('is unmodifiable', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final list = ThemeRegistry.instance.registeredCategories;
      expect(() => list.add(severity), throwsUnsupportedError);
    });
  });

  group('allRegisteredTokens', () {
    test('flattens to dotted ids', () {
      ThemeRegistry.instance.registerCategory(canvas);
      ThemeRegistry.instance.registerCategory(severity);
      final flat = ThemeRegistry.instance.allRegisteredTokens;
      expect(flat.keys.toSet(), {
        'canvas.background',
        'canvas.foreground',
        'severity.error',
      });
      expect(flat['canvas.background']!.lightDefault, const Color(0xFFFFFFFF));
    });

    test('is unmodifiable', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final flat = ThemeRegistry.instance.allRegisteredTokens;
      expect(
        () => flat['x'] = const ThemeTokenDescriptor(
          id: 'x',
          displayName: 'X',
          lightDefault: Color(0xFF000000),
          darkDefault: Color(0xFFFFFFFF),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('resolve', () {
    test('returns explicit theme value when present', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final theme = CruxColorTheme(
        id: 't',
        displayName: 'T',
        brightness: Brightness.dark,
        tokens: const {
          'canvas': {'background': Color(0xFF111111)},
        },
      );
      expect(
        ThemeRegistry.instance.resolve(theme, 'canvas', 'background'),
        const Color(0xFF111111),
      );
    });

    test('falls back to dark default when theme omits and dark', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final theme = CruxColorTheme(
        id: 't',
        displayName: 'T',
        brightness: Brightness.dark,
        tokens: const {},
      );
      expect(
        ThemeRegistry.instance.resolve(theme, 'canvas', 'background'),
        const Color(0xFF000000),
      );
    });

    test('falls back to light default when theme omits and light', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final theme = CruxColorTheme(
        id: 't',
        displayName: 'T',
        brightness: Brightness.light,
        tokens: const {},
      );
      expect(
        ThemeRegistry.instance.resolve(theme, 'canvas', 'background'),
        const Color(0xFFFFFFFF),
      );
    });

    test('returns null when neither theme nor registry knows the token', () {
      ThemeRegistry.instance.registerCategory(canvas);
      final theme = CruxColorTheme(
        id: 't',
        displayName: 'T',
        brightness: Brightness.dark,
        tokens: const {},
      );
      expect(
        ThemeRegistry.instance.resolve(theme, 'unknown', 'token'),
        isNull,
      );
    });
  });

  group('merge', () {
    test('applies overrides on top of base', () {
      // Built-in presets no longer carry a canvas palette, so
      // this states its own base rather than borrowing a preset's.
      final base = CruxColorTheme(
        id: 'base',
        displayName: 'Base',
        brightness: Brightness.dark,
        tokens: const {
          'canvas': {
            'background': Color(0xFF1A1A1A),
            'cursor.primary': Color(0xFFFFFF00),
          },
        },
      );
      final merged = ThemeRegistry.merge(
        base,
        {'canvas.background': const Color(0xFFFF0000)},
      );
      expect(merged.color('canvas', 'background'), const Color(0xFFFF0000));
      expect(
        merged.color('canvas', 'cursor.primary'),
        base.color('canvas', 'cursor.primary'),
      );
    });

    test('is a no-op for empty override map', () {
      final base = builtinPresets()['crux-dark']!;
      final merged = ThemeRegistry.merge(base, const {});
      expect(identical(merged, base), isTrue);
    });
  });
}
