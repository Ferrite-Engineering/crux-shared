// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<CruxSettingsCategory> _categories() => const [
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.appearance,
    icon: Icons.palette_outlined,
    title: 'Appearance',
    content: CruxSettingsCard(children: [Text('appearance-body')]),
  ),
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.fileHandling,
    icon: Icons.folder_outlined,
    title: 'Files',
    content: CruxSettingsCard(children: [Text('files-body')]),
  ),
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.shortcuts,
    icon: Icons.keyboard_outlined,
    title: 'Shortcuts',
    content: CruxSettingsCard(children: [Text('shortcuts-body')]),
  ),
];

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CruxSettingsMasterDetail(categories: _categories()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('wide (dual-pane)', () {
    testWidgets('rail + detail side by side, first category selected', (
      tester,
    ) async {
      await _pump(tester, size: const Size(900, 700));
      // Side-by-side divider present.
      expect(find.byType(VerticalDivider), findsOneWidget);
      // Rail lists all categories.
      for (final t in ['Appearance', 'Files', 'Shortcuts']) {
        expect(find.text(t), findsWidgets);
      }
      // Default selection shows the first category's body.
      expect(find.text('appearance-body'), findsOneWidget);
      expect(find.text('files-body'), findsNothing);
    });

    testWidgets('selecting a category swaps the detail content', (
      tester,
    ) async {
      await _pump(tester, size: const Size(900, 700));
      await tester.tap(find.text('Files').first);
      await tester.pumpAndSettle();
      expect(find.text('files-body'), findsOneWidget);
      expect(find.text('appearance-body'), findsNothing);
    });

    testWidgets('empty categories renders nothing without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CruxSettingsMasterDetail(categories: []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('self-scrolling detail (scrollableDetail: false)', () {
    testWidgets('hosts a ListView category without overflow or extra title', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CruxSettingsMasterDetail(
              scrollableDetail: false,
              showDetailTitle: false,
              categories: [
                CruxSettingsCategory(
                  id: CruxSettingsCategoryId.general,
                  icon: Icons.tune,
                  title: 'Long',
                  content: ListView(
                    children: [
                      for (var i = 0; i < 60; i++)
                        ListTile(title: Text('row $i')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No shell title (showDetailTitle:false) and the ListView renders.
      expect(find.text('row 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('narrow (list → detail)', () {
    testWidgets('shows list, opens detail on tap, returns via back', (
      tester,
    ) async {
      await _pump(tester, size: const Size(420, 800));
      // No side-by-side divider; detail body hidden until a row is tapped.
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('appearance-body'), findsNothing);

      await tester.tap(find.text('Files').first);
      await tester.pumpAndSettle();
      expect(find.text('files-body'), findsOneWidget);

      // In-pane back returns to the list.
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      expect(find.text('files-body'), findsNothing);
      expect(find.text('Appearance'), findsOneWidget);
    });
  });

  group('initial category', () {
    Future<void> pumpAt(
      WidgetTester tester, {
      required Size size,
      String? initialCategoryId,
      String? inherited,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget body = CruxSettingsMasterDetail(
        categories: _categories(),
        initialCategoryId: initialCategoryId,
      );
      if (inherited != null) {
        body = CruxSettingsInitialCategory(id: inherited, child: body);
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      await tester.pumpAndSettle();
    }

    testWidgets('opens on the named category when wide', (tester) async {
      await pumpAt(
        tester,
        size: const Size(900, 700),
        initialCategoryId: CruxSettingsCategoryId.shortcuts,
      );
      expect(find.text('shortcuts-body'), findsOneWidget);
      expect(find.text('appearance-body'), findsNothing);
    });

    testWidgets('opens straight into the detail when narrow', (tester) async {
      await pumpAt(
        tester,
        size: const Size(420, 800),
        initialCategoryId: CruxSettingsCategoryId.fileHandling,
      );
      expect(find.text('files-body'), findsOneWidget);
    });

    testWidgets('reads the category from an enclosing scope', (tester) async {
      await pumpAt(
        tester,
        size: const Size(900, 700),
        inherited: CruxSettingsCategoryId.fileHandling,
      );
      expect(find.text('files-body'), findsOneWidget);
    });

    testWidgets('ignores an id no category carries', (tester) async {
      await pumpAt(
        tester,
        size: const Size(900, 700),
        initialCategoryId: 'pro.nothing',
      );
      expect(find.text('appearance-body'), findsOneWidget);
    });
  });
}
