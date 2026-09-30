// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tab context menu's execution paths.
///
/// The test this replaces asserted that `TabContextAction.values` had four
/// entries whose names matched their labels. That assertion passes unchanged
/// if every handler in `_showMenuAt` is replaced with `return;` — which is
/// exactly what the coverage report showed: 105 uncovered lines, all of them
/// menu execution. These tests open the real menu and tap the real items, so
/// gutting a handler turns them red.

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

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  const strings = ViewerTabBarStringsEn();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_menu_');
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

  /// Pumps a bar over a workspace seeded with [labels], returning the
  /// container and the ids in creation order.
  Future<(ProviderContainer, List<TabId>)> pumpBarWithTabs(
    WidgetTester tester,
    List<String> labels, {
    TabContextMenuItemsBuilder<String>? contextMenuItems,
    TabContextMenuBuilder<String>? contextMenuBuilder,
    String? Function(WorkspaceTab<String> tab)? tabFilePath,
    void Function(String path)? onRevealTab,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final ids = <TabId>[];
    for (final label in labels) {
      ids.add(await notifier.openTab(displayName: label, payload: label));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              contextMenuItems: contextMenuItems,
              contextMenuBuilder: contextMenuBuilder,
              tabFilePath: tabFilePath,
              onRevealTab: onRevealTab,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, ids);
  }

  /// Right-clicks the chip labelled [label] and settles the menu open.
  Future<void> openMenuOn(WidgetTester tester, String label) async {
    final chip = find.text(label);
    expect(chip, findsOneWidget, reason: 'chip "$label" must be rendered');
    final center = tester.getCenter(chip);
    final gesture = await tester.startGesture(
      center,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Long-presses the chip labelled [label] — the touch path to the same menu.
  Future<void> longPressOn(WidgetTester tester, String label) async {
    await tester.longPress(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<List<String>> tabLabels(ProviderContainer container) async {
    final ws = await container.read(provider.notifier).future;
    return ws.tabs.map((t) => t.displayName).toList();
  }

  group('menu execution', () {
    testWidgets('Close Tab closes exactly that tab', (tester) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A', 'B', 'C']);

      await openMenuOn(tester, 'B');
      await tester.tap(find.text(strings.closeTabMenuItem).last);
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['A', 'C']);
    });

    testWidgets('Close Other Tabs leaves only the clicked tab', (tester) async {
      final (container, _) = await pumpBarWithTabs(tester, [
        'A',
        'B',
        'C',
        'D',
      ]);

      await openMenuOn(tester, 'B');
      await tester.tap(find.text(strings.closeOtherTabsMenuItem));
      await tester.pumpAndSettle();

      expect(
        await tabLabels(container),
        ['B'],
        reason: 'gutting this handler would leave all four tabs open',
      );
    });

    testWidgets('Close Tabs to the Right closes only the suffix', (
      tester,
    ) async {
      final (container, _) = await pumpBarWithTabs(tester, [
        'A',
        'B',
        'C',
        'D',
      ]);

      await openMenuOn(tester, 'B');
      await tester.tap(find.text(strings.closeTabsToTheRightMenuItem));
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['A', 'B']);
    });

    testWidgets('Close Tabs to the Right on the last tab is a no-op', (
      tester,
    ) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A', 'B']);

      await openMenuOn(tester, 'B');
      // The item renders but is disabled, so the tap yields no selection.
      await tester.tap(find.text(strings.closeTabsToTheRightMenuItem));
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['A', 'B']);
    });

    testWidgets('Close Other Tabs is disabled for a lone tab', (tester) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A']);

      await openMenuOn(tester, 'A');
      final item = tester.widget<PopupMenuItem<Object>>(
        find.ancestor(
          of: find.text(strings.closeOtherTabsMenuItem),
          matching: find.byType(PopupMenuItem<Object>),
        ),
      );
      expect(item.enabled, isFalse);

      await tester.tap(find.text(strings.closeOtherTabsMenuItem));
      await tester.pumpAndSettle();
      expect(await tabLabels(container), ['A']);
    });

    testWidgets('Move to New Window is rendered but inert in this build', (
      tester,
    ) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A', 'B']);

      await openMenuOn(tester, 'A');
      final entry = find.text(strings.moveToNewWindowMenuItem);
      expect(
        entry,
        findsOneWidget,
        reason: 'the seam stays visible so contributors can see it',
      );
      final item = tester.widget<PopupMenuItem<Object>>(
        find.ancestor(of: entry, matching: find.byType(PopupMenuItem<Object>)),
      );
      expect(
        item.enabled,
        kMultiWindowAvailable,
        reason: 'enablement is gated on the compile-time flag, nothing else',
      );

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(
        await tabLabels(container),
        ['A', 'B'],
        reason: 'the disabled action must not mutate the workspace',
      );
    });

    testWidgets('dismissing the menu without a selection changes nothing', (
      tester,
    ) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A', 'B']);

      await openMenuOn(tester, 'A');
      // Tap outside the menu to dismiss it.
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['A', 'B']);
    });
  });

  group('both menu-positioning paths reach the same actions', () {
    testWidgets('long-press (touch) opens the menu and executes', (
      tester,
    ) async {
      final (container, _) = await pumpBarWithTabs(tester, ['A', 'B', 'C']);

      await longPressOn(tester, 'C');
      expect(find.text(strings.closeTabMenuItem), findsOneWidget);

      await tester.tap(find.text(strings.closeTabMenuItem).last);
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['A', 'B']);
    });

    testWidgets('secondary-tap (desktop) opens the menu', (tester) async {
      await pumpBarWithTabs(tester, ['A']);
      await openMenuOn(tester, 'A');
      expect(find.text(strings.closeTabMenuItem), findsOneWidget);
      expect(find.text(strings.closeOtherTabsMenuItem), findsOneWidget);
      expect(find.text(strings.closeTabsToTheRightMenuItem), findsOneWidget);
      expect(find.text(strings.moveToNewWindowMenuItem), findsOneWidget);
    });
  });

  group('product extension points', () {
    testWidgets('contextMenuItems are appended below the built-ins', (
      tester,
    ) async {
      var customTaps = 0;
      await pumpBarWithTabs(
        tester,
        ['A'],
        contextMenuItems: (tab) => [
          PopupMenuItem<Object>(
            value: 'custom',
            onTap: () => customTaps++,
            child: Text('Reveal ${tab.displayName}'),
          ),
        ],
      );

      await openMenuOn(tester, 'A');
      expect(find.text(strings.closeTabMenuItem), findsOneWidget);
      expect(find.text('Reveal A'), findsOneWidget);

      await tester.tap(find.text('Reveal A'));
      await tester.pumpAndSettle();
      expect(customTaps, 1);
    });

    testWidgets('contextMenuBuilder replaces the built-in block entirely', (
      tester,
    ) async {
      var customTaps = 0;
      final (container, _) = await pumpBarWithTabs(
        tester,
        ['A', 'B'],
        contextMenuBuilder: (context, tab) => [
          PopupMenuItem<Object>(
            value: 'only',
            onTap: () => customTaps++,
            child: const Text('Only Item'),
          ),
        ],
      );

      await openMenuOn(tester, 'A');
      expect(find.text('Only Item'), findsOneWidget);
      expect(
        find.text(strings.closeOtherTabsMenuItem),
        findsNothing,
        reason: 'a fully-composed menu suppresses the built-in actions',
      );

      await tester.tap(find.text('Only Item'));
      await tester.pumpAndSettle();
      expect(customTaps, 1);
      expect(await tabLabels(container), ['A', 'B']);
    });
  });

  group('chip affordances', () {
    testWidgets('the × button closes the tab', (tester) async {
      final (container, ids) = await pumpBarWithTabs(tester, ['A', 'B']);

      // The default strings return one generic close tooltip for every chip,
      // so address the button positionally: the first × belongs to tab A.
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(await tabLabels(container), ['B']);
      expect(ids, hasLength(2));
    });

    testWidgets('tapping a chip activates it', (tester) async {
      final (container, ids) = await pumpBarWithTabs(tester, ['A', 'B']);

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      final ws = await container.read(provider.notifier).future;
      expect(ws.activeTabId, ids.first);
    });
  });
  group('path header + reveal (promoted WaveCrux canon)', () {
    testWidgets('with tabFilePath + onRevealTab the default menu shows the '
        'monospace path header and a working Reveal item', (tester) async {
      String? revealed;
      await pumpBarWithTabs(
        tester,
        ['a.vcd'],
        tabFilePath: (tab) => '/tmp/traces/${tab.payload}',
        onRevealTab: (path) => revealed = path,
      );
      await openMenuOn(tester, 'a.vcd');

      expect(find.text('/tmp/traces/a.vcd'), findsOneWidget);
      await tester.tap(find.text('Reveal in Finder'));
      await tester.pumpAndSettle();
      expect(revealed, '/tmp/traces/a.vcd');
    });

    testWidgets('without tabFilePath the default menu is unchanged', (
      tester,
    ) async {
      await pumpBarWithTabs(tester, ['a.vcd']);
      await openMenuOn(tester, 'a.vcd');
      expect(find.text('Reveal in Finder'), findsNothing);
    });
  });
}
