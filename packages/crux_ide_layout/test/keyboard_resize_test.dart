// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Layout implements IdePanelLayout {
  @override
  bool leftVisible = true;
  @override
  bool rightVisible = true;
  @override
  bool bottomVisible = true;
  @override
  PaneSize? leftSize = PaneSize.pixel(200);
  @override
  PaneSize? rightSize = PaneSize.pixel(200);
  @override
  PaneSize? bottomSize = PaneSize.pixel(150);
}

class _Sink implements IdePanelLayoutSink {
  final List<String> calls = <String>[];

  @override
  void setLeftVisible({required bool visible}) {}
  @override
  void setRightVisible({required bool visible}) {}
  @override
  void setBottomVisible({required bool visible}) {}
  @override
  void setLeftSize(double pixels) => calls.add('left=$pixels');
  @override
  void setRightSize(double pixels) => calls.add('right=$pixels');
  @override
  void setBottomSize(double pixels) => calls.add('bottom=$pixels');
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey arrow) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(arrow);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+Shift+Arrow resizes the region holding focus and '
      'persists the size', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sink = _Sink();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CruxIdeLayout(
            layout: _Layout(),
            sink: sink,
            leftMinSize: PaneSize.pixel(150),
            leftBuilder: (_, _) =>
                TextButton(onPressed: () {}, child: const Text('Left')),
            centerBuilder: (_, _) =>
                TextButton(onPressed: () {}, child: const Text('Center')),
            rightBuilder: (_, _) =>
                TextButton(onPressed: () {}, child: const Text('Right')),
            bottomBuilder: (_, _) =>
                TextButton(onPressed: () {}, child: const Text('Bottom')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double leftWidth() =>
        tester.getSize(find.byType(CruxFocusRegion).first).width;
    final before = leftWidth();

    Focus.of(tester.element(find.text('Left'))).requestFocus();
    await tester.pump();

    await _chord(tester, LogicalKeyboardKey.arrowRight);
    expect(leftWidth(), closeTo(before + kCruxPaneResizeStep, 0.5));
    expect(sink.calls.last, 'left=${before + kCruxPaneResizeStep}');

    // Shrinking stops at the region's minimum.
    for (var i = 0; i < 10; i++) {
      await _chord(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(leftWidth(), closeTo(150, 0.5));

    // Focus in the bottom region resizes the bottom region instead.
    Focus.of(tester.element(find.text('Bottom'))).requestFocus();
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.arrowUp);
    expect(sink.calls.last, 'bottom=${150 + kCruxPaneResizeStep}');
  });

  testWidgets('the resize key handler adds nothing to the semantics tree', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    // A search field above a loose line of text: the shape that, under a
    // key-handling Focus that carried semantics, merged into one node named
    // "Search 644 rules".
    Widget panel(String name) => Column(
      children: [
        TextField(decoration: InputDecoration(hintText: 'Search $name')),
        Text('644 $name'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CruxIdeLayout(
            layout: _Layout(),
            sink: _Sink(),
            leftBuilder: (_, _) => panel('left'),
            centerBuilder: (_, _) => panel('center'),
            rightBuilder: (_, _) => panel('right'),
            bottomBuilder: (_, _) => panel('bottom'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final name in ['left', 'center', 'right', 'bottom']) {
      expect(
        find.bySemanticsLabel('644 $name'),
        findsOneWidget,
        reason: 'the $name region keeps its field and its text apart',
      );
    }
    semantics.dispose();
  });
}
