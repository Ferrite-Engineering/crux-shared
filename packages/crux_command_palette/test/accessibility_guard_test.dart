// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///
/// Every action is bound to a shortcut. Without bindings the palette renders
/// no shortcut hints at all, and the contrast guideline then passes over a
/// palette that is missing its most muted text. With all three bound, the hint
/// is on screen on the selected row and on unselected rows alike.
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

const _bindings = <_DemoAction, ShortcutActivator?>{
  _DemoAction.openFile: SingleActivator(LogicalKeyboardKey.keyO, meta: true),
  _DemoAction.zoomIn: SingleActivator(LogicalKeyboardKey.equal, meta: true),
  _DemoAction.showAbout: SingleActivator(
    LogicalKeyboardKey.keyK,
    meta: true,
    shift: true,
  ),
};

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A theme shaped like the products' own.
///
/// Every product replaces Material's `outline` with its border colour, which
/// is far dimmer than the seeded default: a hairline is meant to recede. Text
/// painted in the seeded `outline` is close to readable, so a guard built on a
/// plain seeded scheme understates the defect its users would see. These are
/// border colours of the kind the products ship, one per brightness.
ThemeData _productLikeTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF4650C8),
          brightness: brightness,
        ).copyWith(
          outline: isDark ? const Color(0xFF2C2C38) : const Color(0xFFCCCCD8),
        ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('CommandPalette meets the guidelines (${brightness.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: _productLikeTheme(brightness),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => CommandPalette.show<_DemoAction>(
                    context,
                    actions: _DemoAction.values,
                    labelFor: (a) => a.displayLabel,
                    onAction: (_) {},
                    bindings: _bindings,
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

      // Flutter's contrast guideline judges a semantics node by the two most
      // common colours inside its rectangle. A palette row is one node that
      // holds a label and a hint, so the label decides the verdict and the
      // hint is never measured. Each hint is therefore measured here, against
      // the background of its own row.
      final surface = Theme.of(
        tester.element(find.byType(TextField)),
      ).colorScheme.surface;
      var selectedRows = 0;
      for (final activator in _bindings.values) {
        final hint = find.text(defaultShortcutActivatorLabel(activator));
        expect(hint, findsOneWidget);
        final row = tester.widget<Container>(
          find.ancestor(of: hint, matching: find.byType(Container)).first,
        );
        final rowColor = row.color;
        if (rowColor != null) selectedRows++;
        final background = rowColor == null
            ? surface
            : Color.alphaBlend(rowColor, surface);
        final foreground = tester.widget<Text>(hint).style!.color!;
        final rowKind = rowColor == null ? 'an unselected' : 'the selected';
        expect(
          _contrast(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'the shortcut hint on $rowKind row must read as text',
        );
      }
      // One highlighted row and two plain ones, so both colour pairs were
      // measured.
      expect(selectedRows, 1);

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
          theme: _productLikeTheme(brightness),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => CommandPalette.show<_DemoAction>(
                    context,
                    actions: _DemoAction.values,
                    labelFor: (a) => a.displayLabel,
                    onAction: (_) {},
                    bindings: _bindings,
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
