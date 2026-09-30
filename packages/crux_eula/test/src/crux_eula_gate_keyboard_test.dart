// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The agreement on a first launch, as a keyboard and a screen reader meet it.
//
// Before, it was stacked over the app with nothing but a barrier: focus
// stayed on the app behind it, Tab walked controls the user could not see
// (each one silent, because the barrier blocks their semantics), nothing
// ever landed inside the dialog, and Enter could press a hidden button.
//
// The transcript in goldens/eula_gate.txt is what NVDA reads, one Tab at a
// time; `flutter test --update-goldens` rewrites it, and the diff is the
// review.
//
// MUTATION: dropping the ExcludeFocus from CruxModalGate turns "nothing
// behind the agreement can be reached" red; dropping the agreement text's
// autofocus turns "focus opens on the agreement" red.

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_eula/crux_eula.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

late InMemoryCruxEulaStorage _storage;
late FocusNode _behind;
final List<String> _pressed = <String>[];

Widget _app() {
  return ProviderScope(
    overrides: [
      cruxEulaStorageProvider.overrideWithValue(_storage),
      cruxEulaOnDeclineProvider.overrideWithValue(
        () => _pressed.add('declined'),
      ),
      cruxEulaOpenOnlineProvider.overrideWithValue(
        () async => _pressed.add('opened online'),
      ),
    ],
    child: MaterialApp(
      home: CruxEulaGate(
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
    ),
  );
}

Future<void> _launch(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('cruxEulaDialog')), findsOneWidget);
}

double _documentOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('cruxEulaDocumentScroll')),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .pixels;

void main() {
  setUp(() {
    _storage = InMemoryCruxEulaStorage();
    _behind = FocusNode(debugLabel: 'behind');
    _pressed.clear();
  });
  tearDown(() => _behind.dispose());

  testWidgets('focus opens on the agreement, inside the named dialog', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    expect(
      describeFocus(tester).line,
      '[End User License Agreement grouping] Agreement text grouping',
    );
    expect(
      tester.getSemantics(find.byType(CruxModalSurface)),
      matchesSemantics(
        label: 'End User License Agreement',
        scopesRoute: true,
        namesRoute: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('Tab walks the agreement and never the app behind it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.transcript, isNot(contains(' design button')));
    expectFocusWalkGolden(walk, 'test/src/goldens/eula_gate.txt');

    final back = await walkFocus(tester, reverse: true);
    expectCleanFocusWalk(back);
    expect(back.transcript, isNot(contains(' design button')));
    handle.dispose();
  });

  testWidgets('nothing behind the agreement can be reached', (tester) async {
    await _launch(tester);

    // The app behind grabbing focus once it has loaded, as a canvas or a
    // palette does, after the agreement is already up.
    _behind.requestFocus();
    await tester.pump();
    expect(_behind.hasFocus, isFalse);

    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }
    expect(_pressed, isNot(contains('behind: open')));
    expect(find.byKey(const Key('cruxEulaDialog')), findsOneWidget);
  });

  testWidgets('the agreement scrolls from the keyboard', (tester) async {
    await _launch(tester);
    expect(_documentOffset(tester), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(_documentOffset(tester), greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    final end = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('cruxEulaDocumentScroll')),
            matching: find.byType(Scrollable),
          ),
        )
        .position
        .maxScrollExtent;
    expect(_documentOffset(tester), end);
  });

  testWidgets('Escape does not dismiss it', (tester) async {
    await _launch(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cruxEulaDialog')), findsOneWidget);
    expect(_storage.values[kCruxEulaAcceptedVersionKey], isNull);
  });

  testWidgets('it is accepted with the keyboard alone, and focus moves to '
      'the app', (tester) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    Future<String> tabTo(String name) async {
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final stop = describeFocus(tester);
        if (stop.name.contains(name)) return stop.line;
      }
      fail('Tab never reached "$name"');
    }

    // Accept is disabled until the box is ticked, so it is not a Tab stop yet
    // (the walk golden shows the order without it).
    await tabTo('I have read and accept');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(describeFocus(tester).states, contains('checked'));

    expect(await tabTo('Accept'), endsWith('Accept button'));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cruxEulaDialog')), findsNothing);
    expect(_storage.values[kCruxEulaAcceptedVersionKey], kCruxEulaVersion);
    expectFocusAnnounced(tester, named: 'Open design');
    handle.dispose();
  });

  testWidgets('Decline is reachable and pressed from the keyboard', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _launch(tester);

    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (describeFocus(tester).name == 'Decline and quit') break;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_pressed, <String>['declined']);
    handle.dispose();
  });
}
