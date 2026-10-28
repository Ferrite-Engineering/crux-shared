// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A router with one page holding two buttons, the second opening a dialog
/// on the root navigator. The shape every product has: `MaterialApp.router`,
/// with the strips in `MaterialApp.builder` around the routed content.
class _Delegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    pages: <Page<void>>[
      MaterialPage<void>(
        child: Scaffold(
          body: Column(
            children: <Widget>[
              ElevatedButton(onPressed: () {}, child: const Text('Page one')),
              ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: navigatorKey.currentContext!,
                  builder: (_) => AlertDialog(
                    title: const Text('Confirm'),
                    actions: <Widget>[
                      TextButton(onPressed: () {}, child: const Text('Cancel')),
                      TextButton(onPressed: () {}, child: const Text('OK')),
                    ],
                  ),
                ),
                child: const Text('Open dialog'),
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

/// A notice strip as the products draw them above the `Navigator`.
class _Strip extends StatelessWidget {
  const _Strip();

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Row(
        children: <Widget>[
          const Expanded(child: Text('An update is available.')),
          TextButton(onPressed: () {}, child: const Text('Update now')),
          TextButton(onPressed: () {}, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, {required bool wrapped}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerDelegate: _Delegate(),
      builder: (context, child) => Column(
        children: <Widget>[
          const _Strip(),
          Expanded(
            child: wrapped
                ? CruxRoutedContent(child: child)
                : child ?? const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}

List<String> _names(FocusWalk walk) =>
    walk.stops.map((stop) => stop.name).toList();

void main() {
  testWidgets('Tab runs from the page through the strip and back', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, wrapped: true);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(_names(walk), <String>[
      'Page one',
      'Open dialog',
      'Update now',
      'Dismiss',
    ]);

    final back = await walkFocus(tester, reverse: true);
    expectCleanFocusWalk(back);
    expect(_names(back).toSet(), _names(walk).toSet());
    handle.dispose();
  });

  testWidgets('without the boundary the strip is silent', (tester) async {
    // Pins the defect the widget exists for: the page route's modal barrier
    // blocks the semantics of everything painted before it in the window's
    // container, so Tab reaches the strip's buttons and a screen reader
    // hears nothing. If this starts passing cleanly, the framework stopped
    // doing that and the widget can go.
    final handle = tester.ensureSemantics();
    await _pump(tester, wrapped: false);

    final walk = await walkFocus(tester);
    expect(walk.stops, hasLength(4));
    expect(
      walk.problems().map((problem) => problem.rule),
      contains(FocusWalkRule.silentStop),
    );
    handle.dispose();
  });

  testWidgets('a dialog keeps Tab inside itself', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, wrapped: true);
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(_names(walk), <String>['Cancel', 'OK']);
    handle.dispose();
  });
}
