// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _updates = true;
  String _verbosity = 'Normal';

  @override
  Widget build(BuildContext context) => CruxSettingsMasterDetail(
    categories: <CruxSettingsCategory>[
      CruxSettingsCategory(
        id: CruxSettingsCategoryId.general,
        icon: Icons.tune,
        title: 'General',
        content: CruxSettingsCard(
          children: <Widget>[
            SwitchListTile(
              title: const Text('Check for updates'),
              value: _updates,
              onChanged: (v) => setState(() => _updates = v),
            ),
            ListTile(
              title: const Text('Log verbosity'),
              trailing: DropdownButton<String>(
                value: _verbosity,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'Normal', child: Text('Normal')),
                  DropdownMenuItem(value: 'Verbose', child: Text('Verbose')),
                ],
                onChanged: (v) => setState(() => _verbosity = v!),
              ),
            ),
          ],
        ),
      ),
      const CruxSettingsCategory(
        id: CruxSettingsCategoryId.appearance,
        icon: Icons.palette_outlined,
        title: 'Appearance',
        content: CruxSettingsCard(children: <Widget>[Text('appearance-body')]),
      ),
      const CruxSettingsCategory(
        id: CruxSettingsCategoryId.shortcuts,
        icon: Icons.keyboard_outlined,
        title: 'Keyboard Shortcuts',
        content: CruxSettingsCard(children: <Widget>[Text('shortcuts-body')]),
      ),
    ],
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openCruxSettings(
                context,
                title: 'Settings',
                closeTooltip: 'Close',
                asDialog: true,
                bodyBuilder: (_) => const _Body(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening Settings puts focus on the selected category', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    expectFocusAnnounced(tester, named: 'General', context: 'Settings opened');
    final stop = describeFocus(tester);
    expect(stop.line, '[Settings grouping] General button selected');
    handle.dispose();
  });

  testWidgets('Tab visits the rail once, then the pane, never interleaved', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    // One rail stop (the selected tile), the pane's two controls, Close.
    expect(walk.stops.map((s) => s.line), <String>[
      'Check for updates switch on',
      'Log verbosity Normal button collapsed',
      'Close button',
      'General button selected',
    ]);
    handle.dispose();
  });

  testWidgets('arrow keys move the selection along the rail', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('appearance-body'), findsOneWidget);
    final stop = describeFocus(tester);
    expect(stop.name, 'Appearance');
    expect(stop.states, <String>['selected']);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('shortcuts-body'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(describeFocus(tester).name, 'General');
    handle.dispose();
  });

  testWidgets('each settings row is its own node, not the card name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    final walk = await walkFocus(tester);

    // Before rows were containers, the dropdown row's text became the name
    // of the card, and every switch in the card was announced inside it.
    expect(walk.transcript, isNot(contains('[Log verbosity')));
    expect(
      walk.stops.map((s) => s.line),
      containsAllInOrder(<String>[
        'Check for updates switch on',
        'Log verbosity Normal button collapsed',
        'Close button',
        'General button selected',
      ]),
    );
    handle.dispose();
  });

  testWidgets('Escape closes Settings despite the modal barrier', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byType(CruxSettingsDialogShell), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CruxSettingsDialogShell), findsNothing);
  });
}
