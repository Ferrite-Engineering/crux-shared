// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The beta-expired modal as a keyboard and a screen reader meet it.
//
// Each product's own copy stacked the dialog over the app with nothing but a
// barrier: focus stayed on the app behind it, Tab walked controls nobody
// could see, and Enter could press one of them.
//
// MUTATION: rendering the modal in a plain Stack instead of CruxModalGate
// turns "nothing behind it can be reached" red; dropping the download
// action's autofocus turns "focus opens on the download action" red.

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

late FocusNode _behind;
final List<String> _pressed = <String>[];

Widget _app({bool blocking = true}) => MaterialApp(
  home: CruxBetaExpiredOverlay(
    blocking: blocking,
    onDownload: () => _pressed.add('download'),
    onQuit: () => _pressed.add('quit'),
    child: Scaffold(
      body: Column(
        children: [
          ElevatedButton(
            focusNode: _behind,
            autofocus: true,
            onPressed: () => _pressed.add('behind: open'),
            child: const Text('Open design'),
          ),
          ElevatedButton(
            onPressed: () => _pressed.add('behind: save'),
            child: const Text('Save design'),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  expect(find.byKey(CruxBetaExpiredOverlay.dialogKey), findsOneWidget);
}

void main() {
  const strings = CruxBetaExpiredStringsEn();

  setUp(() {
    _behind = FocusNode(debugLabel: 'behind');
    _pressed.clear();
  });
  tearDown(() => _behind.dispose());

  testWidgets('focus opens on the download action, inside the named dialog', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    expectFocusAnnounced(tester, named: strings.downloadLabel);
    expect(
      tester.getSemantics(find.byType(CruxModalSurface)),
      matchesSemantics(
        label: strings.title,
        scopesRoute: true,
        namesRoute: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Tab walks the dialog and never the app behind it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(walk.transcript, contains(strings.downloadLabel));
    expect(walk.transcript, contains(strings.quitLabel));
    expect(walk.transcript, isNot(contains(' design button')));

    final back = await walkFocus(tester, reverse: true);
    expectCleanFocusWalk(back);
    expect(back.transcript, isNot(contains(' design button')));
    handle.dispose();
  });

  testWidgets('nothing behind it can be reached', (tester) async {
    await _launch(tester);

    _behind.requestFocus();
    await tester.pump();
    expect(_behind.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_behind.hasFocus, isFalse);
    expect(_pressed, isNot(contains('behind: open')));
  });

  testWidgets('Escape does not dismiss it', (tester) async {
    await _launch(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(CruxBetaExpiredOverlay.dialogKey), findsOneWidget);
  });

  testWidgets('both actions are pressed from the keyboard alone', (
    tester,
  ) async {
    await _launch(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_pressed, <String>['download']);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_pressed, <String>['download', 'quit']);
  });

  testWidgets('not blocking renders the app untouched and reachable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(blocking: false));
    await tester.pumpAndSettle();

    expect(find.byKey(CruxBetaExpiredOverlay.dialogKey), findsNothing);
    expect(_behind.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_pressed, <String>['behind: open']);
  });
}
