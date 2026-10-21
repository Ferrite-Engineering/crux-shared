// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a keyboard and a screen reader get from a tab on its own navigator:
// the window's toolbar stays in the semantics tree beside it, the tab's page
// does not take focus itself (the screen's primary region does), and a
// dialog on the tab's navigator takes focus, keeps Tab, leaves the pointer
// free for the rest of the window, and gives focus back when Escape closes
// it.

import 'dart:async';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

class _Window extends StatefulWidget {
  const _Window({required this.onSave});

  final VoidCallback onSave;

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> {
  final GlobalKey<NavigatorState> _tab = GlobalKey<NavigatorState>();
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    return CruxFocusRegionScope(
      restoreLostFocus: true,
      child: Column(
        children: <Widget>[
          CruxFocusRegion(
            semanticLabel: 'Toolbar',
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: 'Save',
                  onPressed: widget.onSave,
                  icon: const Icon(Icons.save),
                ),
                IconButton(
                  tooltip: 'Find',
                  onPressed: () {},
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            // Unnamed, so no semantics container of the test's own stands
            // between the tab's navigator and the toolbar painted before it.
            child: CruxFocusRegion(
              primary: true,
              child: _opened
                  ? CruxTabNavigatorHost(
                      navigatorKey: _tab,
                      builder: (context) => const _TabPage(),
                    )
                  : Center(
                      child: FilledButton(
                        autofocus: true,
                        onPressed: () => setState(() => _opened = true),
                        child: const Text('Open File'),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextButton(onPressed: () {}, child: const Text('First')),
        TextButton(
          onPressed: () => unawaited(
            showCruxDialog<void>(
              context: context,
              navigator: cruxTabNavigatorOf(context),
              barrierDismissible: false,
              builder: (dialogContext) => CruxDialog(
                title: 'Rename',
                content: const TextField(
                  decoration: InputDecoration(labelText: 'Name'),
                ),
                actions: <Widget>[
                  CruxDialogAction(
                    label: 'Cancel',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                  CruxDialogAction(
                    label: 'OK',
                    role: CruxDialogActionRole.primary,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

Future<void> _pumpOpened(WidgetTester tester, {VoidCallback? onSave}) async {
  tester.view
    ..physicalSize = const Size(1000, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: _Window(onSave: onSave ?? () {})),
    ),
  );
  await tester.pumpAndSettle();
  expectFocusAnnounced(tester, named: 'Open File', context: 'launch');
  // Enter on the focused button replaces it with the tab, the way opening a
  // file replaces a start screen.
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

Future<void> _openRename(WidgetTester tester) async {
  Focus.of(tester.element(find.text('Rename'))).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
  expect(find.byType(CruxDialog), findsOneWidget);
}

SemanticsFinder _tooltip(String tooltip) =>
    find.semantics.byPredicate((node) => node.tooltip == tooltip);

String? _focusedLabel(WidgetTester tester) => describeFocus(tester).name;

void main() {
  testWidgets('the tab page does not take focus; the primary region does, '
      'and it is announced', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpened(tester);
    // The page's own route scope, or the navigator's node, would be silent.
    expectFocusAnnounced(tester, named: 'First', context: 'tab opened');
    handle.dispose();
  }, variant: _desktop);

  testWidgets('the window around a tab navigator stays in the semantics tree, '
      'and one Tab cycle walks the whole window', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpened(tester);
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'tab open');
    expectFocusWalkGolden(walk, 'test/goldens/tab_navigator_host.txt');
    handle.dispose();
  }, variant: _desktop);

  testWidgets('a dialog on the tab navigator takes focus, keeps Tab inside, '
      'and hides only the tab behind it', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpened(tester);
    await _openRename(tester);

    expectFocusAnnounced(tester, context: 'dialog opened');
    expect(cruxFocusIsInPushedRoute(), isTrue);
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'tab dialog');
    expectFocusWalkGolden(walk, 'test/goldens/tab_navigator_dialog.txt');
    expect(
      walk.stops.map((s) => s.name),
      everyElement(isIn(<String>['Name', 'Cancel', 'OK'])),
    );

    // The window's toolbar is still heard; the tab's content behind the
    // dialog is not.
    expect(_tooltip('Save'), findsOne);
    expect(find.semantics.byLabel('First'), findsNothing);
    handle.dispose();
  }, variant: _desktop);

  testWidgets('the pointer still reaches the window around a tab dialog', (
    tester,
  ) async {
    var saved = 0;
    await _pumpOpened(tester, onSave: () => saved++);
    await _openRename(tester);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(saved, 1);
  }, variant: _desktop);

  testWidgets('Escape closes a tab dialog and returns focus to the control '
      'that opened it', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpOpened(tester);
    await _openRename(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CruxDialog), findsNothing);
    expect(_focusedLabel(tester), 'Rename');
    expect(cruxFocusIsInPushedRoute(), isFalse);
    expect(find.semantics.byLabel('First'), findsOne);
    handle.dispose();
  }, variant: _desktop);
}
