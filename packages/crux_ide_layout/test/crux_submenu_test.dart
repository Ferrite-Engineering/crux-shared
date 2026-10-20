// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> chosen;

  List<CruxMenuEntry> entries({List<CruxMenuEntry>? targets}) =>
      <CruxMenuEntry>[
        CruxMenuItem(label: 'Rename', onSelected: () => chosen.add('rename')),
        CruxSubmenu(
          key: const ValueKey('sendTo'),
          label: 'Send to',
          tooltip: 'Start a peer first',
          entries:
              targets ??
              <CruxMenuEntry>[
                CruxMenuItem(
                  label: 'WaveCrux',
                  onSelected: () => chosen.add('wavecrux'),
                ),
                CruxMenuItem(
                  label: 'NetCrux',
                  onSelected: () => chosen.add('netcrux'),
                ),
              ],
        ),
      ];

  setUp(() => chosen = <String>[]);

  Widget host(List<CruxMenuEntry> menu) => MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
    ),
    home: Scaffold(
      body: Center(
        child: CruxOverflowMenu(entries: menu, tooltip: 'More actions'),
      ),
    ),
  );

  testWidgets('choosing a submenu opens its entries beside it', (
    tester,
  ) async {
    await tester.pumpWidget(host(entries()));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    final parentRow = tester.getRect(find.text('Send to'));

    await tester.tap(find.text('Send to'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    expect(find.text('WaveCrux'), findsOneWidget);
    // The second menu opens level with the row that opened it.
    expect(
      (tester.getRect(find.text('WaveCrux')).top - parentRow.top).abs(),
      lessThan(parentRow.height * 2),
    );

    await tester.tap(find.text('NetCrux'));
    await tester.pumpAndSettle();
    expect(chosen, ['netcrux']);
  });

  testWidgets('Right arrow and Enter open a submenu from the keyboard', (
    tester,
  ) async {
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.enter,
    ]) {
      await tester.pumpWidget(host(entries()));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      // Down twice: the first lands on Rename, the second on the submenu.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(find.text('WaveCrux'), findsOneWidget, reason: '$key');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    expect(chosen, isEmpty);
  });

  testWidgets('a submenu with no entries is disabled and explains why', (
    tester,
  ) async {
    await tester.pumpWidget(host(entries(targets: const [])));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<int>>(
      find.byKey(const ValueKey('sendTo')),
    );
    expect(item.enabled, isFalse);
    expect(find.byTooltip('Start a peer first'), findsOneWidget);
    await tester.tap(find.text('Send to'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('WaveCrux'), findsNothing);
  });

  testWidgets('a menu item tooltip is shown on hover, not spoken', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(<CruxMenuEntry>[
        CruxMenuItem(
          label: 'Export',
          tooltip: 'Open a file first',
          enabled: false,
          onSelected: () {},
        ),
      ]),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open a file first'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Open a file first')),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('cruxTextInputFocused is true only inside a text field', (
    tester,
  ) async {
    final field = FocusNode();
    final button = FocusNode();
    addTearDown(field.dispose);
    addTearDown(button.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: field),
              ElevatedButton(
                focusNode: button,
                onPressed: () {},
                child: const Text('Go'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(cruxTextInputFocused(), isFalse);
    field.requestFocus();
    await tester.pump();
    expect(cruxTextInputFocused(), isTrue);
    button.requestFocus();
    await tester.pump();
    expect(cruxTextInputFocused(), isFalse);
  });
}
