// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui';

import 'package:crux_theme/src/crux_focus_ring_borders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ring = BorderSide(color: Color(0xFF00AAFF), width: 2);
const _other = BorderSide(color: Color(0xFFFF0000), width: 4);
const _side = BorderSide(color: Color(0xFF123456));
const _radius = BorderRadius.all(Radius.circular(6));
const _rect = Rect.fromLTWH(10, 10, 100, 40);

/// Paints [draw] onto a recording canvas and returns the picture, so a test
/// can tell a painted frame from a skipped one by its size.
int _recordedBytes(void Function(Canvas) draw) {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final bytes = picture.approximateBytesUsed;
  picture.dispose();
  return bytes;
}

void main() {
  group('paintCruxFocusRing', () {
    final control = _radius.toRRect(_rect);

    test('strokes the ring', () {
      final painted = _recordedBytes(
        (canvas) => paintCruxFocusRing(canvas, control, _ring, 2),
      );
      final empty = _recordedBytes((_) {});
      expect(painted, greaterThan(empty));
    });

    test('draws nothing for a none-style or zero-width ring', () {
      final empty = _recordedBytes((_) {});
      for (final ring in [
        BorderSide.none,
        const BorderSide(width: 0),
        const BorderSide(style: BorderStyle.none),
      ]) {
        expect(
          _recordedBytes((c) => paintCruxFocusRing(c, control, ring, 2)),
          empty,
        );
      }
    });
  });

  group('CruxFocusRingShape', () {
    const shape = CruxFocusRingShape(
      ring: _ring,
      side: _side,
      borderRadius: _radius,
      gap: 3,
    );

    test('paints its outline and the ring', () {
      final plain = _recordedBytes(
        (c) => const RoundedRectangleBorder(
          side: _side,
          borderRadius: _radius,
        ).paint(c, _rect),
      );
      final ringed = _recordedBytes((c) => shape.paint(c, _rect));
      expect(ringed, greaterThan(plain));
    });

    test('copyWith keeps the ring and gap and swaps side / radius', () {
      final copy = shape.copyWith(
        side: _other,
        borderRadius: BorderRadius.zero,
      );
      expect(copy.ring, _ring);
      expect(copy.gap, 3);
      expect(copy.side, _other);
      expect(copy.borderRadius, BorderRadius.zero);
      expect(shape.copyWith(), shape);
    });

    test('scale multiplies every dimension', () {
      final scaled = shape.scale(2) as CruxFocusRingShape;
      expect(scaled.gap, 6);
      expect(scaled.ring.width, 4);
      expect(scaled.side.width, _side.width * 2);
      expect(scaled.borderRadius, _radius * 2);
    });

    test('lerps between two ring shapes', () {
      const to = CruxFocusRingShape(
        ring: _other,
        side: _side,
        borderRadius: _radius,
        gap: 5,
      );
      final mid = shape.lerpTo(to, 0.5)! as CruxFocusRingShape;
      expect(mid.gap, 4);
      expect(mid.ring.width, 3);
      expect(to.lerpFrom(shape, 0.5), mid);
    });

    test('switches, rather than fades, against a ring-less shape', () {
      const plain = RoundedRectangleBorder();
      expect(shape.lerpFrom(plain, 0.25), plain);
      expect(shape.lerpFrom(plain, 0.75), shape);
      expect(shape.lerpTo(plain, 0.25), shape);
      expect(shape.lerpTo(plain, 0.75), plain);
      expect(shape.lerpFrom(null, 0.25), isNull);
    });

    test('equality and hash cover every field', () {
      const same = CruxFocusRingShape(
        ring: _ring,
        side: _side,
        borderRadius: _radius,
        gap: 3,
      );
      expect(shape, same);
      expect(shape.hashCode, same.hashCode);
      expect(
        shape,
        isNot(
          const CruxFocusRingShape(
            ring: _other,
            side: _side,
            borderRadius: _radius,
            gap: 3,
          ),
        ),
      );
      expect(
        shape,
        isNot(
          const CruxFocusRingShape(
            ring: _ring,
            side: _side,
            borderRadius: _radius,
            gap: 4,
          ),
        ),
      );
      expect(shape, isNot(const RoundedRectangleBorder()));
    });
  });

  group('CruxFocusRingInputBorder', () {
    const border = CruxFocusRingInputBorder(
      ring: _ring,
      borderSide: _side,
      borderRadius: _radius,
      gap: 3,
    );

    test('paints its outline and the ring', () {
      final plain = _recordedBytes(
        (c) => const OutlineInputBorder(
          borderSide: _side,
          borderRadius: _radius,
        ).paint(c, _rect),
      );
      final ringed = _recordedBytes((c) => border.paint(c, _rect));
      expect(ringed, greaterThan(plain));
    });

    test('paints around a floating label gap', () {
      expect(
        () => _recordedBytes(
          (c) => border.paint(
            c,
            _rect,
            gapStart: 12,
            gapExtent: 30,
            gapPercentage: 1,
            textDirection: TextDirection.ltr,
          ),
        ),
        returnsNormally,
      );
    });

    test('copyWith keeps the ring and gap', () {
      final copy = border.copyWith(
        borderSide: _other,
        borderRadius: BorderRadius.zero,
        gapPadding: 9,
      );
      expect(copy.ring, _ring);
      expect(copy.gap, 3);
      expect(copy.borderSide, _other);
      expect(copy.borderRadius, BorderRadius.zero);
      expect(copy.gapPadding, 9);
      expect(border.copyWith(), border);
    });

    test('scale multiplies every dimension', () {
      final scaled = border.scale(2);
      expect(scaled.gap, 6);
      expect(scaled.ring.width, 4);
      expect(scaled.gapPadding, 8);
      expect(scaled.borderRadius, _radius * 2);
    });

    test('lerps between two ring borders', () {
      const to = CruxFocusRingInputBorder(
        ring: _other,
        borderSide: _side,
        borderRadius: _radius,
        gapPadding: 8,
        gap: 5,
      );
      final mid = border.lerpTo(to, 0.5)! as CruxFocusRingInputBorder;
      expect(mid.gap, 4);
      expect(mid.gapPadding, 6);
      expect(mid.ring.width, 3);
    });

    test('switches, rather than fades, against a ring-less border', () {
      const plain = OutlineInputBorder();
      expect(border.lerpFrom(plain, 0.25), plain);
      expect(border.lerpFrom(plain, 0.75), border);
      expect(border.lerpTo(plain, 0.25), border);
      expect(border.lerpTo(plain, 0.75), plain);
    });

    test('equality and hash cover every field', () {
      const same = CruxFocusRingInputBorder(
        ring: _ring,
        borderSide: _side,
        borderRadius: _radius,
        gap: 3,
      );
      expect(border, same);
      expect(border.hashCode, same.hashCode);
      expect(border, isNot(border.copyWith(gapPadding: 5)));
      expect(border, isNot(const OutlineInputBorder()));
    });
  });
}
