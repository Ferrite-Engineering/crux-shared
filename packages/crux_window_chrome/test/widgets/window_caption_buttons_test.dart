// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/window_caption_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('WindowCaptionButtons', () {
    Widget wrap({Brightness brightness = Brightness.dark}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: const Scaffold(
        body: WindowCaptionButtons(),
      ),
    );

    testWidgets('renders minimize, maximize and close caption buttons', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      // Three caption buttons: minimize, maximize (default, not maximized),
      // close. (No live window_manager channel in tests, so isMaximized()
      // stays at its swallowed default and the maximize glyph is shown.)
      expect(find.byType(WindowCaptionButton), findsNWidgets(3));
    });

    testWidgets('builds without a live window_manager channel (no exception)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('is exactly WindowCaptionButtons.width wide', (tester) async {
      // The title bar sizes the menu allowance from this constant, so it has
      // to be the real laid-out width, not an estimate.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Spacer(),
                WindowCaptionButtons(),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byType(WindowCaptionButtons)).width,
        WindowCaptionButtons.width,
      );
      for (final element in find.byType(WindowCaptionButton).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).width,
          WindowCaptionButtons.buttonWidth,
        );
      }
    });

    testWidgets('adapts caption glyph brightness to the theme', (tester) async {
      await tester.pumpWidget(wrap(brightness: Brightness.light));
      await tester.pump();
      final button = tester.widget<WindowCaptionButton>(
        find.byType(WindowCaptionButton).first,
      );
      expect(button.brightness, Brightness.light);
    });
  });
}
