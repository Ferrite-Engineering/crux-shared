// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SizedBox(width: width, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CruxPolicyLockNote', () {
    testWidgets('renders the host-supplied sentence and a lock glyph', (
      tester,
    ) async {
      await _pump(
        tester,
        const CruxPolicyLockNote(
          message: "Locked by your organization's policy file.",
        ),
      );

      // The package holds no strings — every word comes from the host's ARB,
      // which is what lets one widget read identically in four products.
      expect(
        find.text("Locked by your organization's policy file."),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('appends the source on its own line when given one', (
      tester,
    ) async {
      await _pump(
        tester,
        const CruxPolicyLockNote(
          message: 'Locked by policy.',
          source: '/Library/Application Support/EDACrux/.crux-policy.json',
        ),
      );

      expect(
        find.text(
          'Locked by policy.\n'
          '/Library/Application Support/EDACrux/.crux-policy.json',
        ),
        findsOneWidget,
      );
    });

    testWidgets('omits the source line entirely when there is none', (
      tester,
    ) async {
      await _pump(tester, const CruxPolicyLockNote(message: 'Locked.'));

      final text = tester.widget<Text>(find.byType(Text));
      // Not an empty second line: a trailing newline would render as a gap
      // under the sentence and read as a missing value.
      expect(text.data, 'Locked.');
      expect(text.data, isNot(contains('\n')));
    });

    testWidgets('takes its colour from the theme, not a literal', (
      tester,
    ) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A3B12)),
      );
      await _pump(
        tester,
        const CruxPolicyLockNote(message: 'Locked.'),
        theme: theme,
      );

      final expected = theme.colorScheme.onSurfaceVariant;
      expect(
        tester.widget<Icon>(find.byIcon(Icons.lock_outline)).color,
        expected,
      );
      expect(
        tester.widget<Text>(find.byType(Text)).style?.color,
        expected,
        reason: 'the note must recede against whatever theme the host runs',
      );
    });

    testWidgets('a long message wraps instead of overflowing', (tester) async {
      await _pump(
        tester,
        const CruxPolicyLockNote(
          message:
              'Locked by your organization policy file, which was supplied by '
              'your IT department and cannot be changed from inside the '
              'application.',
          source: '/etc/edacrux/.crux-policy.json',
        ),
        width: 220,
      );

      // A settings pane is narrow and a policy path is long; the Expanded is
      // what keeps this an explanation rather than a yellow-and-black bar.
      expect(tester.takeException(), isNull);
    });

    testWidgets('aligns the glyph to the first line of a wrapped message', (
      tester,
    ) async {
      await _pump(
        tester,
        const CruxPolicyLockNote(
          message:
              'Locked by your organization policy file and not editable '
              'here, ask your IT department.',
        ),
        width: 200,
      );

      final icon = tester.getTopLeft(find.byIcon(Icons.lock_outline));
      final text = tester.getTopLeft(find.byType(Text));
      // `CrossAxisAlignment.start`: a centred glyph beside three wrapped lines
      // floats away from the sentence it belongs to.
      expect(
        (icon.dy - text.dy).abs(),
        lessThan(8),
        reason: 'the lock must sit with the first line, not the block centre',
      );
    });
  });
}
