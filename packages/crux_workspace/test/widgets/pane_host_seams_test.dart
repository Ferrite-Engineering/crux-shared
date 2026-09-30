// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Behavioural tests for the additive PaneHost seams (stackBuilder,
// splitLayoutBuilder, showTabBars, paneTrailingActionsBuilder).

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'v': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['v'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  late ProviderContainer root;
  late TabContainerManager tabsManager;
  late PaneContainerManager panesManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_pane_host_seams_');
    service = WorkspaceService<String>(
      codec: const _StringCodec(),
      directoryFactory: () async => tempDir,
      logger: (_) {},
    );
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
    root = ProviderContainer();
    tabsManager = TabContainerManager(rootContainer: root);
    panesManager = PaneContainerManager(rootContainer: root);
  });

  tearDown(() async {
    tabsManager.dispose();
    panesManager.dispose();
    root.dispose();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> hydrateWithTabs(int count) async {
    await root.read(provider.future);
    for (var i = 0; i < count; i++) {
      await root
          .read(provider.notifier)
          .openTab(displayName: 'Tab $i', payload: 't$i');
    }
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    PaneStackBuilder? stackBuilder,
    PaneSplitLayoutBuilder? splitLayoutBuilder,
    PaneTrailingActionsBuilder? paneTrailingActionsBuilder,
    PaneBorderBuilder? paneBorderBuilder,
    bool showTabBars = true,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: root,
        child: MaterialApp(
          home: Scaffold(
            body: PaneHost<String>(
              provider: provider,
              tabs: tabsManager,
              panes: panesManager,
              emptyCanvasContent: const Text('empty'),
              tabContentBuilder: (ctx, tab) =>
                  Text('content-${tab.displayName}'),
              stackBuilder: stackBuilder,
              splitLayoutBuilder: splitLayoutBuilder,
              paneTrailingActionsBuilder: paneTrailingActionsBuilder,
              paneBorderBuilder: paneBorderBuilder,
              showTabBars: showTabBars,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('paneBorderBuilder overrides the default pane border', (
    tester,
  ) async {
    await hydrateWithTabs(1);
    var sawActive = false;
    var sawUnsplit = false;
    await pumpHost(
      tester,
      paneBorderBuilder: (context, {required isActive, required isSplit}) {
        if (isActive) sawActive = true;
        if (!isSplit) sawUnsplit = true;
        return Border.all(
          color: const Color(0xFF112233),
          width: isActive ? 3 : 1,
        );
      },
    );
    expect(sawActive, isTrue);
    // A single-tab workspace renders one pane, so the builder is told the
    // workspace is un-split.
    expect(sawUnsplit, isTrue);
    final usesCustomBorder = tester
        .widgetList<Container>(find.byType(Container))
        .any((c) {
          final deco = c.decoration;
          return deco is BoxDecoration &&
              deco.border ==
                  Border.all(color: const Color(0xFF112233), width: 3);
        });
    expect(usesCustomBorder, isTrue);
  });

  testWidgets('stackBuilder is used in place of the default IndexedStack', (
    tester,
  ) async {
    await hydrateWithTabs(1);
    var called = false;
    await pumpHost(
      tester,
      stackBuilder: (index, children) {
        called = true;
        return Column(
          key: const ValueKey('customStack'),
          children: children,
        );
      },
    );
    expect(called, isTrue);
    expect(find.byKey(const ValueKey('customStack')), findsOneWidget);
  });

  testWidgets('default stack is a plain IndexedStack', (tester) async {
    await hydrateWithTabs(1);
    await pumpHost(tester);
    expect(find.byType(IndexedStack), findsOneWidget);
  });

  testWidgets('splitLayoutBuilder governs the multi-pane layout', (
    tester,
  ) async {
    await hydrateWithTabs(2);
    await root.read(provider.notifier).splitPaneRight();
    await pumpHost(
      tester,
      splitLayoutBuilder: (context, panes) => Column(
        key: const ValueKey('customSplit'),
        children: [for (final p in panes) Expanded(child: p)],
      ),
    );
    expect(find.byKey(const ValueKey('customSplit')), findsOneWidget);
  });

  testWidgets('showTabBars:false hides the tab strip but keeps content', (
    tester,
  ) async {
    await hydrateWithTabs(1);
    await pumpHost(tester, showTabBars: false);
    expect(find.byType(ViewerTabBar<String>), findsNothing);
    expect(find.text('content-Tab 0'), findsOneWidget);
  });

  testWidgets('showTabBars:true (default) renders the tab strip', (
    tester,
  ) async {
    await hydrateWithTabs(1);
    await pumpHost(tester);
    expect(find.byType(ViewerTabBar<String>), findsOneWidget);
  });

  testWidgets('paneTrailingActionsBuilder reaches the pane tab bar', (
    tester,
  ) async {
    await hydrateWithTabs(1);
    await pumpHost(
      tester,
      paneTrailingActionsBuilder: (context, pane) =>
          const Icon(Icons.bolt, key: ValueKey('paneTrailing')),
    );
    expect(find.byKey(const ValueKey('paneTrailing')), findsOneWidget);
  });

  testWidgets(
    'tabContainerFor / paneContainerFor override the managers when supplied',
    (tester) async {
      await hydrateWithTabs(1);
      final tabCalls = <TabId>[];
      final paneCalls = <PaneId>[];
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: MaterialApp(
            home: Scaffold(
              body: PaneHost<String>(
                provider: provider,
                emptyCanvasContent: const Text('empty'),
                tabContentBuilder: (ctx, tab) =>
                    Text('content-${tab.displayName}'),
                // No tabs/panes managers — resolution goes through the
                // callbacks, which delegate to the same managers here.
                tabContainerFor: (id) {
                  tabCalls.add(id);
                  return tabsManager.containerFor(id);
                },
                paneContainerFor: (id) {
                  paneCalls.add(id);
                  return panesManager.containerFor(id);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tabCalls, isNotEmpty);
      expect(paneCalls, isNotEmpty);
      expect(find.text('content-Tab 0'), findsOneWidget);
    },
  );
}
