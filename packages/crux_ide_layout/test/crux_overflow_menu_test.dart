// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> chosen;
  late List<CruxMenuEntry> entries;

  setUp(() {
    chosen = <String>[];
    entries = <CruxMenuEntry>[
      CruxMenuItem(label: 'Rename', onSelected: () => chosen.add('rename')),
      const CruxMenuDivider(),
      CruxMenuItem(
        label: 'Delete',
        destructive: true,
        onSelected: () => chosen.add('delete'),
      ),
      CruxMenuItem(
        label: 'Disabled',
        enabled: false,
        onSelected: () => chosen.add('disabled'),
      ),
    ];
  });

  Widget host() => MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
    ),
    home: Scaffold(
      body: Center(
        child: CruxContextMenuRegion(
          entries: entries,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 120, child: Text('Marker A')),
              CruxOverflowMenu(entries: entries, tooltip: 'More actions'),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('the visible overflow is "⋯", never "⋮"', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byTooltip('More actions'), findsOneWidget);
  });

  testWidgets('the button opens the commands and runs the chosen one', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(chosen, ['rename']);
  });

  testWidgets('a disabled command cannot be chosen', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disabled'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);
  });

  testWidgets('right-click on the row opens the same commands', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('Marker A'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(chosen, ['delete']);
  });

  testWidgets('Shift+F10 opens them from the keyboard', (tester) async {
    await tester.pumpWidget(host());
    // Focus the overflow button, inside the region.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('the Menu key opens them from the keyboard', (tester) async {
    await tester.pumpWidget(host());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('F10 without Shift is left alone', (tester) async {
    await tester.pumpWidget(host());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
  });

  group('trailingBuilder', () {
    late int builds;

    Widget badgeHost() {
      builds = 0;
      final badged = <CruxMenuEntry>[
        CruxMenuItem(
          label: 'Export',
          onSelected: () => chosen.add('export'),
          trailingBuilder: (context) {
            builds++;
            return const Text('Pro', key: ValueKey('badge'));
          },
        ),
      ];
      return MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Scaffold(
          body: Center(
            child: CruxContextMenuRegion(
              entries: badged,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 120, child: Text('Marker A')),
                  CruxOverflowMenu(entries: badged, tooltip: 'More actions'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('is not built until the menu opens', (tester) async {
      await tester.pumpWidget(badgeHost());
      expect(builds, 0);
      expect(find.byKey(const ValueKey('badge')), findsNothing);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(builds, greaterThan(0));
      expect(find.byKey(const ValueKey('badge')), findsOneWidget);
    });

    testWidgets('renders in the right-click menu and stays enabled', (
      tester,
    ) async {
      await tester.pumpWidget(badgeHost());
      await tester.tap(find.text('Marker A'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('badge')), findsOneWidget);
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(chosen, ['export']);
    });

    testWidgets('renders in the button menu at the same place', (tester) async {
      await tester.pumpWidget(badgeHost());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      final viaButton = tester.getRect(find.byKey(const ValueKey('badge')));
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      expect(chosen, ['export']);
      expect(
        viaButton.left,
        greaterThan(tester.getRect(find.text('Marker A')).left),
      );
    });

    testWidgets('semantics read the label, then the badge once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(badgeHost());
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.text('Export'));
      expect(node.label, 'Export\nPro');
      final item = tester.widget<PopupMenuItem<int>>(
        find.byType(PopupMenuItem<int>),
      );
      expect(item.enabled, isTrue);
      handle.dispose();
    });
  });
}
