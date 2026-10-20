// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({this.enabled = true});

  final bool enabled;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool value = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: CruxSwitch(
          value: value,
          semanticLabel: 'Auto-reload',
          onChanged: widget.enabled ? (v) => setState(() => value = v) : null,
        ),
      ),
    ),
  );
}

bool _value(WidgetTester tester) =>
    tester.widget<CruxSwitch>(find.byType(CruxSwitch)).value;

void main() {
  testWidgets('the track is 32 x 18 with a 14 px thumb', (tester) async {
    await tester.pumpWidget(const _Host());
    final track = find.descendant(
      of: find.byType(CruxSwitch),
      matching: find.byWidgetPredicate(
        (w) =>
            w is AnimatedContainer &&
            w.constraints ==
                const BoxConstraints.tightFor(
                  width: kCruxSwitchTrackWidth,
                  height: kCruxSwitchTrackHeight,
                ),
      ),
    );
    expect(tester.getSize(track), const Size(32, 18));
    final thumb = find.descendant(
      of: track,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints ==
                const BoxConstraints.tightFor(
                  width: kCruxSwitchThumbSize,
                  height: kCruxSwitchThumbSize,
                ),
      ),
    );
    expect(tester.getSize(thumb), const Size(14, 14));
  });

  testWidgets('it is drawn at size, never a scaled Material switch', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    expect(
      find.descendant(
        of: find.byType(CruxSwitch),
        matching: find.byType(Switch),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(CruxSwitch),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('a click toggles it', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.byType(CruxSwitch));
    await tester.pump();
    expect(_value(tester), isTrue);
  });

  testWidgets('Space and Enter toggle it', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(_value(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_value(tester), isFalse);
  });

  testWidgets('a screen reader hears its label and toggled state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    expect(
      tester.getSemantics(find.byType(CruxSwitch)),
      matchesSemantics(
        label: 'Auto-reload',
        hasToggledState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.byType(CruxSwitch));
    await tester.pump();
    expect(
      tester.getSemantics(find.byType(CruxSwitch)),
      matchesSemantics(
        label: 'Auto-reload',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('keyboard focus draws a 1.5 px ring, 2.5 px in high contrast', (
    tester,
  ) async {
    Border? ring() {
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(CruxSwitch),
          matching: find.byType(DecoratedBox),
        ),
      );
      for (final box in boxes) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration && decoration.color == null) {
          return decoration.border as Border?;
        }
      }
      return null;
    }

    await tester.pumpWidget(const _Host());
    expect(ring()!.top.color, Colors.transparent);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring()!.top.width, 1.5);
    expect(ring()!.top.color, isNot(Colors.transparent));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(ring()!.top.width, 2.5);
  });

  testWidgets('a disabled switch ignores clicks and keys', (tester) async {
    await tester.pumpWidget(const _Host(enabled: false));
    await tester.tap(find.byType(CruxSwitch));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(_value(tester), isFalse);
  });

  testWidgets('the focus walk names it as a switch', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(walk.stops.single.line, contains('Auto-reload'));
    handle.dispose();
  });
}
