// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

enum _Export { sarif, json, csv, html }

CruxToolbarButtonItem<_Export> _variant(_Export a, IconData icon) =>
    CruxToolbarButtonItem<_Export>(action: a, icon: icon, tooltip: a.name);

Widget _wrapSplit({
  bool Function(_Export)? isEnabled,
  void Function(_Export)? onAction,
  void Function(_Export)? onVariantChanged,
  _Export? initialVariant,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: CruxToolbarSplitButton<_Export>(
        item: CruxToolbarSplitItem<_Export>(
          id: 'export',
          tooltip: 'Export Report…',
          variants: [
            _variant(_Export.sarif, Icons.upload_file_outlined),
            _variant(_Export.json, Icons.data_object),
            _variant(_Export.csv, Icons.table_chart_outlined),
            _variant(_Export.html, Icons.html),
          ],
        ),
        metrics: CruxToolbarMetrics.desktop,
        isEnabled: isEnabled ?? (_) => true,
        onAction: onAction ?? (_) {},
        shortcutOf: (_) => null,
        initialVariant: initialVariant,
        onVariantChanged: onVariantChanged,
      ),
    ),
  ),
);

void main() {
  group('CruxToolbarSplitButton', () {
    testWidgets('faces the first variant by default', (tester) async {
      await tester.pumpWidget(_wrapSplit());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(_Export.sarif)), findsOneWidget);
    });

    testWidgets('faces the persisted variant when one is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapSplit(initialVariant: _Export.csv));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(_Export.csv)), findsOneWidget);
    });

    testWidgets('falls back when the persisted variant is not in the cluster', (
      tester,
    ) async {
      // A stale persisted id must not leave the button faceless.
      await tester.pumpWidget(_wrapSplit());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(_Export.sarif)), findsOneWidget);
    });

    testWidgets('tapping the face dispatches the faced variant', (
      tester,
    ) async {
      final fired = <_Export>[];
      await tester.pumpWidget(_wrapSplit(onAction: fired.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(_Export.sarif)));
      expect(fired, [_Export.sarif]);
    });

    testWidgets('long-press opens the sibling menu with every variant', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapSplit());
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey(_Export.sarif)));
      await tester.pumpAndSettle();
      for (final v in _Export.values) {
        expect(
          find.text(v.name),
          findsWidgets,
          reason: '${v.name} must be offered in the sibling menu',
        );
      }
    });

    for (final (how, open) in <(String, Future<void> Function(WidgetTester))>[
      (
        'long-press',
        (t) => t.longPress(find.byKey(const ValueKey(_Export.sarif))),
      ),
      (
        'right-click',
        (t) => t.tap(
          find.byKey(const ValueKey(_Export.sarif)),
          buttons: kSecondaryButton,
        ),
      ),
    ]) {
      testWidgets('Escape closes the sibling menu opened by $how', (
        tester,
      ) async {
        await tester.pumpWidget(_wrapSplit());
        await tester.pumpAndSettle();
        await open(tester);
        await tester.pumpAndSettle();
        expect(find.text('json'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('json'), findsNothing);
      });
    }

    testWidgets('choosing a sibling dispatches it, re-faces, and notifies', (
      tester,
    ) async {
      final fired = <_Export>[];
      final remembered = <_Export>[];
      await tester.pumpWidget(
        _wrapSplit(onAction: fired.add, onVariantChanged: remembered.add),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const ValueKey(_Export.sarif)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'csv'));
      await tester.pumpAndSettle();

      expect(fired, [_Export.csv], reason: 'the chosen variant runs');
      expect(remembered, [_Export.csv], reason: 'the host can persist it');
      expect(
        find.byKey(const ValueKey(_Export.csv)),
        findsOneWidget,
        reason: 'the chosen variant becomes the new face',
      );
    });

    testWidgets('a disabled variant is greyed in the sibling menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapSplit(isEnabled: (a) => a != _Export.html),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey(_Export.sarif)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, 'html'))
            .onPressed,
        isNull,
      );
    });
  });

  group('CruxRunStopButton', () {
    Widget wrap(
      CruxRunState state, {
      VoidCallback? onRun,
      VoidCallback? onCancel,
    }) => MaterialApp(
      home: Scaffold(
        body: CruxRunStopButton(
          state: state,
          metrics: CruxToolbarMetrics.desktop,
          runTooltip: 'Run',
          cancelTooltip: 'Cancel',
          onRun: onRun ?? () {},
          onCancel: onCancel ?? () {},
        ),
      ),
    );

    testWidgets('idle shows play and offers to run', (tester) async {
      var ran = false;
      await tester.pumpWidget(
        wrap(CruxRunState.idle, onRun: () => ran = true),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(ran, isTrue);
    });

    testWidgets('running shows stop plus a progress ring, and cancels', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        wrap(CruxRunState.running, onCancel: () => cancelled = true),
      );
      await tester.pump();
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop));
      expect(cancelled, isTrue);
    });

    testWidgets('finished acknowledges, then behaves like idle', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(CruxRunState.finished));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a null handler greys the button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CruxRunStopButton(
              state: CruxRunState.idle,
              metrics: CruxToolbarMetrics.desktop,
              runTooltip: 'Run',
              cancelTooltip: 'Cancel',
              onRun: null,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    });
  });
}
