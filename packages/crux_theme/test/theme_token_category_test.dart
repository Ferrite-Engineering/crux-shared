// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeTokenDescriptor', () {
    const descriptor = ThemeTokenDescriptor(
      id: 'background',
      displayName: 'Background',
      lightDefault: Color(0xFFFFFFFF),
      darkDefault: Color(0xFF000000),
      description: 'Canvas background fill',
    );

    test('stores all fields', () {
      expect(descriptor.id, 'background');
      expect(descriptor.displayName, 'Background');
      expect(descriptor.lightDefault, const Color(0xFFFFFFFF));
      expect(descriptor.darkDefault, const Color(0xFF000000));
      expect(descriptor.description, 'Canvas background fill');
    });

    test('defaultFor returns brightness-appropriate color', () {
      expect(descriptor.defaultFor(Brightness.light), const Color(0xFFFFFFFF));
      expect(descriptor.defaultFor(Brightness.dark), const Color(0xFF000000));
    });

    test('equality is value-based', () {
      const a = ThemeTokenDescriptor(
        id: 'background',
        displayName: 'Background',
        lightDefault: Color(0xFFFFFFFF),
        darkDefault: Color(0xFF000000),
        description: 'Canvas background fill',
      );
      const b = ThemeTokenDescriptor(
        id: 'background',
        displayName: 'Background',
        lightDefault: Color(0xFFFFFFFF),
        darkDefault: Color(0xFF000000),
        description: 'Canvas background fill',
      );
      const c = ThemeTokenDescriptor(
        id: 'background',
        displayName: 'Background',
        lightDefault: Color(0xFFFFFFFE),
        darkDefault: Color(0xFF000000),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('description is optional', () {
      const minimal = ThemeTokenDescriptor(
        id: 'x',
        displayName: 'X',
        lightDefault: Color(0xFF000000),
        darkDefault: Color(0xFFFFFFFF),
      );
      expect(minimal.description, isNull);
    });

    test('toString includes id and displayName', () {
      expect(
        descriptor.toString(),
        contains('background'),
      );
      expect(
        descriptor.toString(),
        contains('Background'),
      );
    });
  });

  group('ThemeTokenCategory', () {
    const tokens = [
      ThemeTokenDescriptor(
        id: 'background',
        displayName: 'Background',
        lightDefault: Color(0xFFFFFFFF),
        darkDefault: Color(0xFF000000),
      ),
      ThemeTokenDescriptor(
        id: 'foreground',
        displayName: 'Foreground',
        lightDefault: Color(0xFF000000),
        darkDefault: Color(0xFFFFFFFF),
      ),
    ];

    const category = ThemeTokenCategory(
      id: 'canvas',
      displayName: 'Canvas',
      tokens: tokens,
    );

    test('stores all fields', () {
      expect(category.id, 'canvas');
      expect(category.displayName, 'Canvas');
      expect(category.tokens.length, 2);
    });

    test('descriptor returns matching token by id', () {
      expect(category.descriptor('background'), tokens[0]);
      expect(category.descriptor('foreground'), tokens[1]);
    });

    test('descriptor returns null for unknown tokens', () {
      expect(category.descriptor('nonexistent'), isNull);
    });

    test('equality is value-based', () {
      const a = ThemeTokenCategory(
        id: 'canvas',
        displayName: 'Canvas',
        tokens: tokens,
      );
      const b = ThemeTokenCategory(
        id: 'canvas',
        displayName: 'Canvas',
        tokens: tokens,
      );
      const different = ThemeTokenCategory(
        id: 'chrome',
        displayName: 'Chrome',
        tokens: tokens,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(different)));
    });

    test('toString includes id and token count', () {
      expect(category.toString(), contains('canvas'));
      expect(category.toString(), contains('2 tokens'));
    });
  });
}
