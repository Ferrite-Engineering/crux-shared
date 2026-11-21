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

  group('fittedToDisplays', () {
    // The checks every fitted result must pass: the whole window lies on one
    // work area, in physical pixels.
    void expectOnScreen(
      WindowBounds fitted,
      DisplayWorkArea area, {
      double windowScale = 1,
    }) {
      const slack = 1e-9;
      final s = area.scaleFactor;
      final l = fitted.left! * windowScale;
      final t = fitted.top! * windowScale;
      expect(l, greaterThanOrEqualTo(area.left * s - slack));
      expect(t, greaterThanOrEqualTo(area.top * s - slack));
      expect(
        l + fitted.width * s,
        lessThanOrEqualTo((area.left + area.width) * s + slack),
      );
      expect(
        t + fitted.height * s,
        lessThanOrEqualTo((area.top + area.height) * s + slack),
      );
    }

    test('fits the window that opened 2894 px wide on a 2880 px work area '
        'at 175%', () {
      // The physical geometry seen on Windows, (-29, 85) to (2865, 1582),
      // as window_manager reports it: logical pixels at the window's 1.75.
      const scale = 1.75;
      const saved = WindowBounds(
        left: -29 / scale,
        top: 85 / scale,
        width: 2894 / scale,
        height: 1497 / scale,
      );
      // 2880 x 1800 display, 84 px taskbar, as screen_retriever reports it.
      const area = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2880 / scale,
        height: 1716 / scale,
        scaleFactor: scale,
        primary: true,
      );
      final fitted = saved.fittedToDisplays([area], windowScale: scale)!;
      expect(fitted.width, closeTo(2880 / scale, 1e-9));
      expect(fitted.height, closeTo(1497 / scale, 1e-9));
      expect(fitted.left, closeTo(0, 1e-9));
      expect(fitted.top, closeTo(85 / scale, 1e-9));
      expectOnScreen(fitted, area, windowScale: scale);
    });

    test('leaves a window that already fits untouched', () {
      const area = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        primary: true,
      );
      const saved = WindowBounds(left: 200, top: 100, width: 1280, height: 720);
      expect(saved.fittedToDisplays([area]), saved);
    });

    test('keeps a window on a secondary display with a negative origin', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2560,
        height: 1400,
        primary: true,
      );
      const left = DisplayWorkArea(
        left: -1920,
        top: -200,
        width: 1920,
        height: 1040,
      );
      const saved = WindowBounds(
        left: -1800,
        top: -150,
        width: 1000,
        height: 700,
      );
      final fitted = saved.fittedToDisplays([primary, left])!;
      expect(fitted, saved);
      expectOnScreen(fitted, left);
    });

    test('pulls a window hanging off a negative-origin display back on', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2560,
        height: 1400,
        primary: true,
      );
      const left = DisplayWorkArea(
        left: -1920,
        top: 0,
        width: 1920,
        height: 1040,
      );
      // Mostly on the left display, its left edge 100 px past that
      // display's own left edge.
      const saved = WindowBounds(
        left: -2020,
        top: 20,
        width: 1200,
        height: 700,
      );
      final fitted = saved.fittedToDisplays([primary, left])!;
      expect(fitted.left, -1920);
      expect(fitted.top, 20);
      expectOnScreen(fitted, left);
    });

    test('moves a window straddling two displays onto the one it overlaps '
        'most', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2560,
        height: 1400,
        primary: true,
      );
      const left = DisplayWorkArea(
        left: -1920,
        top: 0,
        width: 1920,
        height: 1040,
      );
      const saved = WindowBounds(
        left: -300,
        top: 100,
        width: 1000,
        height: 700,
      );
      final fitted = saved.fittedToDisplays([primary, left])!;
      expect(fitted.left, 0);
      expect(fitted.top, 100);
      expectOnScreen(fitted, primary);
    });

    test('centres on the primary display when the saved display is gone', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        primary: true,
      );
      const saved = WindowBounds(
        left: 4000,
        top: 200,
        width: 1280,
        height: 720,
      );
      final fitted = saved.fittedToDisplays([primary])!;
      expect(fitted.left, (1920 - 1280) / 2);
      expect(fitted.top, (1040 - 720) / 2);
      expect(fitted.width, 1280);
      expectOnScreen(fitted, primary);
    });

    test('centres on the display flagged primary, not the first listed', () {
      const other = DisplayWorkArea(
        left: -1920,
        top: 0,
        width: 1920,
        height: 1040,
      );
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2560,
        height: 1400,
        primary: true,
      );
      const saved = WindowBounds(width: 1280, height: 720);
      final fitted = saved.fittedToDisplays([other, primary])!;
      expect(fitted.left, (2560 - 1280) / 2);
      expect(fitted.top, (1400 - 720) / 2);
    });

    test('a window with no position is sized to fit and centred', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 30,
        width: 1366,
        height: 738,
        primary: true,
      );
      const saved = WindowBounds(width: 2560, height: 1400);
      final fitted = saved.fittedToDisplays([primary])!;
      expect(fitted.width, 1366);
      expect(fitted.height, 738);
      expect(fitted.left, 0);
      expect(fitted.top, 30);
    });

    test('compares displays of different scales in physical pixels', () {
      // Windows: a 3840 x 2160 primary at 150% and a 1920 x 1080 display
      // at 100% to its right, each reported in its own logical pixels.
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2560,
        height: 1400,
        scaleFactor: 1.5,
        primary: true,
      );
      const right = DisplayWorkArea(
        left: 3840,
        top: 0,
        width: 1920,
        height: 1040,
      );
      // Saved while on the primary (window scale 1.5): physical x 3600 to
      // 5400, mostly on the right-hand display.
      const saved = WindowBounds(
        left: 2400,
        top: 100,
        width: 1200,
        height: 800,
      );
      final fitted = saved.fittedToDisplays([
        primary,
        right,
      ], windowScale: 1.5)!;
      // Physical x 3840 is the right display's edge: 2560 at scale 1.5.
      expect(fitted.left, closeTo(2560, 1e-9));
      expect(fitted.top, closeTo(100, 1e-9));
      expect(fitted.width, 1200);
      expect(fitted.height, 800);
      expectOnScreen(fitted, right, windowScale: 1.5);
    });

    test('shrinks to a high-scale display measured in its own logical '
        'pixels', () {
      // A 2560 x 1600 laptop panel at 200% next to a 100% monitor.
      const laptop = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 1280,
        height: 760,
        scaleFactor: 2,
        primary: true,
      );
      const monitor = DisplayWorkArea(
        left: 2560,
        top: 0,
        width: 2560,
        height: 1400,
      );
      const saved = WindowBounds(left: 10, top: 10, width: 1600, height: 900);
      final fitted = saved.fittedToDisplays([laptop, monitor], windowScale: 2)!;
      expect(fitted.width, 1280);
      expect(fitted.height, 760);
      expect(fitted.left, 0);
      expect(fitted.top, 0);
      expectOnScreen(fitted, laptop, windowScale: 2);
    });

    test('centres in physical pixels when the window and display scales '
        'differ', () {
      const primary = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 2000,
        height: 1000,
        scaleFactor: 2,
        primary: true,
      );
      const saved = WindowBounds(width: 1000, height: 600);
      final fitted = saved.fittedToDisplays([primary], windowScale: 1.25)!;
      // Physical: work area 4000 x 2000, window 2000 x 1200.
      expect(fitted.left! * 1.25, closeTo(1000, 1e-9));
      expect(fitted.top! * 1.25, closeTo(400, 1e-9));
      expectOnScreen(fitted, primary, windowScale: 1.25);
    });

    test('floors to the minimum size but never past the work area', () {
      const small = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 731,
        height: 411,
        scaleFactor: 1.75,
        primary: true,
      );
      const saved = WindowBounds(left: 0, top: 0, width: 200, height: 100);
      final fitted = saved.fittedToDisplays([small], windowScale: 1.75)!;
      expect(fitted.width, 731);
      expect(fitted.height, 411);
    });

    test('keeps maximized and still fits the restore rectangle', () {
      const area = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        primary: true,
      );
      const saved = WindowBounds(
        left: -8,
        top: -8,
        width: 1936,
        height: 1056,
        maximized: true,
      );
      final fitted = saved.fittedToDisplays([area])!;
      expect(fitted.maximized, isTrue);
      expectOnScreen(fitted, area);
    });

    test('falls back to sanitizedForRestore without usable displays', () {
      const saved = WindowBounds(left: -4000, top: 30, width: 200, height: 100);
      expect(saved.fittedToDisplays(const []), saved.sanitizedForRestore());
      expect(
        saved.fittedToDisplays(const [
          DisplayWorkArea(left: 0, top: 0, width: 0, height: 1040),
          DisplayWorkArea(left: double.nan, top: 0, width: 800, height: 600),
        ]),
        saved.sanitizedForRestore(),
      );
    });

    test('ignores a degenerate display beside a real one', () {
      const real = DisplayWorkArea(left: 0, top: 0, width: 1920, height: 1040);
      const saved = WindowBounds(width: 1280, height: 720);
      final fitted = saved.fittedToDisplays([
        const DisplayWorkArea(left: 0, top: 0, width: -1, height: 1040),
        real,
      ])!;
      expectOnScreen(fitted, real);
    });

    test('treats a non-positive scale as 1', () {
      const area = DisplayWorkArea(
        left: 0,
        top: 0,
        width: 1920,
        height: 1040,
        scaleFactor: 0,
        primary: true,
      );
      const saved = WindowBounds(left: 1500, top: 900, width: 800, height: 500);
      final fitted = saved.fittedToDisplays([area], windowScale: -2)!;
      expect(fitted.left, 1120);
      expect(fitted.top, 540);
    });

    test('every result lands on one display, across a sweep', () {
      const displays = [
        DisplayWorkArea(
          left: 0,
          top: 0,
          width: 1645.7142857142858,
          height: 980.5714285714286,
          scaleFactor: 1.75,
          primary: true,
        ),
        DisplayWorkArea(
          left: -2560,
          top: -300,
          width: 2560,
          height: 1400,
        ),
        DisplayWorkArea(
          left: 1920,
          top: 400,
          width: 1280,
          height: 760,
          scaleFactor: 2,
        ),
      ];
      for (final x in <double>[-6000, -2600, -400, 0, 900, 1700, 2400, 9000]) {
        for (final y in <double>[-900, -310, 0, 500, 1300, 5000]) {
          for (final size in [
            (200.0, 100.0),
            (1280.0, 720.0),
            (4000.0, 3000.0),
          ]) {
            final saved = WindowBounds(
              left: x,
              top: y,
              width: size.$1,
              height: size.$2,
            );
            final fitted = saved.fittedToDisplays(
              displays,
              windowScale: 1.75,
            )!;
            final onOne = displays.any((area) {
              final s = area.scaleFactor;
              final l = fitted.left! * 1.75;
              final t = fitted.top! * 1.75;
              const slack = 1e-6;
              return l >= area.left * s - slack &&
                  t >= area.top * s - slack &&
                  l + fitted.width * s <=
                      (area.left + area.width) * s + slack &&
                  t + fitted.height * s <= (area.top + area.height) * s + slack;
            });
            expect(onOne, isTrue, reason: '$saved fitted to $fitted');
          }
        }
      }
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
