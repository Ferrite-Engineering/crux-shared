// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaneId', () {
    test('generate() produces unique ids', () {
      final a = PaneId.generate();
      final b = PaneId.generate();
      expect(a, isNot(equals(b)));
    });

    test('fromString round-trips', () {
      final original = PaneId.generate();
      final restored = PaneId.fromString(original.value);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });

    test('equality is value-based', () {
      final a = PaneId.fromString('aaa');
      final b = PaneId.fromString('aaa');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('primary sentinel is stable across calls', () {
      expect(PaneId.primary, equals(PaneId.primary));
      expect(
        PaneId.primary.value,
        equals('00000000-0000-0000-0000-000000000001'),
      );
    });

    test('toString includes the value', () {
      final id = PaneId.fromString('abc');
      expect(id.toString(), contains('abc'));
    });
  });
}
