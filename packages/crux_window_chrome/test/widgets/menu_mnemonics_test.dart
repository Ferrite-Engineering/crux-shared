// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/menu_mnemonics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MnemonicsController', () {
    test('visible reflects Alt-held OR latched menu mode', () {
      final c = MnemonicsController();
      addTearDown(c.dispose);

      expect(c.visible, isFalse);

      c.altHeld = true;
      expect(c.visible, isTrue);
      c.altHeld = false;
      expect(c.visible, isFalse);

      c.latch();
      expect(c.visible, isTrue);
      expect(c.latched, isTrue);

      c.unlatch();
      expect(c.visible, isFalse);
      expect(c.latched, isFalse);
    });

    test('notifies only when visibility actually changes', () {
      final c = MnemonicsController();
      addTearDown(c.dispose);
      var notifications = 0;
      c
        ..addListener(() => notifications++)
        ..altHeld =
            true // false -> true : notify
        ..latch() //       visible stays true : no notify
        ..altHeld =
            false // still latched -> visible stays true : no notify
        ..unlatch(); //    true -> false : notify

      expect(notifications, 2);
    });
  });

  group('MnemonicLabel', () {
    Widget wrap(MnemonicsController c) => MaterialApp(
      home: Scaffold(
        body: MnemonicsScope(
          notifier: c,
          child: const Center(child: MnemonicLabel('&File')),
        ),
      ),
    );

    testWidgets('renders plain text (no & and no split) when hidden', (
      tester,
    ) async {
      final c = MnemonicsController();
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      expect(find.text('File'), findsOneWidget);
      expect(find.textContaining('&'), findsNothing);
    });

    testWidgets('underlines the mnemonic char when visible', (tester) async {
      final c = MnemonicsController();
      addTearDown(c.dispose);
      await tester.pumpWidget(wrap(c));
      await tester.pump();

      c.latch();
      await tester.pump();

      // The accelerator char is rendered as its own (underlined) widget, so the
      // whole word is no longer a single Text and the lone 'F' appears.
      expect(find.text('File'), findsNothing);
      expect(find.text('F'), findsOneWidget);
      // The '&' marker is never shown.
      expect(find.textContaining('&'), findsNothing);
    });

    testWidgets('label with no & marker is always plain', (tester) async {
      final c = MnemonicsController()..latch();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MnemonicsScope(
              notifier: c,
              child: const Center(child: MnemonicLabel('WaveCrux')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('WaveCrux'), findsOneWidget);
    });
  });
}
