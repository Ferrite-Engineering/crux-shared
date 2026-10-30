// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kLongPressTimeout, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

enum _Export { sarif, json, csv, html }

CruxToolbarButtonItem<_Export> _variant(_Export a, IconData icon) =>
    CruxToolbarButtonItem<_Export>(action: a, icon: icon, tooltip: a.name);

Widget _wrapSplit({
  String Function(_Export)? faceTooltip,
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
          faceTooltip: faceTooltip,
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

    // Over a remote display a mouse button-up can arrive after the long-press
    // timeout; that click must fire the tool, not open the menu.
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.trackpad]) {
      testWidgets('a ${kind.name} held past the long-press timeout fires the '
          'faced variant and opens no menu', (tester) async {
        final fired = <_Export>[];
        await tester.pumpWidget(_wrapSplit(onAction: fired.add));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey(_Export.sarif))),
          kind: kind,
        );
        await tester.pump(const Duration(seconds: 2));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('json'), findsNothing);
        // A trackpad press is delivered as a pan/zoom, never a button, so only
        // the mouse is required to fire.
        if (kind == PointerDeviceKind.mouse) {
          expect(fired, [_Export.sarif]);
        }
      });
    }

    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      testWidgets('a ${kind.name} long press opens the sibling menu and fires '
          'nothing', (tester) async {
        final fired = <_Export>[];
        await tester.pumpWidget(_wrapSplit(onAction: fired.add));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey(_Export.sarif))),
          kind: kind,
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('json'), findsOneWidget);
        expect(fired, isEmpty);
      });
    }

    testWidgets('a right-click held past the timeout opens the sibling menu', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapSplit());
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey(_Export.sarif))),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('json'), findsOneWidget);
    });

    testWidgets('a mouse click on the corner triangle opens the sibling menu', (
      tester,
    ) async {
      final fired = <_Export>[];
      await tester.pumpWidget(_wrapSplit(onAction: fired.add));
      await tester.pumpAndSettle();

      final corner =
          tester.getBottomRight(find.byType(CruxToolbarSplitButton<_Export>)) -
          const Offset(4, 4);
      final gesture = await tester.startGesture(
        corner,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('json'), findsOneWidget);
      expect(fired, isEmpty);
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

    testWidgets('the face tooltip names the cluster and follows the faced '
        'variant', (tester) async {
      await tester.pumpWidget(
        _wrapSplit(
          faceTooltip: (a) => 'Export… (${a.name.toUpperCase()} is default)',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Export… (SARIF is default)'), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey(_Export.sarif)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('json').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Export… (JSON is default)'), findsOneWidget);
    });

    testWidgets('without a face tooltip the faced variant names itself', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapSplit());
      await tester.pumpAndSettle();
      expect(find.byTooltip('sarif'), findsOneWidget);
    });

    for (final enabled in [true, false]) {
      testWidgets("the face is announced under the faced action's name when "
          "${enabled ? 'enabled' : 'disabled'}", (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _wrapSplit(
            isEnabled: (_) => enabled,
            faceTooltip: (a) => 'Export… (${a.name.toUpperCase()} is default)',
          ),
        );
        await tester.pumpAndSettle();
        final node = tester.getSemantics(
          find.descendant(
            of: find.byKey(const ValueKey(_Export.sarif)),
            matching: find.byType(IconButton),
          ),
        );
        final data = node.getSemanticsData();
        expect(
          data.label,
          'Export… (SARIF is default)',
          reason: 'a screen reader must not announce a bare "button"',
        );
        expect(data.flagsCollection.isButton, isTrue);
        expect(
          data.flagsCollection.isEnabled,
          enabled ? ui.Tristate.isTrue : ui.Tristate.isFalse,
        );
        handle.dispose();
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
      await tester.pumpWidget(_wrapSplit(isEnabled: (a) => a != _Export.html));
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
      await tester.pumpWidget(wrap(CruxRunState.idle, onRun: () => ran = true));
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
