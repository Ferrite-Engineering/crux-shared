// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<CruxPressState> states;
  late int presses;

  Widget host({bool enabled = true}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: CruxPressable(
          semanticLabel: 'Run',
          onPressed: enabled ? () => presses++ : null,
          builder: (context, state) {
            states.add(state);
            return CruxFocusRing(
              focused: state.focused,
              child: const SizedBox(width: 60, height: 28, child: Text('Run')),
            );
          },
        ),
      ),
    ),
  );

  setUp(() {
    states = <CruxPressState>[];
    presses = 0;
  });

  testWidgets('a click presses it; pressed shows between down and up', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Run')),
    );
    await tester.pump();
    expect(states.last.pressed, isTrue);
    await gesture.up();
    await tester.pump();
    expect(states.last.pressed, isFalse);
    expect(presses, 1);
  });

  testWidgets('Space and Enter press it; keyboard focus shows, a click does '
      'not', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(states.last.focused, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(states.last.focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 3);
  });

  testWidgets('disabled: no press, no focus', (tester) async {
    await tester.pumpWidget(host(enabled: false));
    await tester.tap(find.text('Run'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(presses, 0);
    expect(states.last.enabled, isFalse);
    expect(states.last.focused, isFalse);
  });

  testWidgets('one button node named by its label; the text is not read '
      'twice', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    expect(
      tester.getSemantics(find.byType(CruxPressable)),
      matchesSemantics(
        label: 'Run',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  test('the ring is 2 px outside the control, or 2 px inside when inset', () {
    const outside = CruxFocusRingPainter(
      color: Colors.blue,
      radius: 4,
      width: 1.5,
    );
    const size = Size(60, 28);
    final out = outside.ringFor(size);
    // The stroke's inner edge sits 2 px from the control.
    expect(out.outerRect.deflate(0.75), const Rect.fromLTRB(-2, -2, 62, 30));
    expect(out.tlRadiusX, 4 + 2.75);
    const inside = CruxFocusRingPainter(
      color: Colors.blue,
      radius: 4,
      width: 1.5,
      inset: true,
    );
    final inner = inside.ringFor(size);
    expect(inner.outerRect.inflate(0.75), const Rect.fromLTRB(2, 2, 58, 26));
  });

  testWidgets('the ring is 1.5 px, 2.5 px in high contrast', (tester) async {
    double? width;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            width = cruxFocusRingWidth(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(width, 1.5);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(width, 2.5);
  });
}
