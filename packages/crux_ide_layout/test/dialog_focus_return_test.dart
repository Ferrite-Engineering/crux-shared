// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Closing a dialog opened with showCruxDialog leaves keyboard focus somewhere
// a window-level shortcut can hear it, and puts it back where it was.

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final GlobalKey<NavigatorState> _nested = GlobalKey<NavigatorState>();

/// The chord the window-level shortcut answers to, standing in for an app's
/// Toggle Theme.
const SingleActivator _chord = SingleActivator(
  LogicalKeyboardKey.keyK,
  control: true,
);

String? _focusedText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final widget = e.widget;
    if (widget is Text) {
      found = widget.data;
      return;
    }
    e.visitChildren(visit);
  }

  visit(context as Element);
  return found;
}

/// An app whose shortcuts sit above the navigator, as the products' do, with
/// two text fields and a nested navigator holding a Run button.
class _Harness {
  int chords = 0;
  bool showFirstField = true;
  final FocusNode firstNode = FocusNode(debugLabel: 'first field');
  late StateSetter rebuild;

  Widget app() => MaterialApp(
    builder: (context, child) => CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{_chord: () => chords++},
      child: child!,
    ),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return Column(
            children: <Widget>[
              if (showFirstField)
                TextField(
                  key: const Key('first'),
                  focusNode: firstNode,
                ),
              const TextField(key: Key('second')),
              Expanded(
                child: Navigator(
                  key: _nested,
                  onGenerateInitialRoutes: (_, _) => <Route<void>>[
                    PageRouteBuilder<void>(
                      requestFocus: false,
                      pageBuilder: (_, _, _) => Center(
                        child: TextButton(
                          onPressed: () {},
                          child: const Text('Run'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> _pressChord(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Walks focus up to the window root, what a platform can leave behind while a
/// modal is up.
Future<void> _dropFocusToRoot(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }
  expect(FocusManager.instance.primaryFocus, FocusManager.instance.rootScope);
}

Widget _dialogBody({
  required String title,
  VoidCallback? onClose,
  bool autofocusClose = false,
}) => Builder(
  builder: (context) => CruxDialog(
    title: title,
    content: Text('$title body'),
    actions: <Widget>[
      CruxDialogAction(
        label: 'Close $title',
        autofocus: autofocusClose,
        onPressed: () {
          Navigator.of(context).pop();
          onClose?.call();
        },
      ),
    ],
  ),
);

void main() {
  late _Harness harness;

  Future<void> boot(WidgetTester tester) async {
    harness = _Harness();
    addTearDown(harness.firstNode.dispose);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  BuildContext pageContext(WidgetTester tester) =>
      tester.element(find.byKey(const Key('second')));

  Future<FocusNode?> focusField(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    return focus;
  }

  group('a dialog on the root navigator', () {
    testWidgets('Escape returns focus to the control that held it', (
      tester,
    ) async {
      await boot(tester);
      final before = await focusField(tester, const Key('second'));

      unawaited(
        showCruxDialog<void>(
          context: pageContext(tester),
          builder: (_) => _dialogBody(title: 'One'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('One body'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(before));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('One body'), findsNothing);
      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('a window-level chord still fires after focus dropped to the '
        'window root and the scrim closed the dialog', (tester) async {
      await boot(tester);
      await focusField(tester, const Key('second'));
      await _pressChord(tester);
      expect(harness.chords, 1, reason: 'the chord works before any dialog');

      unawaited(
        showCruxDialog<void>(
          context: pageContext(tester),
          builder: (_) => _dialogBody(title: 'One'),
        ),
      );
      await tester.pumpAndSettle();
      await _dropFocusToRoot(tester);
      // The scrim needs no focused node to close the dialog.
      await tester.tapAt(const Offset(2, 590));
      await tester.pumpAndSettle();
      expect(find.text('One body'), findsNothing);

      await _pressChord(tester);
      expect(
        harness.chords,
        2,
        reason: 'focus must be under the navigator again',
      );
    });

    testWidgets('focus goes back to the control that held it, not the root, '
        'when the scrim closes the dialog', (tester) async {
      await boot(tester);
      final before = await focusField(tester, const Key('second'));

      unawaited(
        showCruxDialog<void>(
          context: pageContext(tester),
          builder: (_) => _dialogBody(title: 'One'),
        ),
      );
      await tester.pumpAndSettle();
      await _dropFocusToRoot(tester);
      await tester.tapAt(const Offset(2, 590));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('a control that left the tree while the dialog was open: '
        'focus falls back to the navigator, and a chord still fires', (
      tester,
    ) async {
      await boot(tester);
      await focusField(tester, const Key('first'));

      unawaited(
        showCruxDialog<void>(
          context: pageContext(tester),
          builder: (_) => _dialogBody(title: 'One'),
        ),
      );
      await tester.pumpAndSettle();
      harness.rebuild(() => harness.showFirstField = false);
      await tester.pump();
      await _dropFocusToRoot(tester);
      await tester.tapAt(const Offset(2, 590));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus,
        isNot(FocusManager.instance.rootScope),
      );
      await _pressChord(tester);
      expect(harness.chords, 1);
    });

    testWidgets("an action that opened another dialog keeps that dialog's "
        'focus', (tester) async {
      await boot(tester);
      final before = await focusField(tester, const Key('second'));
      final context = pageContext(tester);

      unawaited(
        showCruxDialog<void>(
          context: context,
          builder: (_) => _dialogBody(
            title: 'One',
            onClose: () => unawaited(
              showCruxDialog<void>(
                context: context,
                builder: (_) => _dialogBody(title: 'Two', autofocusClose: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close One'));
      await tester.pumpAndSettle();

      expect(find.text('One body'), findsNothing);
      expect(find.text('Two body'), findsOneWidget);
      expect(_focusedText(), 'Close Two');
      expect(cruxFocusIsInPushedRoute(), isTrue);
      expect(FocusManager.instance.primaryFocus, isNot(before));
    });

    testWidgets('an action that moved focus into the app keeps it there', (
      tester,
    ) async {
      await boot(tester);
      await focusField(tester, const Key('second'));
      final context = pageContext(tester);
      final firstFocus = harness.firstNode;

      unawaited(
        showCruxDialog<void>(
          context: context,
          builder: (_) =>
              _dialogBody(title: 'One', onClose: firstFocus.requestFocus),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close One'));
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, firstFocus);
    });
  });

  group("a dialog on a tab's own navigator", () {
    Future<FocusNode?> focusRun(WidgetTester tester) async {
      await tester.tap(find.text('Run'));
      await tester.pump();
      Focus.of(tester.element(find.text('Run'))).requestFocus();
      await tester.pump();
      return FocusManager.instance.primaryFocus;
    }

    testWidgets('Escape returns focus to the control in the tab that held it', (
      tester,
    ) async {
      await boot(tester);
      final before = await focusRun(tester);
      expect(_focusedText(), 'Run');

      unawaited(
        showCruxDialog<void>(
          context: _nested.currentContext!,
          navigator: _nested.currentState,
          builder: (_) => _dialogBody(title: 'One'),
        ),
      );
      await tester.pumpAndSettle();
      expect(cruxFocusIsInPushedRoute(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('One body'), findsNothing);
      expect(FocusManager.instance.primaryFocus, before);
    });

    testWidgets('an action that opened a dialog on the root navigator keeps '
        "that dialog's focus", (tester) async {
      await boot(tester);
      final before = await focusRun(tester);
      final rootContext = pageContext(tester);

      unawaited(
        showCruxDialog<void>(
          context: _nested.currentContext!,
          navigator: _nested.currentState,
          builder: (_) => _dialogBody(
            title: 'One',
            onClose: () => unawaited(
              showCruxDialog<void>(
                context: rootContext,
                builder: (_) => _dialogBody(title: 'Two', autofocusClose: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close One'));
      await tester.pumpAndSettle();

      expect(find.text('Two body'), findsOneWidget);
      expect(_focusedText(), 'Close Two');
      expect(FocusManager.instance.primaryFocus, isNot(before));
    });
  });
}
