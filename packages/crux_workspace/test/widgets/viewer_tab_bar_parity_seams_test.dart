// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Behavioural tests for the parity seams added in 0.4.0 so a host product can
// reproduce a richer tab strip without forking the widget:
//   - reorderTabInPane (correct pane-local → global index in a split)
//   - ViewerTabBarStrings.closeTabTooltipFor (name-bearing close tooltip)
//   - ViewerTabBar.useDragHandle (whole-chip drag + leading insertion slot)
//   - ViewerTabBar.contextMenuBuilder (full menu replacement)
//   - ViewerTabBar.tabTooltipBuilder (per-chip label tooltip)
// Sibling products that don't opt into these are unaffected (defaults match
// the prior behaviour); the no-opt-in defaults are covered in
// viewer_tab_bar_seams_test.dart.

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

class _NamedStrings extends ViewerTabBarStringsEn {
  const _NamedStrings();

  @override
  String closeTabTooltipFor(String name) => 'Close $name';
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_parity_');
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

  group('reorderTabInPane', () {
    test('maps a pane-local index to the correct global position', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(provider.notifier);
      await container.read(provider.future);

      // Pane A gets a0, a1; splitting moves the active tab (a1) into pane B.
      await notifier.openTab(displayName: 'a0', payload: 'a0');
      await notifier.openTab(displayName: 'a1', payload: 'a1');
      final paneB = await notifier.splitPaneRight();
      // Pane B now holds [a1]; add b0 so pane B is [a1, b0].
      await notifier.openTab(displayName: 'b0', payload: 'b0', paneId: paneB);

      // Global order is [a0, a1, b0]; pane B is [a1, b0].
      // Move a1 (pane-local index 0 in B) to pane-local index 1 (after b0).
      final a1 = (await container.read(
        provider.future,
      )).tabs.firstWhere((t) => t.displayName == 'a1');
      await notifier.reorderTabInPane(a1.id, paneB, 1);

      final ws = await container.read(provider.future);
      // Pane A is untouched; pane B is reordered to [b0, a1].
      expect(
        ws.tabsForPane(paneB).map((t) => t.displayName).toList(),
        ['b0', 'a1'],
      );
      // The fix must not corrupt the global list or pane A.
      final paneA = ws.tabs.firstWhere((t) => t.displayName == 'a0').paneId;
      expect(ws.tabsForPane(paneA).map((t) => t.displayName).toList(), ['a0']);
    });
  });

  testWidgets('closeTabTooltipFor drives the close-button tooltip', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'cpu.vcd', payload: 'a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              strings: const _NamedStrings(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final closeButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      ),
    );
    expect(closeButton.tooltip, 'Close cpu.vcd');
  });

  testWidgets(
    'useDragHandle:false hides the handle and shows a leading insertion slot',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ws = await container.read(provider.future);
      await container
          .read(provider.notifier)
          .openTab(displayName: 'a', payload: 'a');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ViewerTabBar<String>(
                paneId: ws.activePaneId,
                provider: provider,
                useDragHandle: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(
        find.byKey(ValueKey('tabInsertionSlot_${ws.activePaneId.value}_0')),
        findsOneWidget,
      );
      // The whole chip is a Draggable in this mode (private payload type, so
      // match the raw generic).
      expect(
        find.byWidgetPredicate((w) => w is Draggable),
        findsWidgets,
      );
    },
  );

  testWidgets('useDragHandle:true (default) shows handle, no leading slot', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'a', payload: 'a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(
      find.byKey(ValueKey('tabInsertionSlot_${ws.activePaneId.value}_0')),
      findsNothing,
    );
  });

  testWidgets('contextMenuBuilder fully replaces the built-in menu', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'a', payload: 'a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              contextMenuBuilder: (context, tab) => const [
                PopupMenuItem<Object>(child: Text('Custom Only')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Custom Only'), findsOneWidget);
    // None of the built-in actions are present when the host owns the menu.
    expect(find.text('Close Tab'), findsNothing);
    expect(find.text('Close Other Tabs'), findsNothing);
  });

  testWidgets('tabTooltipBuilder sets the chip label tooltip', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    await container
        .read(provider.notifier)
        .openTab(displayName: 'a', payload: 'a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              tabTooltipBuilder: (tab) => '/full/path/${tab.displayName}.vcd',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('a'),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, '/full/path/a.vcd');
  });
}
