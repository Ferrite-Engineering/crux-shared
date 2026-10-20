// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int undone;

  setUp(() => undone = 0);

  Widget host({bool desktop = true}) => MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[
        if (desktop) const CruxDesktopTokens(),
      ],
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showCruxInfoSnack(
              context,
              'Bookmark removed.',
              action: CruxToastAction(label: 'Undo', onPressed: () => undone++),
            ),
            child: const Text('Remove'),
          ),
        ),
      ),
    ),
  );

  testWidgets('the action is a button; choosing it runs it and closes the '
      'toast', (tester) async {
    final announced = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove'));
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);
    expect(announced.messages, contains('Bookmark removed. Undo'));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, 1);
    expect(find.text('Bookmark removed.'), findsNothing);
  });

  testWidgets('an info toast with an action stays past four seconds and '
      'leaves at eight', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Bookmark removed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Bookmark removed.'), findsNothing);
    expect(undone, 0);
  });

  testWidgets('it never leaves while hovered or focused, and counts again '
      'from the start once released', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove'));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Bookmark removed.')));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Bookmark removed.'), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Bookmark removed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Bookmark removed.'), findsNothing);

    // Focus holds it the same way.
    await tester.tap(find.text('Remove'));
    await tester.pump();
    final undo = find.byKey(const ValueKey('cruxToastAction'));
    Focus.of(tester.element(find.text('Undo'))).requestFocus();
    await tester.pump(const Duration(seconds: 20));
    expect(undo, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(undone, 1);
    expect(undo, findsNothing);
  });

  testWidgets('the keyboard reaches the action, named with the message', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.tap(find.text('Remove'));
    await tester.pump();
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_toast_action.txt');
    handle.dispose();
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('on phone and tablet it is a SnackBarAction', (tester) async {
    await tester.pumpWidget(host(desktop: false));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.action?.label, 'Undo');
    expect(bar.duration, kCruxActionSnackDuration);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
  });

  testWidgets('on phone and tablet an info snack bar with an action leaves '
      'after its duration', (tester) async {
    await tester.pumpWidget(host(desktop: false));
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Bookmark removed.'), findsOneWidget);
    await tester.pump(kCruxActionSnackDuration);
    await tester.pumpAndSettle();
    expect(find.text('Bookmark removed.'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(undone, 0);
  });

  testWidgets('on phone and tablet the action still works before the '
      'duration ends', (tester) async {
    await tester.pumpWidget(host(desktop: false));
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Bookmark removed.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, 1);
    expect(find.text('Bookmark removed.'), findsNothing);
  });

  testWidgets('on phone and tablet an error snack bar with an action leaves '
      'after its duration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCruxErrorSnack(
                context,
                'Export failed.',
                action: CruxToastAction(label: 'Retry', onPressed: () {}),
              ),
              child: const Text('Export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Export failed.'), findsOneWidget);
    await tester.pump(kCruxActionSnackDuration);
    await tester.pumpAndSettle();
    expect(find.text('Export failed.'), findsNothing);
  });

  testWidgets('an error toast can carry an action beside its close button', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCruxErrorSnack(
                context,
                'Export failed.',
                action: CruxToastAction(
                  label: 'Retry',
                  onPressed: () => retried++,
                ),
              ),
              child: const Text('Export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const ValueKey('cruxToastClose')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retried, 1);
    expect(find.text('Export failed.'), findsNothing);
  });
}
