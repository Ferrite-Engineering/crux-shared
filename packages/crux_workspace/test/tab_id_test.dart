// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TabId', () {
    test('generate() produces unique ids', () {
      final a = TabId.generate();
      final b = TabId.generate();
      expect(a, isNot(equals(b)));
      expect(a.value, isNot(equals(b.value)));
    });

    test('fromString round-trips', () {
      final original = TabId.generate();
      final restored = TabId.fromString(original.value);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });

    test('equality is value-based', () {
      final a = TabId.fromString('123e4567-e89b-12d3-a456-426614174000');
      final b = TabId.fromString('123e4567-e89b-12d3-a456-426614174000');
      final c = TabId.fromString('00000000-0000-0000-0000-000000000000');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes the value', () {
      final id = TabId.fromString('abc');
      expect(id.toString(), contains('abc'));
    });
  });
}
