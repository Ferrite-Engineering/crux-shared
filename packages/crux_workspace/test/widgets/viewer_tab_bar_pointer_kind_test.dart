// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which pointers may long-press a tab.
///
/// Over a remote display (X forwarding, a thin client, VNC) a mouse button-up
/// reaches the application late. A click whose release arrives after the
/// long-press timeout used to open the tab context menu, or start a drag from
/// the handle, instead of switching tabs. Long press belongs to touch and pen;
/// a mouse or trackpad that holds the button is still clicking.

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

/// Held well past `kLongPressTimeout` (500 ms).
const Duration _slowRelease = Duration(seconds: 2);

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  const strings = ViewerTabBarStringsEn();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_vtb_kind_');
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

  /// Opens tabs a, b, c (c is active) and pumps a bar over them.
  Future<(ProviderContainer, Map<String, TabId>, PaneId)> pumpBar(
    WidgetTester tester, {
    bool useDragHandle = true,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ws = await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final ids = <String, TabId>{};
    for (final name in ['a', 'b', 'c']) {
      ids[name] = await notifier.openTab(displayName: name, payload: name);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ViewerTabBar<String>(
              paneId: ws.activePaneId,
              provider: provider,
              useDragHandle: useDragHandle,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, ids, ws.activePaneId);
  }

  Future<TabId?> activeTab(ProviderContainer container) async =>
      (await container.read(provider.future)).activeTabId;

  Future<List<String>> order(ProviderContainer container, PaneId pane) async =>
      (await container.read(
        provider.future,
      )).tabsForPane(pane).map((t) => t.displayName).toList();

  Finder menuOpen() => find.text(strings.closeTabMenuItem);

  Finder handleOf(String label) => find
      .descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byIcon(Icons.drag_indicator),
      )
      .first;

  /// Presses [kind] at [at], holds past the long-press timeout, then releases.
  Future<void> holdAndRelease(
    WidgetTester tester,
    Offset at,
    PointerDeviceKind kind,
  ) async {
    final gesture = await tester.startGesture(at, kind: kind);
    await tester.pump(_slowRelease);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('a slow click is a click', () {
    testWidgets('a mouse held past the long-press timeout then released on '
        'a tab switches tabs and opens no menu', (tester) async {
      final (container, ids, _) = await pumpBar(tester);
      expect(await activeTab(container), ids['c']);

      await holdAndRelease(
        tester,
        tester.getCenter(find.text('a')),
        PointerDeviceKind.mouse,
      );

      expect(await activeTab(container), ids['a']);
      expect(menuOpen(), findsNothing);
    });

    testWidgets('a trackpad held past the long-press timeout opens no menu', (
      tester,
    ) async {
      await pumpBar(tester);

      await holdAndRelease(
        tester,
        tester.getCenter(find.text('a')),
        PointerDeviceKind.trackpad,
      );

      expect(menuOpen(), findsNothing);
    });

    testWidgets('the same holds in whole-chip drag mode', (tester) async {
      final (container, ids, pane) = await pumpBar(
        tester,
        useDragHandle: false,
      );

      await holdAndRelease(
        tester,
        tester.getCenter(find.text('b')),
        PointerDeviceKind.mouse,
      );

      expect(await activeTab(container), ids['b']);
      expect(menuOpen(), findsNothing);
      expect(await order(container, pane), ['a', 'b', 'c']);
    });

    testWidgets('a mouse held on the drag handle switches tabs and starts no '
        'drag', (tester) async {
      final (container, ids, pane) = await pumpBar(tester);

      await holdAndRelease(
        tester,
        tester.getCenter(handleOf('a')),
        PointerDeviceKind.mouse,
      );

      expect(
        await activeTab(container),
        ids['a'],
        reason: 'a held press on the handle is a click on the tab',
      );
      expect(menuOpen(), findsNothing);
      expect(await order(container, pane), ['a', 'b', 'c']);
    });

    testWidgets('a slow click on the handle leaves no drag feedback behind', (
      tester,
    ) async {
      await pumpBar(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(handleOf('a')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(_slowRelease);
      expect(
        find.byType(Draggable<Object>),
        findsNothing,
        reason: 'no drag may be in flight while the button is only held',
      );
      // The chip's own label is rendered once; a drag would add its feedback.
      expect(find.text('a'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('touch and pen long-press opens the menu', () {
    for (final kind in [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      testWidgets('a ${kind.name} long press opens the tab menu and does not '
          'switch tabs', (tester) async {
        final (container, ids, _) = await pumpBar(tester);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('a')),
          kind: kind,
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(menuOpen(), findsOneWidget);
        expect(await activeTab(container), ids['c']);
      });
    }

    testWidgets('a quick touch tap still switches tabs', (tester) async {
      final (container, ids, _) = await pumpBar(tester);

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(await activeTab(container), ids['a']);
      expect(menuOpen(), findsNothing);
    });
  });

  group('right-click opens the menu', () {
    testWidgets('a secondary-button mouse click', (tester) async {
      final (container, ids, _) = await pumpBar(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuOpen(), findsOneWidget);
      expect(await activeTab(container), ids['c']);
    });

    testWidgets('a right-click held past the long-press timeout', (
      tester,
    ) async {
      await pumpBar(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pump(_slowRelease);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(menuOpen(), findsOneWidget);
    });
  });

  group('dragging a tab', () {
    /// Moves [kind] from the handle of [from] onto the label of [onto].
    Future<void> dragHandle(
      WidgetTester tester, {
      required PointerDeviceKind kind,
      required String from,
      required String onto,
      Duration hold = Duration.zero,
    }) async {
      final gesture = await tester.startGesture(
        tester.getCenter(handleOf(from)),
        kind: kind,
      );
      if (hold > Duration.zero) await tester.pump(hold);
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text(onto)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('a mouse drags a tab by its handle without holding first', (
      tester,
    ) async {
      final (container, _, pane) = await pumpBar(tester);

      await dragHandle(
        tester,
        kind: PointerDeviceKind.mouse,
        from: 'a',
        onto: 'c',
      );

      expect(await order(container, pane), ['b', 'c', 'a']);
      expect(menuOpen(), findsNothing);
    });

    testWidgets('a finger drags a tab by its handle after a long press', (
      tester,
    ) async {
      final (container, _, pane) = await pumpBar(tester);

      await dragHandle(
        tester,
        kind: PointerDeviceKind.touch,
        from: 'a',
        onto: 'c',
        hold: const Duration(milliseconds: 600),
      );

      expect(await order(container, pane), ['b', 'c', 'a']);
    });

    testWidgets('a finger moving at once does not drag the tab by its '
        'handle', (tester) async {
      final (container, _, pane) = await pumpBar(tester);

      await dragHandle(
        tester,
        kind: PointerDeviceKind.touch,
        from: 'a',
        onto: 'c',
      );

      expect(
        await order(container, pane),
        ['a', 'b', 'c'],
        reason: 'touch keeps the long press that leaves a swipe to scrolling',
      );
    });
  });
}
