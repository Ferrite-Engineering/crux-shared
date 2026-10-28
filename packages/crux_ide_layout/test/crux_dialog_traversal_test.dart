// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final GlobalKey<NavigatorState> _root = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _tab = GlobalKey<NavigatorState>();

/// The products' shape: `MaterialApp.router`, a strip above the routed
/// content in `MaterialApp.builder`, and a page holding a tab's own nested
/// navigator.
class _Delegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  GlobalKey<NavigatorState> get navigatorKey => _root;

  @override
  Widget build(BuildContext context) => Navigator(
    key: _root,
    pages: <Page<void>>[
      MaterialPage<void>(
        child: Scaffold(
          body: Column(
            children: <Widget>[
              ElevatedButton(onPressed: () {}, child: const Text('Page')),
              // A semantics boundary, as crux_workspace's tab host draws
              // one, so the tab page's barrier does not hide the button
              // above it.
              Expanded(
                child: CruxRoutedContent(
                  child: Navigator(
                    key: _tab,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => ElevatedButton(
                        onPressed: () {},
                        child: const Text('Tab content'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
    onDidRemovePage: (_) {},
  );

  @override
  Future<void> setNewRoutePath(Object configuration) async {}
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerDelegate: _Delegate(),
      builder: (context, child) => Column(
        children: <Widget>[
          Material(
            child: TextButton(onPressed: () {}, child: const Text('Strip')),
          ),
          Expanded(child: CruxRoutedContent(child: child)),
        ],
      ),
    ),
  );
}

Widget _dialog(BuildContext context) => CruxDialog(
  title: 'Rename',
  content: const TextField(decoration: InputDecoration(labelText: 'Name')),
  actions: <Widget>[
    CruxDialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(),
    ),
    CruxDialogAction(
      label: 'Rename',
      role: CruxDialogActionRole.primary,
      onPressed: () => Navigator.of(context).pop(),
    ),
  ],
);

List<String> _names(FocusWalk walk) =>
    walk.stops.map((stop) => stop.name).toList();

void main() {
  testWidgets('the page hands Tab on to the strip above the Navigator', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(_names(walk).toSet(), <String>{'Page', 'Tab content', 'Strip'});
    handle.dispose();
  });

  for (final nested in <bool>[false, true]) {
    final where = nested ? "a tab's navigator" : 'the root navigator';
    testWidgets('a dialog on $where keeps Tab inside itself', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      final context = (nested ? _tab : _root).currentContext!;
      final result = showCruxDialog<void>(
        context: context,
        navigator: nested ? _tab.currentState : null,
        barrierDismissible: false,
        builder: _dialog,
      );
      await tester.pumpAndSettle();

      final walk = await walkFocus(tester);
      expect(walk.cycled, isTrue, reason: walk.transcript);
      expect(_names(walk), isNot(contains('Strip')), reason: walk.transcript);
      expect(_names(walk), isNot(contains('Page')), reason: walk.transcript);
      expect(_names(walk), contains('Cancel'), reason: walk.transcript);

      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await result;
      handle.dispose();
    });
  }
}
