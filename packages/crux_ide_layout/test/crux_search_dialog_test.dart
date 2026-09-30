// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<String> Function(String query) search,
  required ValueChanged<String> onActivate,
  Widget Function(BuildContext, VoidCallback refresh)? headerBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CruxSearchDialog<String>(
                  title: 'Search',
                  hintText: 'Type to search',
                  emptyLabel: 'No matches',
                  search: search,
                  headerBuilder: headerBuilder,
                  fieldKey: const ValueKey('searchField'),
                  rowBuilder:
                      (
                        context,
                        result, {
                        required highlighted,
                        required onActivate,
                      }) => CruxSearchResultTile(
                        title: result,
                        highlighted: highlighted,
                        onTap: onActivate,
                      ),
                  onActivateResult: onActivate,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('searchField')), text);
  // Let the keystroke debounce elapse.
  await tester.pump(kCruxSearchDebounceInterval * 2);
}

void main() {
  testWidgets('debounced search renders result rows', (tester) async {
    final queries = <String>[];
    await _pumpDialog(
      tester,
      search: (q) {
        queries.add(q);
        return ['alpha', 'beta'];
      },
      onActivate: (_) {},
    );
    await tester.enterText(find.byKey(const ValueKey('searchField')), 'a');
    // Before the debounce elapses no search has run.
    expect(queries, isEmpty);
    await tester.pump(kCruxSearchDebounceInterval * 2);
    expect(queries, ['a']);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('non-empty query with no results shows the empty label', (
    tester,
  ) async {
    await _pumpDialog(tester, search: (_) => [], onActivate: (_) {});
    expect(find.text('No matches'), findsNothing);
    await _type(tester, 'zzz');
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('arrow keys move the highlight and Enter activates the row', (
    tester,
  ) async {
    String? activated;
    await _pumpDialog(
      tester,
      search: (_) => ['alpha', 'beta', 'gamma'],
      onActivate: (r) => activated = r,
    );
    await _type(tester, 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(activated, 'beta');
    // Activation pops the dialog.
    expect(find.byType(CruxSearchDialog<String>), findsNothing);
  });

  testWidgets('Enter with a pending debounce runs the search, not a stale '
      'activation', (tester) async {
    String? activated;
    await _pumpDialog(
      tester,
      search: (q) => q == 'fresh' ? ['fresh-hit'] : ['stale-hit'],
      onActivate: (r) => activated = r,
    );
    await _type(tester, 'stale');
    expect(find.text('stale-hit'), findsOneWidget);
    // Type again but do NOT wait out the debounce; Enter must search.
    await tester.enterText(find.byKey(const ValueKey('searchField')), 'fresh');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, isNull);
    expect(find.text('fresh-hit'), findsOneWidget);
  });

  testWidgets('header refresh re-runs the search immediately', (tester) async {
    var mode = 'one';
    await _pumpDialog(
      tester,
      search: (q) => ['$q-$mode'],
      onActivate: (_) {},
      headerBuilder: (context, refresh) => TextButton(
        onPressed: () {
          mode = 'two';
          refresh();
        },
        child: const Text('toggle'),
      ),
    );
    await _type(tester, 'q');
    expect(find.text('q-one'), findsOneWidget);
    await tester.tap(find.text('toggle'));
    await tester.pump();
    expect(find.text('q-two'), findsOneWidget);
  });

  testWidgets('tapping a row activates it and pops', (tester) async {
    String? activated;
    await _pumpDialog(
      tester,
      search: (_) => ['alpha', 'beta'],
      onActivate: (r) => activated = r,
    );
    await _type(tester, 'a');
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(activated, 'beta');
    expect(find.byType(CruxSearchDialog<String>), findsNothing);
  });
}
