// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/menu_mnemonics.dart';
import 'package:crux_window_chrome/src/widgets/mnemonic_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MnemonicMenuBar', () {
    Widget wrap() => MaterialApp(
      home: Scaffold(
        body: MnemonicMenuBar(
          entries: [
            MnemonicMenuEntry(
              acceleratorLabel: '&File',
              menuChildren: [
                MenuItemButton(
                  onPressed: () {},
                  child: const Text('OpenItem'),
                ),
              ],
            ),
            MnemonicMenuEntry(
              acceleratorLabel: '&View',
              menuChildren: [
                MenuItemButton(
                  onPressed: () {},
                  child: const Text('ZoomItem'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    Future<void> altTap(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    testWidgets('renders one MnemonicLabel per top-level menu', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.byType(MnemonicLabel), findsNWidgets(2));
      // Dropdowns are closed initially.
      expect(find.text('OpenItem'), findsNothing);
    });

    testWidgets('Alt+letter opens the matching menu', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      expect(find.text('OpenItem'), findsOneWidget);
    });

    testWidgets('tap Alt then a bare letter opens that menu (menu mode)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await altTap(tester); // enter menu mode
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();

      expect(find.text('ZoomItem'), findsOneWidget);
    });

    testWidgets('Esc exits menu mode (a later bare letter no longer opens)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await altTap(tester); // menu mode on
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Not in menu mode anymore: a bare 'F' must NOT open the File menu.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(find.text('OpenItem'), findsNothing);
    });

    testWidgets('without menu mode, a bare letter does not open a menu', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(find.text('OpenItem'), findsNothing);
    });

    testWidgets('Alt+click does not latch menu mode', (tester) async {
      // Alt+click is a real gesture — WaveCrux authors an annotation with it.
      // Only *keys* used to cancel the bare-tap latch, so Alt+click looked
      // exactly like tapping Alt alone: down, a click the state machine could
      // not see, up with nothing recorded between. Menu mode latched, and the
      // first letter the user typed into the editor that had just opened hit a
      // mnemonic, opened that menu and stole the focus mid-word.
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.tapAt(const Offset(400, 400));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();

      // Latched mode would make a bare 'F' open the File menu.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(
        find.text('OpenItem'),
        findsNothing,
        reason: 'a pointer press during Alt is not a bare Alt tap',
      );
    });

    testWidgets('a focused text field keeps its letters', (tester) async {
      // The defence that holds however the Alt state got there. Typing into a
      // text field must never open a menu, so this covers the cases the latch
      // fix cannot — a platform that drops an Alt key-up, a window regaining
      // focus mid-chord.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                MnemonicMenuBar(
                  entries: [
                    MnemonicMenuEntry(
                      acceleratorLabel: '&File',
                      menuChildren: [
                        MenuItemButton(
                          onPressed: () {},
                          child: const Text('OpenItem'),
                        ),
                      ],
                    ),
                  ],
                ),
                const TextField(),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Menu mode latched by a genuine bare Alt tap — the letter must still go
      // to the field the user is typing into.
      await altTap(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();

      expect(find.text('OpenItem'), findsNothing);
    });
  });
}
