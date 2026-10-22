// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Closing the palette must leave keyboard focus somewhere an app-level
/// shortcut can hear it, so a chord pressed straight afterwards still fires.
/// An app's Toggle Theme chord used to do nothing after the palette was
/// dismissed until the user clicked into the window.

enum _Action implements CruxAction {
  first(category: ActionCategory.file),
  second(category: ActionCategory.view);

  const _Action({required this.category});

  @override
  final ActionCategory category;

  @override
  String get id => 'demo.$name';
}

const SingleActivator _chord = SingleActivator(
  LogicalKeyboardKey.keyK,
  control: true,
);

void main() {
  var chords = 0;
  late List<_Action> dispatched;

  setUp(() {
    chords = 0;
    dispatched = <_Action>[];
  });

  /// Shortcuts above the navigator, as the products have them, over a page
  /// with one text field.
  Widget app({void Function(BuildContext, _Action)? onAction}) => MaterialApp(
    builder: (context, child) => CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{_chord: () => chords++},
      child: child!,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Column(
          children: <Widget>[
            const TextField(key: Key('field')),
            TextButton(
              onPressed: () => unawaited(
                CommandPalette.show<_Action>(
                  context,
                  actions: _Action.values,
                  labelFor: (a) => a.name,
                  onAction: (a) {
                    dispatched.add(a);
                    onAction?.call(context, a);
                  },
                  hintText: 'Type to filter',
                  noResultsLabel: 'No matches',
                ),
              ),
              child: const Text('Open palette'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> pressChord(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  /// Focuses the field, then opens the palette from the button's callback, the
  /// way a shortcut opens it with focus still on the field.
  Future<FocusNode?> openFromField(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;
    expect(before, isNotNull);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette<_Action>), findsOneWidget);
    return before;
  }

  testWidgets('a chord fires after Escape closes the palette', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('field')));
    await pressChord(tester);
    expect(chords, 1, reason: 'the chord works before the palette opens');

    await openFromField(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette<_Action>), findsNothing);

    await pressChord(tester);
    expect(chords, 2);
  });

  testWidgets('focus goes back to the field that held it', (tester) async {
    await tester.pumpWidget(app());
    final before = await openFromField(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus, before);
  });

  testWidgets('a chord fires after focus dropped to the window root and the '
      'scrim closed the palette', (tester) async {
    await tester.pumpWidget(app());
    final before = await openFromField(tester);

    for (var i = 0; i < 8; i++) {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus, FocusManager.instance.rootScope);
    await tester.tapAt(const Offset(2, 590));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette<_Action>), findsNothing);

    expect(FocusManager.instance.primaryFocus, before);
    await pressChord(tester);
    expect(chords, 1);
  });

  testWidgets("an action that opened another dialog keeps that dialog's "
      'focus', (tester) async {
    await tester.pumpWidget(
      app(
        onAction: (context, _) => unawaited(
          showCruxDialog<void>(
            context: context,
            builder: (_) => CruxDialog(
              title: 'After',
              content: const Text('After body'),
              actions: <Widget>[
                CruxDialogAction(label: 'Done', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    final before = await openFromField(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(dispatched, <_Action>[_Action.first]);
    expect(find.byType(CommandPalette<_Action>), findsNothing);
    expect(find.text('After body'), findsOneWidget);
    expect(cruxFocusIsInPushedRoute(), isTrue);
    expect(FocusManager.instance.primaryFocus, isNot(before));
  });
}
