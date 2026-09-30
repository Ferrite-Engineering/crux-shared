// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _canvas({
  bool claimInitialFocus = true,
  Widget? above,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: <Widget>[
        ?above,
        Expanded(
          child: EmptyCanvasState(
            title: 'Welcome to NetCrux',
            claimInitialFocus: claimInitialFocus,
            recentFilesSection: TextButton(
              onPressed: () {},
              child: const Text('adder4.netcrux-project'),
            ),
            primaryActions: <Widget>[
              FilledButton(onPressed: () {}, child: const Text('Open Project')),
              OutlinedButton(onPressed: () {}, child: const Text('Open Files')),
            ],
          ),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('launch focus lands on the first primary action, announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_canvas());
    await tester.pump();

    expectFocusAnnounced(tester, named: 'Open Project', context: 'launch');
    expect(
      describeFocus(tester).line,
      '[Welcome to NetCrux grouping] Open Project button',
    );
    handle.dispose();
  });

  testWidgets('the title is a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_canvas());
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Welcome to NetCrux')),
      matchesSemantics(label: 'Welcome to NetCrux', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('a focused control elsewhere keeps its focus', (tester) async {
    await tester.pumpWidget(
      _canvas(
        above: const TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: 'Search'),
        ),
      ),
    );
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>(),
      isNotNull,
    );
  });

  testWidgets('claiming focus can be switched off', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_canvas(claimInitialFocus: false));
    await tester.pump();

    expect(() => expectFocusAnnounced(tester), throwsA(isA<TestFailure>()));
    handle.dispose();
  });
}
