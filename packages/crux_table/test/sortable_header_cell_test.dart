// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_table/crux_table.dart';
import 'package:crux_table/src/table_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  bool sorted = true,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 32,
          child: CruxSortableHeaderCell(
            label: 'Severity',
            onTap: () {},
            sorted: sorted,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  // A squeezed pane lays columns out proportionally, below their drag
  // minimum: LintCrux's 450 px test gives its default sort column 9 px of
  // content. A fixed 18 dp arrow slot overflowed that row by 8.8 px.
  for (final width in <double>[0, 4, 9, 16, 25, 33]) {
    testWidgets('a sorted cell $width px wide does not overflow', (
      tester,
    ) async {
      await _pump(tester, width: width);
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    });
  }

  testWidgets('with room, the label gets everything the arrow does not take', (
    tester,
  ) async {
    await _pump(tester, width: 120);
    expect(tester.takeException(), isNull);
    final label = tester.getSize(find.text('Severity').first);
    final expanded = tester.getSize(
      find.ancestor(of: find.text('Severity'), matching: find.byType(Expanded)),
    );
    expect(
      expanded.width,
      120 - 2 * kCruxTableCellPadding - kCruxTableSortArrowSize,
    );
    expect(label.width, lessThanOrEqualTo(expanded.width));
    expect(
      tester.getSize(find.byIcon(Icons.arrow_drop_up)).width,
      kCruxTableSortArrowSize,
    );
  });

  testWidgets('an unsorted cell gives the label the whole content width', (
    tester,
  ) async {
    await _pump(tester, width: 120, sorted: false);
    final expanded = tester.getSize(
      find.ancestor(of: find.text('Severity'), matching: find.byType(Expanded)),
    );
    expect(expanded.width, 120 - 2 * kCruxTableCellPadding);
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
  });
}
