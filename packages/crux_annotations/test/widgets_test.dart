// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_annotations/crux_annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Stack(children: [Positioned(left: 20, top: 20, child: child)]),
  ),
);

CruxCalloutBalloon _balloon({
  String text = 'stale by one cycle',
  bool isEditing = false,
  VoidCallback? onCollapse,
  VoidCallback? onDelete,
  VoidCallback? onBeginEdit,
  void Function(String)? onCommit,
  bool drifted = false,
}) => CruxCalloutBalloon(
  text: text,
  number: 3,
  color: Colors.teal,
  surface: Colors.white,
  onSurface: Colors.black,
  drifted: drifted,
  touchTarget: 40,
  isEditing: isEditing,
  onCollapse: onCollapse,
  onDelete: onDelete,
  onCommit: onCommit ?? (_) {},
  onBeginEdit: onBeginEdit,
  collapseTooltip: 'Collapse',
  deleteTooltip: 'Delete annotation',
  editHint: 'Write a note',
  maxLength: 1000,
);

void main() {
  group('CruxCalloutDraggable', () {
    testWidgets('claims the pointer on down and releases after the up', (
      tester,
    ) async {
      final claims = <bool>[];
      final deltas = <Offset>[];
      var started = 0;
      var ended = 0;
      var downs = 0;
      await tester.pumpWidget(
        _host(
          CruxCalloutDraggable(
            onClaim: claims.add,
            onPointerDown: () => downs++,
            onDragStart: () => started++,
            onDragUpdate: deltas.add,
            onDragEnd: () => ended++,
            child: const SizedBox(width: 80, height: 30),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(40, 30));
      expect(claims, <bool>[true]);
      expect(downs, 1);
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(30, 10));
      await gesture.up();
      // Released on a microtask, after the ancestors have seen the up.
      expect(claims.last, isFalse);
      expect(started, 1);
      expect(ended, 1);
      final total = deltas.fold(Offset.zero, (a, b) => a + b);
      expect(total.dx, greaterThan(0));
    });

    testWidgets('a cancelled pointer releases the claim too', (tester) async {
      final claims = <bool>[];
      await tester.pumpWidget(
        _host(
          CruxCalloutDraggable(
            onClaim: claims.add,
            child: const SizedBox(width: 80, height: 30),
          ),
        ),
      );
      final gesture = await tester.startGesture(const Offset(40, 30));
      await gesture.cancel();
      await tester.pump();
      expect(claims, <bool>[true, false]);
    });

    testWidgets('shows the move cursor only when it can move', (tester) async {
      await tester.pumpWidget(
        _host(
          CruxCalloutDraggable(
            onDragUpdate: (_) {},
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final region = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(CruxCalloutDraggable),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(region.cursor, SystemMouseCursors.move);

      var taps = 0;
      await tester.pumpWidget(
        _host(
          CruxCalloutDraggable(
            onTap: () => taps++,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      final inert = tester.widget<MouseRegion>(
        find.descendant(
          of: find.byType(CruxCalloutDraggable),
          matching: find.byType(MouseRegion),
        ),
      );
      expect(inert.cursor, MouseCursor.defer);
      await tester.tap(find.byType(CruxCalloutDraggable));
      expect(taps, 1);
    });
  });

  group('CruxCalloutDoubleTapRegion', () {
    testWidgets('fires on two presses close in time and space', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _host(
          CruxCalloutDoubleTapRegion(
            onDoubleTap: () => fired++,
            child: const SizedBox(width: 60, height: 20),
          ),
        ),
      );
      final at = tester.getCenter(find.byType(CruxCalloutDoubleTapRegion));
      Future<void> press(Duration when, {Offset shift = Offset.zero}) async {
        final gesture = await tester.createGesture();
        await gesture.down(at + shift, timeStamp: when);
        await gesture.up(timeStamp: when + const Duration(milliseconds: 10));
      }

      await press(Duration.zero);
      await press(const Duration(milliseconds: 100));
      expect(fired, 1);

      // A slow second press is two single taps.
      await press(const Duration(seconds: 2));
      await press(const Duration(seconds: 4));
      expect(fired, 1);

      // So is a second press far from the first.
      await press(const Duration(seconds: 6));
      await press(
        const Duration(seconds: 6, milliseconds: 100),
        shift: const Offset(0, 300),
      );
      expect(fired, 1);
    });
  });

  group('CruxCalloutBalloon', () {
    testWidgets('draws the number and text, controls only when offered', (
      tester,
    ) async {
      await tester.pumpWidget(_host(SizedBox(width: 190, child: _balloon())));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('stale by one cycle'), findsOneWidget);
      expect(find.byIcon(Icons.unfold_less), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);

      var collapsed = 0;
      var deleted = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 190,
            child: _balloon(
              onCollapse: () => collapsed++,
              onDelete: () => deleted++,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.unfold_less));
      await tester.tap(find.byIcon(Icons.close));
      expect(collapsed, 1);
      expect(deleted, 1);
      expect(find.bySemanticsLabel('Collapse'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete annotation'), findsOneWidget);
    });

    testWidgets('the controls are 0.6 of the pointer target', (tester) async {
      await tester.pumpWidget(
        _host(SizedBox(width: 190, child: _balloon(onDelete: () {}))),
      );
      final size = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(size, const Size(24, 24));
    });

    testWidgets('a drifted note reads in italics', (tester) async {
      await tester.pumpWidget(
        _host(SizedBox(width: 190, child: _balloon(drifted: true))),
      );
      final text = tester.widget<Text>(find.text('stale by one cycle'));
      expect(text.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('double-tapping the text opens the editor', (tester) async {
      var begun = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(width: 190, child: _balloon(onBeginEdit: () => begun++)),
        ),
      );
      final text = find.byKey(kCruxCalloutBalloonTextKey);
      await tester.tap(text);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(text);
      expect(begun, 1);
    });

    testWidgets('the editor commits on Enter and reverts on Escape', (
      tester,
    ) async {
      final commits = <String>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 190,
            child: _balloon(
              isEditing: true,
              text: 'before',
              onCommit: commits.add,
              onDelete: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.unfold_less), findsNothing);
      await tester.enterText(find.byType(TextField), '  after  ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(commits, <String>['after']);

      await tester.pumpWidget(_host(const SizedBox()));
      final reverts = <String>[];
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 190,
            child: _balloon(
              isEditing: true,
              text: 'kept',
              onCommit: reverts.add,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'discarded');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(reverts, <String>['kept']);
    });

    testWidgets('the balloon adds no Tab stop of its own', (tester) async {
      // Keyboard access to a callout is the product's (a focusable wrapper
      // or its panel row); the balloon must not add silent stops to it.
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 190,
            child: _balloon(onCollapse: () {}, onDelete: () {}),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      final walk = await walkFocus(tester);
      expect(
        walk.stops.where((s) => s.spoken && !s.isNameless),
        isEmpty,
      );
      semantics.dispose();
    });
  });

  group('CruxCalloutNumberDot', () {
    testWidgets('a selected dot is ringed', (tester) async {
      await tester.pumpWidget(
        _host(
          const CruxCalloutNumberDot(
            number: 7,
            color: Colors.teal,
            onColor: Colors.white,
            selected: true,
          ),
        ),
      );
      final box = tester.widget<Container>(find.byType(Container));
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(
        tester.getSize(find.byType(CruxCalloutNumberDot)),
        const Size(kCruxCalloutDotRadius * 2, kCruxCalloutDotRadius * 2),
      );
    });

    testWidgets('the anchor dot is inert', (tester) async {
      await tester.pumpWidget(
        _host(const CruxCalloutAnchorDot(color: Colors.teal)),
      );
      expect(
        tester.getSize(find.byType(CruxCalloutAnchorDot)),
        const Size.square(CruxCalloutAnchorDot.size),
      );
      expect(
        find.descendant(
          of: find.byType(CruxCalloutAnchorDot),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });

  group('CruxCalloutLeadersPainter', () {
    const solid = CruxCalloutLeader(
      from: Offset(10, 10),
      to: Offset(100, 60),
      color: Colors.teal,
      dashed: false,
    );
    const dashed = CruxCalloutLeader(
      from: Offset(10, 10),
      to: Offset(100, 60),
      color: Colors.teal,
      dashed: true,
    );

    test('repaints only when the leaders changed', () {
      const painter = CruxCalloutLeadersPainter([solid]);
      expect(
        painter.shouldRepaint(
          const CruxCalloutLeadersPainter([
            CruxCalloutLeader(
              from: Offset(10, 10),
              to: Offset(100, 60),
              color: Colors.teal,
              dashed: false,
            ),
          ]),
        ),
        isFalse,
      );
      expect(
        painter.shouldRepaint(const CruxCalloutLeadersPainter([dashed])),
        isTrue,
      );
      expect(solid == dashed, isFalse);
      expect(solid.hashCode == dashed.hashCode, isFalse);
    });

    testWidgets('paints solid, dashed and zero-length leaders', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 100,
            child: CustomPaint(
              painter: CruxCalloutLeadersPainter([
                solid,
                dashed,
                CruxCalloutLeader(
                  from: Offset(5, 5),
                  to: Offset(5, 5),
                  color: Colors.red,
                  dashed: true,
                ),
              ]),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('CruxAnnotationGroup draws its header, rows and controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CruxAnnotationGroup(
            label: 'Not displayed (2)',
            trailing: Icon(Icons.visibility),
            children: [Text('row one'), Text('row two')],
          ),
        ),
      ),
    );
    expect(find.text('Not displayed (2)'), findsOneWidget);
    expect(find.text('row one'), findsOneWidget);
    expect(find.text('row two'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });
}
