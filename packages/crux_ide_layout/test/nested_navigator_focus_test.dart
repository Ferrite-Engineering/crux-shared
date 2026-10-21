// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Lost focus and cruxFocusIsInPushedRoute around a nested navigator, the
// shape of a tab's own navigator (crux_workspace's CruxTabNavigatorHost):
// its page does not take focus, so the navigator's own node or the page's
// route scope can end up holding focus, and both announce nothing.

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final GlobalKey<NavigatorState> _nested = GlobalKey<NavigatorState>();

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

/// A start button that, activated, is replaced by a nested navigator whose
/// page holds a Run button and does not request focus.
Widget _app() {
  var opened = false;
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => CruxFocusRegionScope(
          restoreLostFocus: true,
          child: Column(
            children: <Widget>[
              CruxFocusRegion(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('Settings'),
                ),
              ),
              Expanded(
                child: CruxFocusRegion(
                  primary: true,
                  child: opened
                      ? Navigator(
                          key: _nested,
                          onGenerateInitialRoutes: (_, _) => <Route<void>>[
                            PageRouteBuilder<void>(
                              requestFocus: false,
                              pageBuilder: (_, _, _) => Column(
                                children: <Widget>[
                                  OutlinedButton(
                                    onPressed: () {},
                                    child: const Text('Run'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () {},
                                    child: const Text('Stop'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : FilledButton(
                          autofocus: true,
                          onPressed: () => setState(() => opened = true),
                          child: const Text('Open Config'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(_app());
  await tester.pumpAndSettle();
  expect(_focusedText(), 'Open Config');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void _pushDialog(Widget child) {
  final navigator = _nested.currentState!;
  navigator.push<void>(
    DialogRoute<void>(
      context: navigator.context,
      builder: (_) => Dialog(child: child),
    ),
  );
}

void main() {
  group('lost focus around a nested navigator', () {
    testWidgets('a page that does not take focus leaves the navigator '
        'holding it; the primary region claims it', (tester) async {
      await _open(tester);
      // Without the restore, focus rests on the nested navigator's own
      // node, which no screen reader announces.
      expect(_focusedText(), 'Run');
    });

    testWidgets("focus resting on the nested navigator's own node is lost "
        'focus, put back where it was', (tester) async {
      await _open(tester);
      Focus.of(tester.element(find.text('Stop'))).requestFocus();
      await tester.pump();
      // The node a Navigator autofocuses when its page takes no focus: no
      // semantics, so a screen reader hears nothing while it holds focus.
      _nested.currentState!.focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_focusedText(), 'Stop');
    });

    testWidgets('focus resting on the route scope of a dialog on the nested '
        'navigator is left there', (tester) async {
      await _open(tester);
      // A dialog with nothing focusable: focus moves onto its route scope,
      // and must stay inside the dialog.
      _pushDialog(const Text('Busy'));
      await tester.pumpAndSettle();

      expect(_focusedText(), isNot('Run'));
      expect(cruxFocusIsInPushedRoute(), isTrue);
    });

    testWidgets('closing a dialog on the nested navigator returns focus to '
        'the control that had it, not to one in the dialog', (tester) async {
      await _open(tester);
      Focus.of(tester.element(find.text('Stop'))).requestFocus();
      await tester.pump();
      _pushDialog(
        TextButton(
          autofocus: true,
          onPressed: () => _nested.currentState!.pop(),
          child: const Text('OK'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedText(), 'OK');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsNothing);
      expect(_focusedText(), 'Stop');
    });
  });

  group('cruxFocusIsInPushedRoute', () {
    testWidgets('false with nothing focused', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(cruxFocusIsInPushedRoute(FocusNode()), isFalse);
    });

    testWidgets('false on a first page, nested or not', (tester) async {
      await _open(tester);
      expect(_focusedText(), 'Run');
      expect(cruxFocusIsInPushedRoute(), isFalse);
      Focus.of(tester.element(find.text('Settings'))).requestFocus();
      await tester.pump();
      expect(cruxFocusIsInPushedRoute(), isFalse);
    });

    testWidgets('true in a dialog on the root navigator', (tester) async {
      await _open(tester);
      unawaited(
        showDialog<void>(
          context: tester.element(find.text('Settings')),
          builder: (_) => Dialog(
            child: TextButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Close'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedText(), 'Close');
      expect(cruxFocusIsInPushedRoute(), isTrue);
    });

    testWidgets('true in a dialog on the nested navigator', (tester) async {
      await _open(tester);
      _pushDialog(
        TextButton(
          autofocus: true,
          onPressed: () {},
          child: const Text('Close'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedText(), 'Close');
      expect(cruxFocusIsInPushedRoute(), isTrue);
      // The page behind it is still a first page.
      final run = Focus.of(tester.element(find.text('Run')));
      expect(cruxFocusIsInPushedRoute(run), isFalse);
    });

    testWidgets('true in a navigator nested inside a pushed route', (
      tester,
    ) async {
      await _open(tester);
      _pushDialog(
        SizedBox(
          width: 200,
          height: 100,
          child: Navigator(
            onGenerateInitialRoutes: (_, _) => <Route<void>>[
              PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => TextButton(
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Inner'),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedText(), 'Inner');
      expect(cruxFocusIsInPushedRoute(), isTrue);
    });
  });
}
