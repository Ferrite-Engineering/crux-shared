// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The default pane stack used to be a bare [IndexedStack], which
/// builds and mounts **every** tab's content tree. In these products a tab is
/// a waveform canvas / schematic / netlist view, so restoring an eight-tab
/// session constructed eight of them before the user looked at any.
///
/// The default is now lazy-with-keep-alive: a tab's subtree is built the first
/// time it becomes active and stays mounted afterwards. These tests pin both
/// halves of that contract — laziness AND state retention — because dropping
/// either one is a plausible regression.

class _StringCodec extends WorkspaceCodec<String> {
  const _StringCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String p) => {'value': p};

  @override
  String payloadFromJson(Map<String, Object?> j) => j['value'] as String? ?? '';

  @override
  String displayNameFor(String p) => p;
}

/// Per-tab content that records every build and holds state, so the test can
/// tell "never built" from "built and kept alive".
class _CountingContent extends StatefulWidget {
  const _CountingContent({required this.label, required this.builds});

  final String label;
  final Map<String, int> builds;

  @override
  State<_CountingContent> createState() => _CountingContentState();
}

class _CountingContentState extends State<_CountingContent> {
  int localState = 0;

  @override
  void initState() {
    super.initState();
    widget.builds[widget.label] = (widget.builds[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

// Test-local helper; the private State type is exactly what we need to touch.
/// Resolves the live [_CountingContentState] for the tab labelled [label].
// ignore: library_private_types_in_public_api
_CountingContentState stateFor(WidgetTester tester, String label) =>
    tester.state<_CountingContentState>(
      find.byWidgetPredicate(
        (w) => w is _CountingContent && w.label == label,
      ),
    );

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  late TabContainerManager tabs;
  late PaneContainerManager panes;
  late Map<String, int> builds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_lazy_stack_');
    builds = <String, int>{};
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
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    PaneStackBuilder? stackBuilder,
  }) async {
    // The container managers MUST be parented to the container that hosts the
    // workspace provider: the per-pane scope PaneHost mounts is a child of the
    // manager's root, and the tab bar resolves `provider` through it. Parenting
    // them to an unrelated root gives the bar a second, empty workspace whose
    // pane ids don't match — which is what the products' bootstrap avoids by
    // construction.
    final container = ProviderContainer();
    tabs = TabContainerManager(rootContainer: container);
    panes = PaneContainerManager(rootContainer: container);
    addTearDown(tabs.dispose);
    addTearDown(panes.dispose);
    await container.read(provider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PaneHost<String>(
              provider: provider,
              tabs: tabs,
              panes: panes,
              stackBuilder: stackBuilder,
              emptyCanvasContent: const Text('empty'),
              tabContentBuilder: (ctx, tab) =>
                  _CountingContent(label: tab.displayName, builds: builds),
            ),
          ),
        ),
      ),
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('only the active tab’s content is built', (tester) async {
    final container = await pumpHost(tester);
    final notifier = container.read(provider.notifier);
    await notifier.openTab(displayName: 'A', payload: 'a');
    await notifier.openTab(displayName: 'B', payload: 'b');
    await notifier.openTab(displayName: 'C', payload: 'c');
    await tester.pumpAndSettle();

    // C is active (openTab activates). A and B have never been looked at.
    expect(builds.containsKey('C'), isTrue);
    expect(
      builds.containsKey('A'),
      isFalse,
      reason: 'an unvisited tab’s content tree must not be constructed',
    );
    expect(builds.containsKey('B'), isFalse);
  });

  testWidgets('activating a tab builds it, and it stays alive after', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final notifier = container.read(provider.notifier);
    final a = await notifier.openTab(displayName: 'A', payload: 'a');
    final b = await notifier.openTab(displayName: 'B', payload: 'b');
    await tester.pumpAndSettle();

    await notifier.setActiveTab(a);
    await tester.pumpAndSettle();
    expect(builds['A'], 1);

    // Switching away and back must NOT rebuild A from scratch — that is the
    // state-retention guarantee IndexedStack provided and we must not lose.
    stateFor(tester, 'A').localState = 99;

    await notifier.setActiveTab(b);
    await tester.pumpAndSettle();
    await notifier.setActiveTab(a);
    await tester.pumpAndSettle();

    expect(builds['A'], 1, reason: 'A was kept alive, not rebuilt');
    expect(
      stateFor(tester, 'A').localState,
      99,
      reason: 'a visited tab retains its State across tab switches',
    );
  });

  testWidgets('every tab eventually visited is built exactly once', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final notifier = container.read(provider.notifier);
    final a = await notifier.openTab(displayName: 'A', payload: 'a');
    final b = await notifier.openTab(displayName: 'B', payload: 'b');
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await notifier.setActiveTab(a);
      await tester.pumpAndSettle();
      await notifier.setActiveTab(b);
      await tester.pumpAndSettle();
    }

    expect(builds['A'], 1);
    expect(builds['B'], 1);
  });

  testWidgets('per-tab content is wrapped in a RepaintBoundary', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'A', payload: 'a');
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('A'),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
      reason: 'a tab’s painting must be isolated from its keep-alive siblings',
    );
  });

  testWidgets('a custom stackBuilder still takes precedence', (tester) async {
    var stackBuilderCalls = 0;
    final container = await pumpHost(
      tester,
      stackBuilder: (index, children) {
        stackBuilderCalls++;
        // An eager stack: proves the override is genuinely in control of the
        // mounting policy, not just decorating the default.
        return Stack(children: children);
      },
    );
    final notifier = container.read(provider.notifier);
    await notifier.openTab(displayName: 'A', payload: 'a');
    await notifier.openTab(displayName: 'B', payload: 'b');
    await tester.pumpAndSettle();

    expect(stackBuilderCalls, greaterThan(0));
    expect(
      builds.keys.toSet(),
      {'A', 'B'},
      reason: 'the product’s stack decides what gets mounted',
    );
  });

  testWidgets('children carry a unique key on the default path too', (
    tester,
  ) async {
    // The stackBuilder contract promises every child has a unique non-null
    // ValueKey. The default path used to omit it, so a lazy stack could not
    // track slots across a reorder.
    final container = await pumpHost(tester);
    final notifier = container.read(provider.notifier);
    final a = await notifier.openTab(displayName: 'A', payload: 'a');
    await notifier.openTab(displayName: 'B', payload: 'b');
    await tester.pumpAndSettle();

    // A is the inactive slot, so it is offstage inside the IndexedStack — the
    // key still has to be there, which is what a lazy stack needs to track it.
    expect(
      find.byKey(ValueKey('paneContent_${a.value}'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('closing a tab does not resurrect a stale slot', (tester) async {
    final container = await pumpHost(tester);
    final notifier = container.read(provider.notifier);
    final a = await notifier.openTab(displayName: 'A', payload: 'a');
    final b = await notifier.openTab(displayName: 'B', payload: 'b');
    await notifier.setActiveTab(a);
    await tester.pumpAndSettle();
    expect(builds['A'], 1);

    await notifier.closeTab(a);
    await tester.pumpAndSettle();

    // B becomes active and is built for the first time; A is gone entirely.
    expect(builds['B'], 1);
    expect(find.text('A'), findsNothing);
    expect(await notifier.future, isNotNull);
    expect((await notifier.future).tabs.single.id, b);
  });
}
