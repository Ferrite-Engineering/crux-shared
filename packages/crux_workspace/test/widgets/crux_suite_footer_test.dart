// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _label = 'A member of the EDACrux suite of products — edacrux.app';

void main() {
  group('CruxSuiteFooter', () {
    testWidgets('renders the whole localized sentence', (tester) async {
      await tester.pumpWidget(
        _wrap(CruxSuiteFooter(label: _label, onTap: () {})),
      );

      // One `Text.rich`, so the spans are asserted through the render object
      // rather than `find.text` on each fragment.
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan!.toPlainText(), _label);
    });

    testWidgets('underlines only the domain', (tester) async {
      await tester.pumpWidget(
        _wrap(CruxSuiteFooter(label: _label, onTap: () {})),
      );

      final span = tester.widget<Text>(find.byType(Text)).textSpan!;
      final underlined = <String>[];
      span.visitChildren((child) {
        if (child is TextSpan &&
            child.style?.decoration == TextDecoration.underline) {
          underlined.add(child.text ?? '');
        }
        return true;
      });
      expect(underlined, <String>['edacrux.app']);
    });

    testWidgets('the whole line is one tappable, focusable link', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(CruxSuiteFooter(label: _label, onTap: () => taps++)),
      );

      // Tapping the prose, not the domain, still follows the link — the
      // reason the row rather than the span carries the gesture.
      await tester.tap(find.byKey(CruxSuiteFooter.rowKey));
      expect(taps, 1);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(CruxSuiteFooter.rowKey)),
        // A link, and specifically not a button: the node carries `isLink`
        // alone, so a screen reader offers "follow link" rather than
        // announcing a control the welcome screen does not have.
        matchesSemantics(
          label: _label,
          isLink: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a translation missing the domain still follows', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          CruxSuiteFooter(
            label: 'EDACrux スイートの製品',
            onTap: () => taps++,
          ),
        ),
      );

      expect(
        tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText(),
        'EDACrux スイートの製品',
      );
      await tester.tap(find.byKey(CruxSuiteFooter.rowKey));
      expect(taps, 1);
    });

    testWidgets('EmptyCanvasState renders it last, below the actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 'Welcome to TestCrux',
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Open File…')),
            ],
            footer: CruxSuiteFooter(label: _label, onTap: () {}),
          ),
        ),
      );

      expect(find.byKey(CruxSuiteFooter.rowKey), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(CruxSuiteFooter.rowKey)).dy,
        greaterThan(tester.getBottomLeft(find.text('Open File…')).dy),
      );
    });

    testWidgets('EmptyCanvasState omits the slot when null', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyCanvasState(title: 'Welcome to TestCrux')),
      );
      expect(find.byKey(CruxSuiteFooter.rowKey), findsNothing);
    });

    testWidgets("the footer does not steal the canvas's initial focus", (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EmptyCanvasState(
            title: 'Welcome to TestCrux',
            primaryActions: [
              FilledButton(onPressed: () {}, child: const Text('Open File…')),
            ],
            footer: CruxSuiteFooter(label: _label, onTap: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Walked from the focused node outwards rather than matched against
      // the button's `Focus`: a button's focus node is created internally, so
      // the `Focus` widget in the tree carries a null `focusNode` field.
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      expect(focusedContext, isNotNull);
      var withinPrimaryAction = false;
      focusedContext!.visitAncestorElements((element) {
        if (element.widget is FilledButton) {
          withinPrimaryAction = true;
          return false;
        }
        return true;
      });
      expect(
        withinPrimaryAction,
        isTrue,
        reason:
            'the primary action must keep initial focus; a screen reader '
            'landing on the suite link would announce an advertisement as '
            'the first thing in the window',
      );
    });
  });
}
