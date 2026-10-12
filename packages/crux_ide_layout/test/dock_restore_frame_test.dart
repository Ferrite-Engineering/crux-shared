// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the IDE layout: a stateful widget whose `State` counts its
/// creations, so a test can tell "rebuilt in place" from "discarded and
/// created again". Fills whatever it is given, as the real layout does.
class _Layout extends StatefulWidget {
  const _Layout();

  static int created = 0;

  @override
  State<_Layout> createState() => _LayoutState();
}

class _LayoutState extends State<_Layout> {
  @override
  void initState() {
    super.initState();
    _Layout.created++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(
    key: ValueKey('layout'),
    child: ColoredBox(color: Colors.white),
  );
}

/// A harness whose bars the test toggles one at a time.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _left = false;
  bool _right = false;
  bool _bottom = false;

  /// Shows or hides the bars; an omitted argument leaves that bar as it is.
  void show({bool? left, bool? right, bool? bottom}) {
    setState(() {
      _left = left ?? _left;
      _right = right ?? _right;
      _bottom = bottom ?? _bottom;
    });
  }

  @override
  Widget build(BuildContext context) => CruxDockRestoreFrame(
    leftBar: _left
        ? const SizedBox(
            key: ValueKey('bar.left'),
            width: 24,
            height: double.infinity,
          )
        : null,
    rightBar: _right
        ? const SizedBox(
            key: ValueKey('bar.right'),
            width: 24,
            height: double.infinity,
          )
        : null,
    bottomBar: _bottom
        ? const SizedBox(
            key: ValueKey('bar.bottom'),
            height: 24,
            width: double.infinity,
          )
        : null,
    child: const _Layout(),
  );
}

Future<_HarnessState> _pump(WidgetTester tester) async {
  _Layout.created = 0;
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: _Harness())),
  );
  return tester.state<_HarnessState>(find.byType(_Harness));
}

void main() {
  testWidgets('produces the fixed Row / Expanded / Column shape', (
    tester,
  ) async {
    final harness = await _pump(tester);
    harness.show(left: true, right: true, bottom: true);
    await tester.pump();

    final row = tester.widget<Row>(
      find
          .descendant(
            of: find.byType(CruxDockRestoreFrame),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(row.children, hasLength(3));
    expect(row.children[0].key, CruxDockRestoreFrame.leftBarKey);
    expect(row.children[1].key, CruxDockRestoreFrame.centerKey);
    expect(row.children[2].key, CruxDockRestoreFrame.rightBarKey);
    final column = (row.children[1] as Expanded).child as Column;
    expect(column.children, hasLength(2));
    expect(column.children[0], isA<Expanded>());
    expect(column.children[1].key, CruxDockRestoreFrame.bottomBarKey);

    // Each bar sits on its own edge; the layout takes what is left.
    final frame = tester.getRect(find.byType(CruxDockRestoreFrame));
    final left = tester.getRect(find.byKey(const ValueKey('bar.left')));
    final right = tester.getRect(find.byKey(const ValueKey('bar.right')));
    final bottom = tester.getRect(find.byKey(const ValueKey('bar.bottom')));
    final layout = tester.getRect(find.byKey(const ValueKey('layout')));
    expect(left.left, frame.left);
    expect(left.height, frame.height);
    expect(right.right, frame.right);
    expect(right.height, frame.height);
    expect(bottom.bottom, frame.bottom);
    expect(bottom.width, frame.width - 48);
    expect(layout, Rect.fromLTRB(24, 0, frame.width - 24, frame.height - 24));
  });

  testWidgets('with no bars the layout fills the frame', (tester) async {
    await _pump(tester);
    expect(find.byKey(CruxDockRestoreFrame.leftBarKey), findsNothing);
    expect(find.byKey(CruxDockRestoreFrame.rightBarKey), findsNothing);
    expect(find.byKey(CruxDockRestoreFrame.bottomBarKey), findsNothing);
    expect(find.byKey(CruxDockRestoreFrame.centerKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('layout'))),
      tester.getRect(find.byType(CruxDockRestoreFrame)),
    );
  });

  testWidgets(
    'collapsing or restoring any region keeps the layout element and state',
    (tester) async {
      final harness = await _pump(tester);
      final element = tester.element(find.byType(_Layout));
      final state = tester.state<_LayoutState>(find.byType(_Layout));
      expect(_Layout.created, 1);

      Future<void> toggle({bool? left, bool? right, bool? bottom}) async {
        harness.show(left: left, right: right, bottom: bottom);
        await tester.pump();
        expect(
          tester.element(find.byType(_Layout)),
          same(element),
          reason: 'the layout element must survive a bar toggle',
        );
        expect(tester.state<_LayoutState>(find.byType(_Layout)), same(state));
        expect(
          _Layout.created,
          1,
          reason: 'the layout must not be re-created',
        );
      }

      await toggle(left: true);
      expect(find.byKey(const ValueKey('bar.left')), findsOneWidget);
      await toggle(bottom: true);
      await toggle(right: true);
      await toggle(left: false);
      expect(find.byKey(const ValueKey('bar.left')), findsNothing);
      await toggle(right: false);
      await toggle(bottom: false);
      await toggle(right: true);
      await toggle(left: true);
      expect(find.byKey(const ValueKey('bar.left')), findsOneWidget);
      expect(find.byKey(const ValueKey('bar.right')), findsOneWidget);
      expect(find.byKey(const ValueKey('bar.bottom')), findsNothing);
    },
  );

  testWidgets('a bar that stays keeps its own element across another toggle', (
    tester,
  ) async {
    final harness = await _pump(tester)
      ..show(right: true);
    await tester.pump();
    final rightElement = tester.element(
      find.byKey(const ValueKey('bar.right')),
    );
    harness.show(left: true);
    await tester.pump();
    expect(
      tester.element(find.byKey(const ValueKey('bar.right'))),
      same(rightElement),
      reason: 'the right bar is matched by key, not by its index in the Row',
    );
  });
}
