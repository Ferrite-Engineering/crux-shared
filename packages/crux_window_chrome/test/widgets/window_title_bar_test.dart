// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/window_caption_buttons.dart';
import 'package:crux_window_chrome/src/widgets/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('WindowTitleBar', () {
    Widget wrap({Widget? menuBar}) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            WindowTitleBar(
              logo: const SizedBox.square(dimension: 18),
              menuBar:
                  menuBar ??
                  const MenuBar(
                    children: [
                      SubmenuButton(
                        menuChildren: [],
                        child: Text('File'),
                      ),
                    ],
                  ),
            ),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ),
    );

    testWidgets('hosts the menu bar inline with the logo and caption buttons', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.byType(WindowTitleBar), findsOneWidget);
      // The supplied menu bar is rendered inside the title bar.
      expect(find.byType(MenuBar), findsOneWidget);
      // Caption buttons (min/max/close) on the right.
      expect(find.byType(WindowCaptionButtons), findsOneWidget);
      // Draggable regions exist (logo + empty caption area).
      expect(find.byType(DragToMoveArea), findsWidgets);
    });

    testWidgets('logo sits at the far left, before the menu bar', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      // The first draggable area (logo) starts at the very left edge of the
      // title bar, and the menu bar is to its right — i.e. left-aligned chrome,
      // not the old center-justified strip.
      final logoLeft = tester.getTopLeft(find.byType(DragToMoveArea).first).dx;
      final menuLeft = tester.getTopLeft(find.byType(MenuBar)).dx;
      expect(logoLeft, lessThan(menuLeft));
      expect(logoLeft, lessThan(40));
    });

    testWidgets('builds without exceptions (no live window channel)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window scrolls the menus instead of overflowing', (
      tester,
    ) async {
      // Regression: the Row had a fixed-width logo, a natural-width menu bar
      // and fixed-width caption buttons, so once the Expanded spacer hit zero
      // there was nothing left to give and the bar overflowed — 127px at
      // 390pt on the Windows integration leg, which pushed the close button
      // off-screen. A user can drag a window this narrow, so this is not a
      // test-only width.
      tester.view.physicalSize = const Size(390, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrap(
          menuBar: const MenuBar(
            children: [
              SubmenuButton(menuChildren: [], child: Text('File')),
              SubmenuButton(menuChildren: [], child: Text('Edit')),
              SubmenuButton(menuChildren: [], child: Text('Selection')),
              SubmenuButton(menuChildren: [], child: Text('View')),
              SubmenuButton(menuChildren: [], child: Text('Navigate')),
              SubmenuButton(menuChildren: [], child: Text('Terminal')),
              SubmenuButton(menuChildren: [], child: Text('Help')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // The window controls stay fully on-screen — the whole point. Anything
      // else may scroll or clip; the close button may not.
      final captions = tester.getRect(find.byType(WindowCaptionButtons));
      expect(captions.right, lessThanOrEqualTo(390));
      expect(captions.left, greaterThanOrEqualTo(0));
    });

    group('caption buttons are flush right', () {
      // Regression: the menu bar was a Flexible and the drag region an
      // Expanded, both flex 1, so they split the free space in half. The
      // menus used only their natural width of their half and the rest was
      // left over after the caption buttons, which then floated between the
      // middle and the right edge on any roomy window.
      for (final width in <double>[390, 640, 1024, 1785, 3840]) {
        testWidgets('at ${width.toInt()} px wide', (tester) async {
          setWindowSize(tester, width);
          await tester.pumpWidget(wrap(menuBar: wideMenuBar));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final bar = tester.getRect(find.byType(WindowTitleBar));
          final captions = tester.getRect(find.byType(WindowCaptionButtons));
          expect(bar.right, width);
          expect(captions.right, bar.right);
          expect(captions.width, WindowCaptionButtons.width);
        });
      }
    });

    testWidgets('no RenderFlex overflow at 390 px wide', (tester) async {
      setWindowSize(tester, 390);
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(wrap(menuBar: wideMenuBar));
      await tester.pumpAndSettle();
      FlutterError.onError = previous;

      expect(
        errors.map((e) => e.exceptionAsString()),
        isNot(contains(contains('overflowed'))),
      );
      expect(errors, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window scrolls the menu bar, not the row', (
      tester,
    ) async {
      setWindowSize(tester, 390);
      await tester.pumpWidget(wrap(menuBar: wideMenuBar));
      await tester.pumpAndSettle();

      final scrollable = menuScroller();
      final position = tester.state<ScrollableState>(scrollable).position;
      // The menus are wider than their allowance, so they scroll.
      expect(position.maxScrollExtent, greaterThan(0));

      // The allowance is exactly what the logo and buttons leave over, so
      // the empty drag region has collapsed and the buttons still end at
      // the right edge.
      final viewport = tester.getRect(scrollable);
      expect(
        viewport.width,
        390 - WindowTitleBar.logoSlotWidth - WindowCaptionButtons.width,
      );
      final captions = tester.getRect(find.byType(WindowCaptionButtons));
      expect(viewport.right, captions.left);
      expect(captions.right, 390);

      // The last menu is reachable by scrolling.
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      final help = tester.getRect(find.text('Help'));
      expect(help.right, lessThanOrEqualTo(captions.left));
    });

    testWidgets('a wide window leaves the menus unscrolled at natural width', (
      tester,
    ) async {
      setWindowSize(tester, 1785);
      await tester.pumpWidget(wrap(menuBar: wideMenuBar));
      await tester.pumpAndSettle();

      final scrollable = menuScroller();
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, 0);
      expect(
        tester.getRect(scrollable).width,
        tester.getSize(find.byType(MenuBar)).width,
      );
    });

    group('the empty region between menus and buttons', () {
      late List<MethodCall> calls;

      setUp(() {
        calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('window_manager'), (
              call,
            ) async {
              calls.add(call);
              return call.method == 'isMaximized' ? false : null;
            });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            );
      });

      testWidgets('is one DragToMoveArea spanning menus to buttons', (
        tester,
      ) async {
        setWindowSize(tester, 1785);
        await tester.pumpWidget(wrap(menuBar: wideMenuBar));
        await tester.pumpAndSettle();

        final menus = tester.getRect(menuScroller());
        final captions = tester.getRect(find.byType(WindowCaptionButtons));
        final dragRegion = find.descendant(
          of: find.byType(WindowTitleBar),
          matching: find.byWidgetPredicate(
            (w) => w is DragToMoveArea && w.child is SizedBox,
          ),
        );
        final gap = tester.getRect(dragRegion);
        expect(gap.left, menus.right);
        expect(gap.right, captions.left);
        // Everything the logo, menus and buttons leave over, with nothing
        // left beyond the buttons.
        expect(
          gap.width,
          1785 -
              WindowTitleBar.logoSlotWidth -
              menus.width -
              WindowCaptionButtons.width,
        );
        expect(gap.width, greaterThan(0));
      });

      testWidgets('drags the window from right beside the buttons', (
        tester,
      ) async {
        setWindowSize(tester, 1785);
        await tester.pumpWidget(wrap(menuBar: wideMenuBar));
        await tester.pumpAndSettle();
        calls.clear();

        final captions = tester.getRect(find.byType(WindowCaptionButtons));
        await tester.dragFrom(
          Offset(captions.left - 4, captions.center.dy),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();

        expect(calls.map((c) => c.method), contains('startDragging'));
      });

      testWidgets('drags the window from right after the menu titles', (
        tester,
      ) async {
        // Making the menu bar an Expanded would also pin the buttons right,
        // but its half of the bar would become scroll viewport, and a
        // viewport is not a drag region.
        setWindowSize(tester, 1785);
        await tester.pumpWidget(wrap(menuBar: wideMenuBar));
        await tester.pumpAndSettle();
        calls.clear();

        final menus = tester.getRect(find.byType(MenuBar));
        await tester.dragFrom(
          Offset(menus.right + 4, menus.center.dy),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();

        expect(calls.map((c) => c.method), contains('startDragging'));
      });

      testWidgets('drags the window from the logo', (tester) async {
        setWindowSize(tester, 1785);
        await tester.pumpWidget(wrap(menuBar: wideMenuBar));
        await tester.pumpAndSettle();
        calls.clear();

        await tester.dragFrom(
          const Offset(WindowTitleBar.logoSlotWidth / 2, 10),
          const Offset(40, 0),
        );
        await tester.pumpAndSettle();

        expect(calls.map((c) => c.method), contains('startDragging'));
      });
    });

    testWidgets('lays an oversized logo out in its fixed slot', (
      tester,
    ) async {
      // The menu allowance is computed from the logo slot, so a host logo
      // larger than the slot must not widen it and push the buttons off.
      setWindowSize(tester, 800);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                WindowTitleBar(
                  logo: SizedBox(width: 120, height: 120),
                  menuBar: wideMenuBar,
                ),
                Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final logo = tester.getRect(find.byType(DragToMoveArea).first);
      expect(logo.width, WindowTitleBar.logoSlotWidth);
      expect(
        tester.getRect(find.byType(WindowCaptionButtons)).right,
        800,
      );
    });
  });
}

/// A realistic seven-menu bar, wide enough to need scrolling at 390 px.
const wideMenuBar = MenuBar(
  children: [
    SubmenuButton(menuChildren: [], child: Text('File')),
    SubmenuButton(menuChildren: [], child: Text('Edit')),
    SubmenuButton(menuChildren: [], child: Text('Selection')),
    SubmenuButton(menuChildren: [], child: Text('View')),
    SubmenuButton(menuChildren: [], child: Text('Navigate')),
    SubmenuButton(menuChildren: [], child: Text('Terminal')),
    SubmenuButton(menuChildren: [], child: Text('Help')),
  ],
);

/// The title bar's own horizontal scroller around the menu bar. `MenuBar`
/// carries a Scrollable of its own further down, so take the outermost.
Finder menuScroller() => find
    .descendant(
      of: find.byType(WindowTitleBar),
      matching: find.byType(Scrollable),
    )
    .first;

void setWindowSize(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
