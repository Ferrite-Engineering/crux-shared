// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// A per-tab provider: every tab container overrides it.
final _counterProvider = NotifierProvider<_Counter, int>(_Counter.new);

/// The tab content: shows the per-tab count, and a button that opens a
/// dialog on the tab's own navigator which watches the same count.
class _TabContent extends ConsumerWidget {
  const _TabContent({required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_counterProvider);
    return Column(
      children: [
        Text('$label content $count'),
        ElevatedButton(
          onPressed: () => Navigator.of(context).push<void>(
            DialogRoute<void>(
              context: context,
              builder: (_) => const _CountDialog(),
            ),
          ),
          child: Text('Open $label'),
        ),
      ],
    );
  }
}

class _CountDialog extends ConsumerWidget {
  const _CountDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(_counterProvider);
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('dialog sees ${ref.watch(tabIdProvider).value} $count'),
          TextButton(
            onPressed: () => ref.read(_counterProvider.notifier).bump(),
            child: const Text('Bump'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_tab_nav_');
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

  Future<(ProviderContainer, TabContainerManager)> pumpHost(
    WidgetTester tester, {
    CruxTabNavigators? navigators,
  }) async {
    final container = ProviderContainer();
    final tabs = TabContainerManager(
      rootContainer: container,
      overridesFactory: (_) => [_counterProvider.overrideWith(_Counter.new)],
    );
    final panes = PaneContainerManager(rootContainer: container);
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
              tabNavigators: navigators,
              emptyCanvasContent: const Text('empty'),
              tabContentBuilder: (ctx, tab) =>
                  _TabContent(label: tab.displayName),
            ),
          ),
        ),
      ),
    );
    addTearDown(container.dispose);
    return (container, tabs);
  }

  testWidgets('without tabNavigators the tab content has no navigator of '
      'its own', (tester) async {
    final (container, _) = await pumpHost(tester);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'A', payload: 'a');
    await tester.pumpAndSettle();
    expect(find.text('A content 0'), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets('a dialog on the tab navigator reads the tab scope, and a '
      'per-tab write while it is open rebuilds both without an error', (
    tester,
  ) async {
    final navigators = CruxTabNavigators();
    final (container, _) = await pumpHost(tester, navigators: navigators);
    final a = await container
        .read(provider.notifier)
        .openTab(displayName: 'A', payload: 'a');
    await tester.pumpAndSettle();
    expect(navigators.navigatorFor(a), isNotNull);
    expect(
      cruxTabNavigatorOf(tester.element(find.text('A content 0'))),
      same(navigators.navigatorFor(a)),
    );

    await tester.tap(find.text('Open A'));
    await tester.pumpAndSettle();
    expect(find.text('dialog sees ${a.value} 0'), findsOneWidget);

    // The write that fanned out to a second scope over the same container
    // and asserted mid-build; with one scope there is nothing to fan out.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Bump'));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('dialog sees ${a.value} 3'), findsOneWidget);
    expect(find.text('A content 3'), findsOneWidget);
  });

  testWidgets('a closed tab is forgotten', (tester) async {
    final navigators = CruxTabNavigators();
    final (container, _) = await pumpHost(tester, navigators: navigators);
    final notifier = container.read(provider.notifier);
    final a = await notifier.openTab(displayName: 'A', payload: 'a');
    await notifier.openTab(displayName: 'B', payload: 'b');
    await notifier.setActiveTab(a);
    await tester.pumpAndSettle();
    expect(navigators.navigatorFor(a), isNotNull);
    await notifier.closeTab(a);
    await tester.pumpAndSettle();
    expect(navigators.navigatorFor(a), isNull);
  });

  testWidgets('Tab leaves the tab content for the tab bar: the nested '
      'navigator is not a Tab trap', (tester) async {
    final handle = tester.ensureSemantics();
    final navigators = CruxTabNavigators();
    final (container, _) = await pumpHost(tester, navigators: navigators);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'A', payload: 'a');
    await tester.pumpAndSettle();
    final walk = await walkFocus(tester);
    expect(walk.transcript, contains('Open A'));
    // Something outside the tab content (the tab bar) is a stop too.
    expect(
      walk.stops.where((stop) => !stop.line.contains('Open A')),
      isNotEmpty,
    );
    handle.dispose();
  });
}
