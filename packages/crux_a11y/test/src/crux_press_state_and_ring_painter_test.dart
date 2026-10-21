// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:crux_a11y/crux_a11y.dart';
import 'package:flutter_test/flutter_test.dart';

int _recordedBytes(void Function(Canvas) draw) {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final bytes = picture.approximateBytesUsed;
  picture.dispose();
  return bytes;
}

void main() {
  group('CruxPressState', () {
    test('defaults to idle and enabled', () {
      const state = CruxPressState();
      expect(state.pressed, isFalse);
      expect(state.hovered, isFalse);
      expect(state.focused, isFalse);
      expect(state.enabled, isTrue);
    });

    test('equality and hash cover every field', () {
      const base = CruxPressState(pressed: true, focused: true);
      expect(base, const CruxPressState(pressed: true, focused: true));
      expect(
        base.hashCode,
        const CruxPressState(pressed: true, focused: true).hashCode,
      );
      expect(base, isNot(const CruxPressState(focused: true)));
      expect(
        base,
        isNot(
          const CruxPressState(pressed: true, focused: true, hovered: true),
        ),
      );
      expect(
        base,
        isNot(
          const CruxPressState(pressed: true, focused: true, enabled: false),
        ),
      );
      expect(base, isNot(const CruxPressState(pressed: true)));
    });

    test('toString names every field', () {
      expect(
        const CruxPressState(hovered: true).toString(),
        'CruxPressState(pressed: false, hovered: true, '
        'focused: false, enabled: true)',
      );
    });
  });

  group('CruxFocusRingPainter', () {
    const painter = CruxFocusRingPainter(
      color: Color(0xFF00AAFF),
      radius: 6,
      width: 2,
    );

    test('ringFor grows outside the control by gap plus half the width', () {
      final ring = painter.ringFor(const Size(100, 40));
      expect(ring.outerRect, const Rect.fromLTWH(-3, -3, 106, 46));
      expect(ring.tlRadius.x, 9);
    });

    test('ringFor insets inside the control and keeps a minimum radius', () {
      const inset = CruxFocusRingPainter(
        color: Color(0xFF00AAFF),
        radius: 6,
        width: 2,
        inset: true,
      );
      final ring = inset.ringFor(const Size(100, 40));
      expect(ring.outerRect, const Rect.fromLTWH(3, 3, 94, 34));
      expect(ring.tlRadius.x, 3);

      const square = CruxFocusRingPainter(
        color: Color(0xFF00AAFF),
        radius: 0,
        width: 2,
        inset: true,
      );
      expect(square.ringFor(const Size(100, 40)).tlRadius.x, 2);
    });

    test('paint strokes the ring', () {
      final painted = _recordedBytes(
        (c) => painter.paint(c, const Size(100, 40)),
      );
      expect(painted, greaterThan(_recordedBytes((_) {})));
    });

    test('repaints only when a field changes', () {
      bool repaint(CruxFocusRingPainter other) => painter.shouldRepaint(other);
      expect(
        repaint(
          const CruxFocusRingPainter(
            color: Color(0xFF00AAFF),
            radius: 6,
            width: 2,
          ),
        ),
        isFalse,
      );
      const color = Color(0xFFFF0000);
      expect(
        repaint(
          const CruxFocusRingPainter(color: color, radius: 6, width: 2),
        ),
        isTrue,
      );
      expect(
        repaint(
          const CruxFocusRingPainter(
            color: Color(0xFF00AAFF),
            radius: 7,
            width: 2,
          ),
        ),
        isTrue,
      );
      expect(
        repaint(
          const CruxFocusRingPainter(
            color: Color(0xFF00AAFF),
            radius: 6,
            width: 3,
          ),
        ),
        isTrue,
      );
      expect(
        repaint(
          const CruxFocusRingPainter(
            color: Color(0xFF00AAFF),
            radius: 6,
            width: 2,
            gap: 4,
          ),
        ),
        isTrue,
      );
      expect(
        repaint(
          const CruxFocusRingPainter(
            color: Color(0xFF00AAFF),
            radius: 6,
            width: 2,
            inset: true,
          ),
        ),
        isTrue,
      );
    });
  });
}
