// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _region({required bool empty, String message = 'Nothing to show.'}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            TextButton(onPressed: () {}, child: const Text('Before')),
            CruxRegionHintHost(
              builder: (context, hint, child) => cruxRegionHintSemantics(
                label: 'Details dock',
                hint: hint,
                explicitChildNodes: true,
                child: child,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(onPressed: () {}, child: const Text('Refresh')),
                  if (empty)
                    CruxRegionHint(hint: message, child: Text(message)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

SemanticsData _regionData(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsLabel('Details dock'))
    .getSemanticsData();

void main() {
  testWidgets('a mounted hint describes the region and keeps its name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_region(empty: true));
    await tester.pump();

    final data = _regionData(tester);
    expect(data.label, 'Details dock');
    expect(data.hint, 'Nothing to show.');
    // The desktop bridge drops the hint and reads the tooltip as the
    // description, so both carry it.
    expect(data.tooltip, 'Nothing to show.');
    // The visible message keeps its own node for browse mode.
    expect(find.bySemanticsLabel('Nothing to show.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the hint goes when the source unmounts, and follows changes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_region(empty: true));
    await tester.pump();
    await tester.pumpWidget(_region(empty: true, message: 'Run a test.'));
    await tester.pump();
    expect(_regionData(tester).hint, 'Run a test.');

    await tester.pumpWidget(_region(empty: false));
    await tester.pump();
    final data = _regionData(tester);
    expect(data.label, 'Details dock');
    expect(data.hint, isEmpty);
    expect(data.tooltip, isEmpty);
    handle.dispose();
  });

  testWidgets('the focus walk announces the description on entry', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_region(empty: true));
    await tester.pump();

    final walk = await walkFocus(tester);
    final refresh = walk.stops.firstWhere((s) => s.name == 'Refresh');
    expect(refresh.entered, <String>[
      'Details dock grouping — Nothing to show.',
    ]);
    expect(
      refresh.line,
      '[Details dock grouping — Nothing to show.] '
      'Refresh button',
    );
    expectCleanFocusWalk(walk);
    handle.dispose();
  });

  testWidgets('a hint with no host is inert', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CruxRegionHint(hint: 'Alone', child: Text('Alone')),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Alone'), findsOneWidget);
  });
}
