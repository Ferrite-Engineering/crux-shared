// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_heatmap/crux_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behaviour of the shared calendar heatmap.
///
/// The two forks this replaced had **no tests at all** between them, in either
/// product — which is why the column-offset arithmetic below is asserted
/// rather than eyeballed. It is the only real logic in the widget, and it is
/// the part that silently shifts the whole grid by a column when it is wrong.
const _size = 14.0;
const _gap = 2.0;
const double _pitch = _size + _gap;

List<CruxHeatmapCell<int>> _cells(DateTime start, int count) => [
  for (var i = 0; i < count; i++)
    CruxHeatmapCell<int>(
      day: start.add(Duration(days: i)),
      color: Colors.green,
      tooltip: 'day $i',
      payload: i,
    ),
];

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4650C8),
          brightness: brightness,
        ),
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('layout', () {
    testWidgets('the first cell sits on the row for its weekday', (
      tester,
    ) async {
      // 2026-08-19 is a Wednesday: weekday 3, so row index 2.
      final start = DateTime.utc(2026, 8, 19);
      await tester.pumpWidget(
        _host(CruxCalendarHeatmap<int>(start: start, cells: _cells(start, 1))),
      );

      final p = tester.widget<Positioned>(find.byType(Positioned));
      expect(p.left, 0);
      expect(p.top, 2 * _pitch);
    });

    testWidgets('cells flow down a column, then wrap to the next week', (
      tester,
    ) async {
      // Monday start, so the grid begins at row 0 with no padding.
      final start = DateTime.utc(2026, 8, 17);
      await tester.pumpWidget(
        _host(CruxCalendarHeatmap<int>(start: start, cells: _cells(start, 9))),
      );

      final ps = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .toList();
      expect(ps.length, 9);
      // Sunday, the seventh day, is the last row of the first column.
      expect(ps[6].left, 0);
      expect(ps[6].top, 6 * _pitch);
      // The eighth wraps to the top of column two.
      expect(ps[7].left, _pitch);
      expect(ps[7].top, 0);
    });

    testWidgets('the canvas is wide enough for the partial first week', (
      tester,
    ) async {
      // Saturday start: six days of leading offset, so 7 cells straddle two
      // columns even though they would fit in one from a Monday.
      final start = DateTime.utc(2026, 8, 22);
      await tester.pumpWidget(
        _host(CruxCalendarHeatmap<int>(start: start, cells: _cells(start, 7))),
      );

      final box = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(SizedBox),
        ),
      );
      expect(box.width, 2 * _pitch);
      expect(box.height, 7 * _pitch);
    });

    testWidgets('an empty range renders nothing at all', (tester) async {
      await tester.pumpWidget(
        _host(
          CruxCalendarHeatmap<int>(
            start: DateTime.utc(2026, 8, 17),
            cells: const [],
          ),
        ),
      );

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('cell size and gap are honoured', (tester) async {
      final start = DateTime.utc(2026, 8, 17);
      await tester.pumpWidget(
        _host(
          CruxCalendarHeatmap<int>(
            start: start,
            cells: _cells(start, 8),
            cellSize: 20,
            cellGap: 4,
          ),
        ),
      );

      final ps = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .toList();
      expect(ps[7].left, 24);
      expect(ps.first.width, 20);
    });
  });

  group('interaction', () {
    testWidgets('tapping a cell reports that cell payload', (tester) async {
      final start = DateTime.utc(2026, 8, 17);
      final tapped = <int>[];
      await tester.pumpWidget(
        _host(
          CruxCalendarHeatmap<int>(
            start: start,
            cells: _cells(start, 5),
            onCellTap: tapped.add,
          ),
        ),
      );

      // Found by tooltip rather than by index: the tree carries chrome
      // gesture detectors of its own, so an ordinal into `byType` addresses a
      // different cell than it appears to.
      await tester.tap(
        find.descendant(
          of: find.byTooltip('day 3'),
          matching: find.byType(GestureDetector),
        ),
        warnIfMissed: false,
      );
      expect(tapped, [3]);
    });

    testWidgets('a null callback leaves cells inert', (tester) async {
      final start = DateTime.utc(2026, 8, 17);
      await tester.pumpWidget(
        _host(CruxCalendarHeatmap<int>(start: start, cells: _cells(start, 3))),
      );

      for (final g in tester.widgetList<GestureDetector>(
        find.byType(GestureDetector),
      )) {
        expect(g.onTap, isNull);
      }
    });

    testWidgets('every cell carries the tooltip the host supplied', (
      tester,
    ) async {
      final start = DateTime.utc(2026, 8, 17);
      await tester.pumpWidget(
        _host(CruxCalendarHeatmap<int>(start: start, cells: _cells(start, 4))),
      );

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(messages, ['day 0', 'day 1', 'day 2', 'day 3']);
    });
  });

  /// A heatmap cell has no visible text, so its tooltip is the *only* thing a
  /// screen reader can announce. `labeledTapTargetGuideline` is the assertion
  /// that keeps the required-tooltip decision honest: drop the message and
  /// this fails rather than shipping a grid of anonymous buttons.
  group('accessibility', () {
    for (final brightness in Brightness.values) {
      testWidgets('meets the labelled-target guideline (${brightness.name})', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final start = DateTime.utc(2026, 8, 17);
        await tester.pumpWidget(
          _host(
            CruxCalendarHeatmap<int>(
              start: start,
              cells: _cells(start, 30),
              onCellTap: (_) {},
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        handle.dispose();
      });
    }
  });
}
