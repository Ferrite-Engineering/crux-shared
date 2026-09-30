// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(List<Widget> children) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  ),
);

Widget _button(String label, {bool autofocus = false}) => TextButton(
  autofocus: autofocus,
  onPressed: () {},
  child: Text(label),
);

Set<FocusWalkRule> _rules(FocusWalk walk) =>
    walk.problems().map((p) => p.rule).toSet();

void main() {
  testWidgets('a plain row of buttons walks cleanly and cycles', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[_button('Open'), _button('Save'), _button('Close')]),
    );

    final walk = await walkFocus(tester);

    expect(walk.cycled, isTrue);
    expect(walk.stops.map((s) => s.line), <String>[
      'Open button',
      'Save button',
      'Close button',
    ]);
    expect(walk.problems(), isEmpty);
    expectCleanFocusWalk(walk);
    handle.dispose();
  });

  testWidgets('Shift+Tab walks the same stops in reverse', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[_button('Open'), _button('Save'), _button('Close')]),
    );

    final walk = await walkFocus(tester, reverse: true);

    expect(walk.reverse, isTrue);
    expect(walk.stops.map((s) => s.name), <String>['Close', 'Save', 'Open']);
    expect(walk.transcript, startsWith('# Shift+Tab walk: 3 stops, cycles'));
    handle.dispose();
  });

  testWidgets('a focusable widget with no semantics is a defect', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        _button('Open'),
        const Focus(child: SizedBox(width: 40, height: 40)),
        _button('Close'),
      ]),
    );

    final walk = await walkFocus(tester);

    expect(walk.stops, hasLength(3));
    expect(
      _rules(walk).intersection(<FocusWalkRule>{
        FocusWalkRule.silentStop,
        FocusWalkRule.namelessStop,
      }),
      isNotEmpty,
    );
    expect(() => expectCleanFocusWalk(walk), throwsA(isA<TestFailure>()));
    handle.dispose();
  });

  testWidgets('a label, a tooltip and a container name are three names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        _button('Open'),
        Semantics(
          container: true,
          label: 'Statistics',
          child: MergeSemantics(
            child: Tooltip(
              message: 'Show Statistics',
              child: _button('Stats'),
            ),
          ),
        ),
      ]),
    );

    final walk = await walkFocus(tester);
    final stats = walk.stops.firstWhere((s) => s.name == 'Stats');

    expect(stats.description, 'Show Statistics');
    expect(stats.entered, contains(startsWith('Statistics')));
    expect(_rules(walk), contains(FocusWalkRule.twoNames));
    handle.dispose();
  });

  testWidgets('a container that repeats its control is flagged; a '
      'control that names its container is not', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        Semantics(
          container: true,
          label: 'Statistics',
          child: _button('Statistics'),
        ),
        Semantics(
          container: true,
          label: 'sample.vcd',
          child: _button('Close sample.vcd'),
        ),
      ]),
    );

    final walk = await walkFocus(tester);
    final flagged = walk
        .problems()
        .where((p) => p.rule == FocusWalkRule.containerRepeatsName)
        .map((p) => p.stopIndex)
        .toList();

    expect(flagged, <int>[1]);
    handle.dispose();
  });

  testWidgets('a tooltip carrying the full path of a named tab is one name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        MergeSemantics(
          child: Tooltip(
            message: '/kit/simcrux.yaml',
            child: _button('simcrux.yaml'),
          ),
        ),
        _button('Close'),
      ]),
    );

    final walk = await walkFocus(tester);

    expect(_rules(walk), isNot(contains(FocusWalkRule.twoNames)));
    handle.dispose();
  });

  testWidgets('a tooltip that extends the name is one name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        MergeSemantics(
          child: Tooltip(
            message: 'Open File (Ctrl+O)',
            child: _button('Open File'),
          ),
        ),
        _button('Close'),
      ]),
    );

    final walk = await walkFocus(tester);

    expect(_rules(walk), isNot(contains(FocusWalkRule.twoNames)));
    handle.dispose();
  });

  testWidgets('checkbox state and role are reported as spoken', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[
        _button('Open'),
        Checkbox(value: true, onChanged: (_) {}, semanticLabel: 'Wrap lines'),
      ]),
    );

    final walk = await walkFocus(tester);

    expect(walk.stops.last.line, 'Wrap lines check box checked');
    handle.dispose();
  });

  testWidgets('an arrow glyph in a name is flagged', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[_button('Diagnostics → Logs'), _button('Close')]),
    );

    final walk = await walkFocus(tester);

    expect(_rules(walk), contains(FocusWalkRule.unspeakableGlyph));
    handle.dispose();
  });

  testWidgets('a walk cut short reports that it never cycled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[_button('A'), _button('B'), _button('C')]),
    );

    final walk = await walkFocus(tester, maxStops: 2);

    expect(walk.cycled, isFalse);
    expect(_rules(walk), contains(FocusWalkRule.noCycle));
    handle.dispose();
  });

  testWidgets('expectFocusAnnounced fails when nothing claims focus', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(<Widget>[_button('Open')]));
    await tester.pump();

    expect(() => expectFocusAnnounced(tester), throwsA(isA<TestFailure>()));
    handle.dispose();
  });

  testWidgets('expectFocusAnnounced passes on an autofocused control', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(<Widget>[_button('Open', autofocus: true), _button('Save')]),
    );
    await tester.pump();

    expectFocusAnnounced(tester, named: 'Open');
    expect(
      () => expectFocusAnnounced(tester, named: 'Save'),
      throwsA(isA<TestFailure>()),
    );
    handle.dispose();
  });

  testWidgets('the golden transcript round-trips and catches a change', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final dir = Directory.systemTemp.createTempSync('focus_walk_golden');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/walk.txt';

    await tester.pumpWidget(_app(<Widget>[_button('Open'), _button('Save')]));
    final walk = await walkFocus(tester);

    expect(
      () => expectFocusWalkGolden(walk, path),
      throwsA(isA<TestFailure>()),
    );
    final previous = autoUpdateGoldenFiles;
    autoUpdateGoldenFiles = true;
    try {
      expectFocusWalkGolden(walk, path);
    } finally {
      autoUpdateGoldenFiles = previous;
    }
    expectFocusWalkGolden(walk, path);

    File(path).writeAsStringSync(walk.transcript.replaceAll('Save', 'Sav'));
    expect(
      () => expectFocusWalkGolden(walk, path),
      throwsA(isA<TestFailure>()),
    );
    handle.dispose();
  });

  testWidgets('announcements are recorded; a SnackBar alone is not one', (
    tester,
  ) async {
    final recorder = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: <Widget>[
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Snack'))),
                  child: const Text('snack'),
                ),
                TextButton(
                  onPressed: () => SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Load failed',
                    TextDirection.ltr,
                  ),
                  child: const Text('announce'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('snack'));
    await tester.pump();
    expect(recorder.messages, isEmpty);

    await tester.tap(find.text('announce'));
    await tester.pump();
    expect(recorder.messages, <String>['Load failed']);
  });
}
