// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A child that repaints on demand, so a test can force extra paints.
class _Repainter extends StatefulWidget {
  const _Repainter({required this.controller});
  final ValueNotifier<int> controller;

  @override
  State<_Repainter> createState() => _RepainterState();
}

class _RepainterState extends State<_Repainter> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: widget.controller,
    builder: (_, value, _) => CustomPaint(
      size: const Size(50, 50),
      painter: _Painter(value),
    ),
  );
}

class _Painter extends CustomPainter {
  _Painter(this.tick);
  final int tick;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint());
  }

  @override
  bool shouldRepaint(_Painter old) => old.tick != tick;
}

void main() {
  testWidgets('reports a paint duration after the frame', (tester) async {
    final samples = <Duration>[];

    await tester.pumpWidget(
      MaterialApp(
        home: CruxPaintTimingProbe(
          onPaintTimed: samples.add,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();

    expect(samples, isNotEmpty);
  });

  testWidgets('coalesces several paints in one frame into one report', (
    tester,
  ) async {
    final samples = <Duration>[];
    final controller = ValueNotifier<int>(0);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CruxPaintTimingProbe(
          onPaintTimed: samples.add,
          child: _Repainter(controller: controller),
        ),
      ),
    );
    await tester.pump();
    final afterFirst = samples.length;

    // Two mutations before the next frame boundary.
    controller
      ..value = 1
      ..value = 2;
    await tester.pump();

    expect(
      samples.length - afterFirst,
      lessThanOrEqualTo(1),
      reason: 'the probe flushes once per frame, not once per paint',
    );
  });

  testWidgets('reports nothing while disabled — measurement nobody looks '
      'at is overhead bought for nothing', (tester) async {
    final samples = <Duration>[];

    await tester.pumpWidget(
      MaterialApp(
        home: CruxPaintTimingProbe(
          enabled: false,
          onPaintTimed: samples.add,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();

    expect(samples, isEmpty);
  });

  testWidgets('starts reporting when re-enabled', (tester) async {
    final samples = <Duration>[];

    Widget build({required bool enabled}) => MaterialApp(
      home: CruxPaintTimingProbe(
        enabled: enabled,
        onPaintTimed: samples.add,
        child: const ColoredBox(
          color: Color(0xFF000000),
          child: SizedBox(width: 50, height: 50),
        ),
      ),
    );

    await tester.pumpWidget(build(enabled: false));
    await tester.pump();
    expect(samples, isEmpty);

    await tester.pumpWidget(build(enabled: true));
    await tester.pump();
    await tester.pump();
    expect(samples, isNotEmpty);
  });

  testWidgets('still paints its child while disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CruxPaintTimingProbe(
          enabled: false,
          onPaintTimed: _noop,
          child: Text('visible', textDirection: TextDirection.ltr),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('visible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not report after the subtree is removed', (tester) async {
    final samples = <Duration>[];

    await tester.pumpWidget(
      MaterialApp(
        home: CruxPaintTimingProbe(
          onPaintTimed: samples.add,
          child: const SizedBox(width: 50, height: 50),
        ),
      ),
    );
    await tester.pump();
    samples.clear();

    // Replace the tree entirely; a detached render object reporting into a
    // disposed container is the crash this guards.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

void _noop(Duration _) {}
