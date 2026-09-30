// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility guidelines for the command palette.
///
/// A suite-wide audit found ZERO accessibility tests
/// across nine repos while `flutter_test` ships four guideline matchers free.
///
/// The palette matters disproportionately here. It is the keyboard-first route
/// to every action in all four products, which makes it the surface a keyboard
/// or screen-reader user is *most* likely to live in — and it renders dense,
/// small, two-tone rows (label plus a muted shortcut badge) of exactly the kind
/// that fail contrast quietly.
///
/// Both themes, because contrast is a property of the colour pair rather than
/// the widget: a surface can pass in light and fail in dark, and the suite
/// ships both.
enum _DemoAction implements CruxAction {
  openFile(category: ActionCategory.file),
  zoomIn(category: ActionCategory.view),
  showAbout(category: ActionCategory.help);

  const _DemoAction({required this.category});

  @override
  final ActionCategory category;

  @override
  String get id => 'demo.$name';

  String get displayLabel => switch (this) {
    _DemoAction.openFile => 'Open File',
    _DemoAction.zoomIn => 'Zoom In',
    _DemoAction.showAbout => 'About',
  };
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('CommandPalette meets the guidelines (${brightness.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4650C8),
              brightness: brightness,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => CommandPalette.show<_DemoAction>(
                    context,
                    actions: _DemoAction.values,
                    labelFor: (a) => a.displayLabel,
                    onAction: (_) {},
                    hintText: 'Type to filter…',
                    noResultsLabel: 'No matching commands.',
                  ),
                  child: const Text('open palette'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open palette'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('the no-results state meets them too (${brightness.name})', (
      tester,
    ) async {
      // A separate widget tree, and the one a user reaches by mistyping — so
      // it deserves its own assertion rather than being assumed to inherit the
      // populated state's compliance.
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF4650C8),
              brightness: brightness,
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => CommandPalette.show<_DemoAction>(
                    context,
                    actions: _DemoAction.values,
                    labelFor: (a) => a.displayLabel,
                    onAction: (_) {},
                    hintText: 'Type to filter…',
                    noResultsLabel: 'No matching commands.',
                  ),
                  child: const Text('open palette'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open palette'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(textContrastGuideline));

      handle.dispose();
    });
  }
}
