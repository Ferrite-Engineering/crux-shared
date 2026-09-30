// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StringPayloadCodec extends WorkspaceCodec<String> {
  const _StringPayloadCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(String payload) => {'value': payload};

  @override
  String payloadFromJson(Map<String, Object?> json) =>
      json['value'] as String? ?? '';

  @override
  String displayNameFor(String payload) => payload;
}

class _NotifierHarness {
  _NotifierHarness({required this.tempDir})
    : service = WorkspaceService<String>(
        codec: const _StringPayloadCodec(),
        directoryFactory: () async => tempDir,
        logger: (_) {},
      ) {
    provider =
        AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
          () => WorkspaceNotifier<String>(
            service: service,
            autoSaveDebounce: Duration.zero,
          ),
        );
    container = ProviderContainer();
  }

  final Directory tempDir;
  final WorkspaceService<String> service;
  late final AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  late final ProviderContainer container;

  Future<void> hydrate() => container.read(provider.future);
  WorkspaceNotifier<String> get notifier => container.read(provider.notifier);
  Workspace<String> get state => container.read(provider).requireValue;

  Future<void> dispose() async {
    // Await any in-flight auto-save before tearing down. With a zero debounce
    // a mutation kicks off `service.save()` eagerly and the dispose hook is
    // fire-and-forget, so the write may still hold the temp file open. POSIX
    // tolerates deleting an open file, but Windows fails the recursive delete
    // with errno 32 ("being used by another process"). Flushing first lets the
    // atomic write finish and release the handle.
    await notifier.flushPendingSave();
    container.dispose();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceNotifier<String>', () {
    late _NotifierHarness h;

    setUp(() async {
      final tempDir = await Directory.systemTemp.createTemp(
        'crux_workspace_notif_',
      );
      h = _NotifierHarness(tempDir: tempDir);
      await h.hydrate();
    });

    tearDown(() async => h.dispose());

    test('build() yields an empty workspace on first read', () {
      expect(h.state.isEmpty, isTrue);
      expect(h.state.panes, hasLength(1));
    });

    test('openTab appends to active pane and activates it', () async {
      final id = await h.notifier.openTab(
        displayName: 'first',
        payload: 'p1',
      );
      expect(h.state.tabs, hasLength(1));
      expect(h.state.tabs.single.id, equals(id));
      expect(h.state.tabs.single.displayName, equals('first'));
      expect(h.state.tabs.single.payload, equals('p1'));
      expect(h.state.activeTabId, equals(id));
    });

    test('openTab honors explicit paneId', () async {
      final secondPaneId = await h.notifier.splitPaneRight();
      final tabInSecond = await h.notifier.openTab(
        displayName: 'right',
        payload: 'r',
        paneId: secondPaneId,
      );
      final hostedTabs = h.state.tabsForPane(secondPaneId);
      expect(hostedTabs.map((t) => t.id), contains(tabInSecond));
    });

    test('openTab rejects unknown paneId', () async {
      expect(
        () => h.notifier.openTab(
          displayName: 'x',
          payload: 'x',
          paneId: PaneId.generate(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('closeTab advances active pointer to the adjacent tab', () async {
      final a = await h.notifier.openTab(displayName: 'a', payload: 'a');
      final b = await h.notifier.openTab(displayName: 'b', payload: 'b');
      final c = await h.notifier.openTab(displayName: 'c', payload: 'c');
      await h.notifier.closeTab(c);
      expect(h.state.activeTabId, equals(b));
      await h.notifier.closeTab(a);
      expect(h.state.activeTabId, equals(b));
    });

    test(
      'closeTab on sole tab leaves the pane empty without dropping it',
      () async {
        final a = await h.notifier.openTab(displayName: 'a', payload: 'a');
        await h.notifier.closeTab(a);
        expect(h.state.tabs, isEmpty);
        expect(h.state.panes, hasLength(1));
        expect(h.state.activeTabId, isNull);
      },
    );

    test(
      'closeTab advances active pointer pane-locally in split-pane mode',
      () async {
        // Regression: closing the active tab must pick the adjacent tab
        // *within the same pane*, indexed by the removed tab's pane-local
        // position — not by its global position in the flat tab list. With
        // paneA populated first, every paneB tab's global index is offset by
        // paneA's tab count, so a global-index lookup selects the wrong
        // survivor (or the pane's last tab) instead of the true next tab.
        final paneA = h.state.activePaneId;
        final paneB = await h.notifier.splitPaneRight();
        // paneA: two tabs, so paneB's globals are offset by 2.
        await h.notifier.openTab(
          displayName: 'a0',
          payload: 'a0',
          paneId: paneA,
        );
        await h.notifier.openTab(
          displayName: 'a1',
          payload: 'a1',
          paneId: paneA,
        );
        // paneB: three tabs.
        final b0 = await h.notifier.openTab(
          displayName: 'b0',
          payload: 'b0',
          paneId: paneB,
        );
        final b1 = await h.notifier.openTab(
          displayName: 'b1',
          payload: 'b1',
          paneId: paneB,
        );
        final b2 = await h.notifier.openTab(
          displayName: 'b2',
          payload: 'b2',
          paneId: paneB,
        );

        // Closing the pane's first tab must advance to its next sibling (b1),
        // not to the pane's last tab (b2). The buggy global-index path
        // computed idx=2 (b0's global position) against a 2-element remaining
        // pane list and fell through to the last element.
        await h.notifier.setActiveTab(b0);
        await h.notifier.closeTab(b0);
        expect(
          h.state.panes.firstWhere((p) => p.id == paneB).activeTabId,
          equals(b1),
        );

        // Closing the pane's now-last tab falls back to the previous sibling.
        await h.notifier.setActiveTab(b2);
        await h.notifier.closeTab(b2);
        expect(
          h.state.panes.firstWhere((p) => p.id == paneB).activeTabId,
          equals(b1),
        );
      },
    );

    test(
      'closeTab on empty non-active pane collapses to single pane',
      () async {
        final paneA = h.state.activePaneId;
        final paneB = await h.notifier.splitPaneRight();
        await h.notifier.openTab(
          displayName: 'left',
          payload: 'left',
          paneId: paneA,
        );
        final rightTab = await h.notifier.openTab(
          displayName: 'right',
          payload: 'right',
          paneId: paneB,
        );
        await h.notifier.closeTab(rightTab);
        expect(h.state.panes, hasLength(1));
        expect(h.state.panes.single.id, equals(paneA));
        expect(h.state.activePaneId, equals(paneA));
      },
    );

    test('reorderTab moves the tab within the list', () async {
      final a = await h.notifier.openTab(displayName: 'a', payload: 'a');
      final b = await h.notifier.openTab(displayName: 'b', payload: 'b');
      final c = await h.notifier.openTab(displayName: 'c', payload: 'c');
      await h.notifier.reorderTab(c, 0);
      expect(h.state.tabs.map((t) => t.id), equals([c, a, b]));
    });

    test('moveTabToPane activates the moved tab in the target pane', () async {
      final paneA = h.state.activePaneId;
      final paneB = await h.notifier.splitPaneRight();
      // Keep paneA populated so it survives the move (its collapse is
      // covered by the dedicated regression test below).
      await h.notifier.openTab(
        displayName: 'keep',
        payload: 'k',
        paneId: paneA,
      );
      final t = await h.notifier.openTab(
        displayName: 'movable',
        payload: 'm',
        paneId: paneA,
      );
      await h.notifier.setActiveTab(t);
      await h.notifier.moveTabToPane(t, paneB);
      expect(
        h.state.tabs.firstWhere((tab) => tab.id == t).paneId,
        equals(paneB),
      );
      expect(
        h.state.panes.firstWhere((p) => p.id == paneB).activeTabId,
        equals(t),
      );
    });

    test(
      'moveTabToPane collapses the source pane when its last tab leaves',
      () async {
        // Regression: dragging the last tab out of pane 2 into pane 1 must
        // remove the now-empty pane 2, not leave a phantom empty pane. The
        // generic WorkspaceNotifier.moveTabToPane originally only retargeted
        // the tab and never pruned the emptied source pane (closeTab did).
        final paneA = h.state.activePaneId;
        final paneB = await h.notifier.splitPaneRight();
        final t = await h.notifier.openTab(
          displayName: 'movable',
          payload: 'm',
          paneId: paneB,
        );
        await h.notifier.setActiveTab(t);
        expect(h.state.activePaneId, equals(paneB));
        expect(h.state.panes.map((p) => p.id), containsAll([paneA, paneB]));

        await h.notifier.moveTabToPane(t, paneA);

        // The emptied source pane is gone; only the destination survives.
        expect(h.state.panes.map((p) => p.id), equals([paneA]));
        expect(h.state.panes.any((p) => p.id == paneB), isFalse);
        // The tab now lives in — and is active in — the destination pane,
        // which also becomes the active pane.
        expect(h.state.tabs.single.paneId, equals(paneA));
        expect(
          h.state.panes.single.activeTabId,
          equals(t),
        );
        expect(h.state.activePaneId, equals(paneA));
      },
    );

    test(
      'moveTabToPane reselects the source active tab when the pane survives',
      () async {
        // Moving the *active* tab out of a still-populated pane must leave
        // that pane showing a surviving sibling, never a blank selection.
        final paneA = h.state.activePaneId;
        final paneB = await h.notifier.splitPaneRight();
        final keep = await h.notifier.openTab(
          displayName: 'keep',
          payload: 'k',
          paneId: paneA,
        );
        final move = await h.notifier.openTab(
          displayName: 'move',
          payload: 'm',
          paneId: paneA,
        );
        await h.notifier.setActiveTab(move);
        expect(
          h.state.panes.firstWhere((p) => p.id == paneA).activeTabId,
          equals(move),
        );

        await h.notifier.moveTabToPane(move, paneB);

        // paneA still exists and falls back to its surviving tab.
        expect(
          h.state.panes.firstWhere((p) => p.id == paneA).activeTabId,
          equals(keep),
        );
        expect(
          h.state.panes.firstWhere((p) => p.id == paneB).activeTabId,
          equals(move),
        );
      },
    );

    test('setActivePane focuses the named pane', () async {
      final paneA = h.state.activePaneId;
      final paneB = await h.notifier.splitPaneRight();
      await h.notifier.setActivePane(paneA);
      expect(h.state.activePaneId, equals(paneA));
      await h.notifier.setActivePane(paneB);
      expect(h.state.activePaneId, equals(paneB));
    });

    test('splitPaneRight is a no-op when already split', () async {
      final paneB = await h.notifier.splitPaneRight();
      final paneBAgain = await h.notifier.splitPaneRight();
      expect(paneBAgain, equals(paneB));
      expect(h.state.panes, hasLength(2));
    });

    test(
      'splitPaneRight moves active tab into new pane when source has 2+',
      () async {
        await h.notifier.openTab(displayName: 'a', payload: 'a');
        final b = await h.notifier.openTab(displayName: 'b', payload: 'b');
        final paneB = await h.notifier.splitPaneRight();
        expect(h.state.tabsForPane(paneB).map((t) => t.id), equals([b]));
        expect(h.state.tabsForPane(h.state.panes.first.id), hasLength(1));
      },
    );

    test('splitPaneRight opens empty when source has a single tab', () async {
      await h.notifier.openTab(displayName: 'sole', payload: 'sole');
      final paneB = await h.notifier.splitPaneRight();
      expect(h.state.tabsForPane(paneB), isEmpty);
    });

    test('closePane merges tabs into the surviving pane', () async {
      final paneA = h.state.activePaneId;
      final paneB = await h.notifier.splitPaneRight();
      final aTab = await h.notifier.openTab(
        displayName: 'a',
        payload: 'a',
        paneId: paneA,
      );
      final bTab = await h.notifier.openTab(
        displayName: 'b',
        payload: 'b',
        paneId: paneB,
      );
      await h.notifier.closePane(paneB);
      expect(h.state.panes, hasLength(1));
      expect(h.state.tabs.map((t) => t.id).toSet(), equals({aTab, bTab}));
      expect(h.state.tabs.every((t) => t.paneId == paneA), isTrue);
    });

    test('closePane on the sole pane is a no-op', () async {
      final sole = h.state.activePaneId;
      await h.notifier.closePane(sole);
      expect(h.state.panes, hasLength(1));
    });

    test('focusOtherPane toggles between panes', () async {
      final paneA = h.state.activePaneId;
      final paneB = await h.notifier.splitPaneRight();
      expect(h.state.activePaneId, equals(paneB));
      await h.notifier.focusOtherPane();
      expect(h.state.activePaneId, equals(paneA));
      await h.notifier.focusOtherPane();
      expect(h.state.activePaneId, equals(paneB));
    });

    test('focusOtherPane is a no-op when single-pane', () async {
      final original = h.state.activePaneId;
      await h.notifier.focusOtherPane();
      expect(h.state.activePaneId, equals(original));
    });

    test('updateTabPayload replaces the payload immutably', () async {
      final t = await h.notifier.openTab(displayName: 'a', payload: 'old');
      final before = h.state.tabs.single;
      await h.notifier.updateTabPayload(t, (p) => '$p-new');
      final after = h.state.tabs.single;
      expect(after.payload, equals('old-new'));
      expect(identical(before, after), isFalse);
    });

    test('updateTabDisplayName changes the displayed title', () async {
      final t = await h.notifier.openTab(displayName: 'old', payload: 'p');
      await h.notifier.updateTabDisplayName(t, 'new');
      expect(h.state.tabs.single.displayName, equals('new'));
    });

    test('resetWorkspace clears all tabs to a single empty pane', () async {
      await h.notifier.openTab(displayName: 'a', payload: 'a');
      await h.notifier.splitPaneRight();
      await h.notifier.openTab(displayName: 'b', payload: 'b');
      await h.notifier.resetWorkspace();
      expect(h.state.tabs, isEmpty);
      expect(h.state.panes, hasLength(1));
      expect(h.state.activeTabId, isNull);
    });

    test('replaceWith swaps in an arbitrary workspace', () async {
      final pane = WorkspacePane(id: PaneId.generate());
      final tab = WorkspaceTab(
        id: TabId.generate(),
        displayName: 'replaced',
        paneId: pane.id,
        payload: 'r',
      );
      final next = Workspace<String>(
        tabs: [tab],
        panes: [pane.copyWith(activeTabId: tab.id)],
        activePaneId: pane.id,
      );
      await h.notifier.replaceWith(next);
      expect(h.state, equals(next));
    });

    test('saveAs writes to disk and loadFrom restores it', () async {
      await h.notifier.openTab(displayName: 'persisted', payload: 'p');
      final namedPath = '${h.tempDir.path}/named.crux-workspace';
      await h.notifier.saveAs(namedPath);
      await h.notifier.resetWorkspace();
      expect(h.state.isEmpty, isTrue);
      final loaded = await h.notifier.loadFrom(namedPath);
      expect(loaded.tabs.single.displayName, equals('persisted'));
      expect(h.state.tabs.single.payload, equals('p'));
    });

    test('flushPendingSave forces a synchronous disk write', () async {
      await h.notifier.openTab(displayName: 'a', payload: 'a');
      await h.notifier.flushPendingSave();
      final reloaded = await h.service.load();
      expect(reloaded.tabs.single.displayName, equals('a'));
    });
  });
}
