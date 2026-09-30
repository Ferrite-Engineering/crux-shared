// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Column(children: <Widget>[const Spacer(), child]),
  ),
);

void main() {
  group('CruxStatusBar', () {
    testWidgets('renders provided segments', (tester) async {
      await tester.pumpWidget(
        _host(
          const CruxStatusBar(
            segments: <Widget>[
              CruxStatusSegment('File: cpu.v'),
              CruxStatusSegment('Top: cpu'),
              CruxStatusSegment('42 cells'),
            ],
          ),
        ),
      );

      expect(find.text('File: cpu.v'), findsOneWidget);
      expect(find.text('Top: cpu'), findsOneWidget);
      expect(find.text('42 cells'), findsOneWidget);
      // A `|` divider sits between each adjacent pair (3 segments → 2).
      expect(find.text('|'), findsNWidgets(2));
    });

    testWidgets('has the canonical fixed height', (tester) async {
      await tester.pumpWidget(
        _host(const CruxStatusBar(segments: <Widget>[CruxStatusSegment('x')])),
      );

      final size = tester.getSize(find.byType(CruxStatusBar));
      expect(size.height, kCruxStatusBarHeight);
    });

    testWidgets('honors an explicit height override', (tester) async {
      await tester.pumpWidget(
        _host(
          const CruxStatusBar(
            height: 40,
            segments: <Widget>[CruxStatusSegment('x')],
          ),
        ),
      );

      expect(tester.getSize(find.byType(CruxStatusBar)).height, 40);
    });

    testWidgets('segments are left-aligned and trailing is right-pinned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CruxStatusBar(
            segments: <Widget>[CruxStatusSegment('left-metric')],
            trailing: <Widget>[Text('trailing-slot')],
          ),
        ),
      );

      final barLeft = tester.getTopLeft(find.byType(CruxStatusBar)).dx;
      final barRight = tester.getTopRight(find.byType(CruxStatusBar)).dx;
      final segLeft = tester.getTopLeft(find.text('left-metric')).dx;
      final trailingRight = tester.getTopRight(find.text('trailing-slot')).dx;

      // Segment sits hard-left (within the 8 dp gutter).
      expect(segLeft, lessThan(barLeft + 12));
      // Trailing sits hard-right.
      expect(trailingRight, greaterThan(barRight - 4));
      // ...and the trailing slot is to the right of the segment.
      expect(trailingRight, greaterThan(segLeft));
    });

    testWidgets('renders leading widgets before the segment strip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CruxStatusBar(
            leading: <Widget>[Icon(Icons.chevron_left)],
            segments: <Widget>[CruxStatusSegment('metric')],
          ),
        ),
      );

      final leadingLeft = tester.getTopLeft(find.byIcon(Icons.chevron_left)).dx;
      final segLeft = tester.getTopLeft(find.text('metric')).dx;
      expect(leadingLeft, lessThan(segLeft));
    });

    testWidgets('centers the center slot between leading and trailing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const CruxStatusBar(
            segments: <Widget>[CruxStatusSegment('metric')],
            center: Icon(Icons.keyboard_arrow_up),
            trailing: <Widget>[Icon(Icons.chevron_right)],
          ),
        ),
      );

      final barCenter = tester.getCenter(find.byType(CruxStatusBar)).dx;
      final slotCenter = tester
          .getCenter(find.byIcon(Icons.keyboard_arrow_up))
          .dx;
      // Within a small tolerance of the geometric center.
      expect((slotCenter - barCenter).abs(), lessThan(20));
    });

    testWidgets('exposes a baseline text style resolver', (tester) async {
      late TextStyle? resolved;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              resolved = CruxStatusBar.resolveTextStyle(context);
              return const CruxStatusBar();
            },
          ),
        ),
      );

      expect(resolved?.fontFamily, 'monospace');
      expect(resolved?.fontSize, kCruxStatusBarFontSize);
    });

    testWidgets('is theme-aware (renders under a dark theme)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: Column(
              children: <Widget>[
                Spacer(),
                CruxStatusBar(segments: <Widget>[CruxStatusSegment('dark')]),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('dark'), findsOneWidget);
    });
  });

  group('CruxStatusBusyIndicator', () {
    Future<void> pump(WidgetTester tester, {String? label}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  const Spacer(),
                  CruxStatusBar(
                    trailing: <Widget>[
                      CruxStatusBusyIndicator(semanticsLabel: label),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('fits inside the bar height', (tester) async {
      await pump(tester);
      // The ring must not force the bar past its fixed height — that is the
      // whole reason it is shared instead of hand-rolled per product.
      expect(
        tester.getSize(find.byType(CruxStatusBar)).height,
        kCruxStatusBarHeight,
      );
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)).height,
        lessThan(kCruxStatusBarHeight),
      );
    });

    testWidgets('announces the operation it is waiting on', (tester) async {
      await pump(tester, label: 'Running lint engines');
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.semanticsLabel, 'Running lint engines');
      expect(indicator.strokeWidth, 2);
    });
  });
}
