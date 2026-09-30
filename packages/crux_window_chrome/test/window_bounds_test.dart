// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowBounds JSON', () {
    test('round-trips a full snapshot', () {
      const bounds = WindowBounds(
        left: 100,
        top: 50,
        width: 1400,
        height: 900,
      );
      final restored = WindowBounds.fromJson(bounds.toJson());
      expect(restored, bounds);
    });

    test('omits null position fields and the default maximized flag', () {
      const bounds = WindowBounds(width: 1280, height: 720);
      expect(bounds.toJson(), {'width': 1280.0, 'height': 720.0});
      expect(bounds.hasPosition, isFalse);
    });

    test('round-trips the maximized flag', () {
      const bounds = WindowBounds(
        left: 0,
        top: 0,
        width: 1920,
        height: 1080,
        maximized: true,
      );
      final restored = WindowBounds.fromJson(bounds.toJson());
      expect(restored?.maximized, isTrue);
    });

    test('returns null for a missing or non-positive size', () {
      expect(WindowBounds.fromJson(const {}), isNull);
      expect(WindowBounds.fromJson(const {'width': 0, 'height': 600}), isNull);
      expect(
        WindowBounds.fromJson(const {'width': -5, 'height': 600}),
        isNull,
      );
      expect(
        WindowBounds.fromJson(const {'width': 800, 'height': 'tall'}),
        isNull,
      );
    });

    test('drops non-finite size/position values', () {
      expect(
        WindowBounds.fromJson({'width': double.infinity, 'height': 600}),
        isNull,
      );
      final b = WindowBounds.fromJson({
        'width': 1000,
        'height': 700,
        'left': double.nan,
        'top': 10,
      });
      expect(b, isNotNull);
      expect(b!.left, isNull);
      expect(b.top, 10);
    });
  });

  group('sanitizedForRestore', () {
    test('floors size to the minimum window dimensions', () {
      const tiny = WindowBounds(left: 10, top: 10, width: 200, height: 100);
      final s = tiny.sanitizedForRestore();
      expect(s, isNotNull);
      expect(s!.width, 800);
      expect(s.height, 500);
      // A sane position survives untouched.
      expect(s.left, 10);
      expect(s.top, 10);
    });

    test('keeps a valid in-range geometry as-is', () {
      const ok = WindowBounds(left: 300, top: 120, width: 1400, height: 900);
      expect(ok.sanitizedForRestore(), ok);
    });

    test('drops a wildly off-screen position but keeps the size', () {
      const offScreen = WindowBounds(
        left: -4000,
        top: 30,
        width: 1280,
        height: 720,
      );
      final s = offScreen.sanitizedForRestore();
      expect(s, isNotNull);
      expect(s!.hasPosition, isFalse, reason: 'off-screen x dropped');
      expect(s.width, 1280);
      expect(s.height, 720);
    });

    test('drops a negative top (window above the desktop) position', () {
      const offTop = WindowBounds(
        left: 100,
        top: -2000,
        width: 1280,
        height: 720,
      );
      expect(offTop.sanitizedForRestore()!.hasPosition, isFalse);
    });

    test('tolerates a slightly negative left (grabbable title bar)', () {
      const nudged = WindowBounds(
        left: -20,
        top: 0,
        width: 1280,
        height: 720,
      );
      expect(nudged.sanitizedForRestore()!.left, -20);
    });

    test('caps an absurd size', () {
      const absurd = WindowBounds(width: 999999, height: 999999);
      final s = absurd.sanitizedForRestore(maxExtent: 5000)!;
      expect(s.width, 5000);
      expect(s.height, 5000);
    });

    test('preserves the maximized flag through sanitization', () {
      const maxed = WindowBounds(
        left: 0,
        top: 0,
        width: 1920,
        height: 1080,
        maximized: true,
      );
      expect(maxed.sanitizedForRestore()!.maximized, isTrue);
    });
  });

  test('copyWith replaces only the supplied fields', () {
    const base = WindowBounds(left: 10, top: 20, width: 800, height: 600);
    expect(base.copyWith(width: 1000).width, 1000);
    expect(base.copyWith(width: 1000).left, 10);
    expect(base.copyWith(maximized: true).maximized, isTrue);
  });

  test('equality and hashCode are value-based', () {
    const a = WindowBounds(left: 1, top: 2, width: 800, height: 600);
    const b = WindowBounds(left: 1, top: 2, width: 800, height: 600);
    const c = WindowBounds(left: 9, top: 2, width: 800, height: 600);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
