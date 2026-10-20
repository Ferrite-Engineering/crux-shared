// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements CruxRecentStore {
  _MemoryStore(this.entries);

  List<String> entries;

  @override
  Future<List<String>> load() async => entries;

  @override
  Future<void> save(List<String> next) async => entries = next;
}

void main() {
  late _MemoryStore store;
  late CruxRecentList list;
  late List<String> opened;

  setUp(() {
    store = _MemoryStore(<String>['/work/top.vcd', '/work/gone.vcd']);
    list = CruxRecentList(name: 'sectionRecent', store: (_) => store);
    opened = <String>[];
  });

  Widget host({required bool Function(String) exists}) => ProviderScope(
    overrides: [list.existsProvider.overrideWithValue(exists)],
    child: MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => CruxRecentListSection(
            list: list,
            strings: CruxRecentListStrings.of(context, CruxRecentKind.files),
            onOpen: (path) async {
              opened.add(path);
              return !path.contains('gone');
            },
          ),
        ),
      ),
    ),
  );

  testWidgets('rows show the name and path; a missing file is marked and '
      'stays removable', (tester) async {
    await tester.pumpWidget(host(exists: (p) => !p.contains('gone')));
    await tester.pumpAndSettle();
    expect(find.text('Recent files'), findsOneWidget);
    expect(find.text('top.vcd'), findsOneWidget);
    expect(find.text('/work/top.vcd'), findsOneWidget);
    expect(find.text('gone.vcd'), findsOneWidget);
    expect(find.text('File not found'), findsOneWidget);
    expect(find.byTooltip('Remove from Recent Files'), findsNWidgets(2));
    expect(find.text('Clear Recent Files'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from Recent Files').last);
    await tester.pumpAndSettle();
    expect(find.text('gone.vcd'), findsNothing);
    expect(store.entries, ['/work/top.vcd']);
  });

  testWidgets('opening a missing file drops it and says so', (tester) async {
    await tester.pumpWidget(host(exists: (p) => !p.contains('gone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gone.vcd'));
    await tester.pumpAndSettle();
    expect(opened, ['/work/gone.vcd']);
    expect(find.text('gone.vcd'), findsNothing);
    expect(
      find.text(
        'gone.vcd could not be opened and was removed from Recent '
        'Files.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Clear Recent empties the list and confirms', (tester) async {
    await tester.pumpWidget(host(exists: (_) => true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Recent Files'));
    await tester.pumpAndSettle();
    expect(find.text('No recent files'), findsOneWidget);
    expect(find.text('Clear Recent Files'), findsNothing);
    expect(find.text('Recent files cleared.'), findsOneWidget);
    expect(store.entries, isEmpty);
    // The confirmation leaves on its own.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Recent files cleared.'), findsNothing);
  });

  testWidgets('the keyboard reaches every row, its remove button and Clear', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(exists: (p) => !p.contains('gone')));
    await tester.pumpAndSettle();
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_recent_list_section.txt');
    handle.dispose();
  });
}
