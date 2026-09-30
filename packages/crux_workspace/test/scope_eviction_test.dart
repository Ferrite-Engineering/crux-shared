// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Regression suite for the structural scope-eviction seam.
///
/// The bug these guard against is not a leak, it is **state bleed**: tab ids
/// round-trip through the workspace JSON document, so reloading a workspace
/// revives an id whose `ProviderContainer` is still cached — and the "new" tab
/// silently inherits the dead tab's per-tab state. The auditor reproduced it
/// with a cursor value; these tests reproduce it with the same shape and
/// assert the seam now prevents it.

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

/// Stands in for a product's per-tab state (WaveCrux's cursor position,
/// NetCrux's selected net, ...). Registered into every tab container by the
/// overrides factory below.
final _cursorProvider = Provider<_Cursor>((ref) => _Cursor(), name: 'cursor');

class _Cursor {
  int value = 0;
}

List<Override> _tabOverrides(TabId _) => <Override>[
  // A fresh _Cursor per container: reading the same provider from two
  // different containers must yield two different instances.
  _cursorProvider.overrideWith((ref) => _Cursor()),
];

/// A product-style subclass: the only way to reach the protected
/// [WorkspaceNotifier.mutate] seam is from inside the hierarchy, which is
/// exactly how products consume it.
class _ExtrasNotifier extends WorkspaceNotifier<String> {
  _ExtrasNotifier({required super.service, required super.autoSaveDebounce});

  /// An incremental document edit that touches no tab or pane — the shape of
  /// WaveCrux's window-geometry persistence.
  Future<void> writeExtra(String key, Object? value) =>
      mutate((c) => c.copyWith(extras: {...c.extras, key: value}));

  /// An incremental edit that DOES drop a tab, to prove `mutate` still prunes.
  Future<void> dropTab(TabId id) => mutate(
    (c) => c.copyWith(tabs: [...c.tabs.where((t) => t.id != id)]),
  );
}

/// Records every snapshot it is handed, so tests can assert on the *signal*
/// as well as on its effect.
class _RecordingReconciler implements WorkspaceScopeReconciler {
  final List<WorkspaceScopeSnapshot> snapshots = [];

  @override
  void reconcileScopes(WorkspaceScopeSnapshot live) => snapshots.add(live);
}

void main() {
  late Directory tempDir;
  late WorkspaceService<String> service;
  late AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>
  provider;
  late ProviderContainer root;
  late TabContainerManager tabs;
  late PaneContainerManager panes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_scope_evict_');
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
    tabs = TabContainerManager(
      rootContainer: root,
      overridesFactory: _tabOverrides,
    );
    panes = PaneContainerManager(rootContainer: root);
  });

  tearDown(() async {
    tabs.dispose();
    panes.dispose();
    root.dispose();
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // A save chained behind the test body can still be settling; the temp
      // directory is disposable either way.
    }
  });

  /// Boots a notifier with both container managers registered, the way a
  /// product's bootstrap does.
  Future<(ProviderContainer, WorkspaceNotifier<String>)> boot() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier)
      ..addScopeReconciler(tabs)
      ..addScopeReconciler(panes);
    return (container, notifier);
  }

  group('reload resurrection', () {
    test(
      'a tab id revived by a workspace reload gets a FRESH container',
      () async {
        final (_, notifier) = await boot();

        // Open a tab and dirty its per-tab state, exactly as a user would.
        final tabId = await notifier.openTab(displayName: 'A', payload: 'a');
        final live = tabs.containerFor(tabId);
        live.read(_cursorProvider).value = 42;
        expect(live.read(_cursorProvider).value, 42);

        // Capture a workspace document that still references this tab, then
        // close the tab. Persisted documents keep tab ids verbatim — this is
        // the round-trip that makes resurrection possible at all.
        final persisted = await persistedRoundTrip(notifier);
        await notifier.closeTab(tabId);
        expect(
          tabs.hasContainerFor(tabId),
          isFalse,
          reason: 'closeTab must evict the closed tab’s container',
        );

        // Reload the saved document. The SAME TabId comes back.
        await notifier.replaceWith(persisted);
        expect(
          persisted.tabs.single.id,
          equals(tabId),
          reason: 'precondition: the reload really does revive the same id',
        );

        final revived = tabs.containerFor(tabId);
        expect(
          identical(revived, live),
          isFalse,
          reason: 'the revived tab must not be handed the dead tab’s container',
        );
        expect(
          revived.read(_cursorProvider).value,
          0,
          reason:
              'the revived tab inherited the closed tab’s cursor — this is '
              'the reproduced state-bleed bug',
        );
      },
    );

    test(
      'replaceWith evicts scopes even when the incoming document reuses '
      'every id',
      () async {
        final (_, notifier) = await boot();
        final tabId = await notifier.openTab(displayName: 'A', payload: 'a');
        tabs.containerFor(tabId).read(_cursorProvider).value = 7;

        // A document with an identical tab set. Pruning to "ids not in the
        // new document" would keep the container; a wholesale replacement
        // must not.
        final same = await persistedRoundTrip(notifier);
        await notifier.replaceWith(same);

        expect(tabs.containerFor(tabId).read(_cursorProvider).value, 0);
      },
    );

    test('loadFrom evicts the outgoing document’s scopes', () async {
      final (_, notifier) = await boot();
      final tabId = await notifier.openTab(displayName: 'A', payload: 'a');
      tabs.containerFor(tabId).read(_cursorProvider).value = 99;

      final path = '${tempDir.path}/named.json';
      await notifier.saveAs(path);
      await notifier.loadFrom(path);

      final loadedId = (await notifier.future).tabs.single.id;
      expect(loadedId, equals(tabId), reason: 'ids survive the round-trip');
      expect(tabs.containerFor(loadedId).read(_cursorProvider).value, 0);
    });

    test('resetWorkspace evicts every tab and pane scope', () async {
      final (_, notifier) = await boot();
      final a = await notifier.openTab(displayName: 'A', payload: 'a');
      final b = await notifier.openTab(displayName: 'B', payload: 'b');
      final paneId = (await notifier.future).activePaneId;
      tabs
        ..containerFor(a)
        ..containerFor(b);
      panes.containerFor(paneId);

      await notifier.resetWorkspace();

      expect(tabs.hasContainerFor(a), isFalse);
      expect(tabs.hasContainerFor(b), isFalse);
      expect(panes.hasContainerFor(paneId), isFalse);
    });
  });

  group('eviction is structural, not opt-in', () {
    test(
      'closeTab evicts only the closed tab, leaving siblings intact',
      () async {
        final (_, notifier) = await boot();
        final a = await notifier.openTab(displayName: 'A', payload: 'a');
        final b = await notifier.openTab(displayName: 'B', payload: 'b');
        final containerA = tabs.containerFor(a);
        final containerB = tabs.containerFor(b);
        containerA.read(_cursorProvider).value = 1;
        containerB.read(_cursorProvider).value = 2;

        await notifier.closeTab(a);

        expect(tabs.hasContainerFor(a), isFalse);
        expect(tabs.hasContainerFor(b), isTrue);
        expect(
          identical(tabs.containerFor(b), containerB),
          isTrue,
          reason: 'the surviving tab keeps its container and its state',
        );
        expect(containerB.read(_cursorProvider).value, 2);
      },
    );

    test(
      'two tabs are isolated, and closing one cannot bleed into the other',
      () async {
        final (_, notifier) = await boot();
        final a = await notifier.openTab(displayName: 'A', payload: 'a');
        final b = await notifier.openTab(displayName: 'B', payload: 'b');

        tabs.containerFor(a).read(_cursorProvider).value = 11;
        tabs.containerFor(b).read(_cursorProvider).value = 22;
        expect(tabs.containerFor(a).read(_cursorProvider).value, 11);
        expect(tabs.containerFor(b).read(_cursorProvider).value, 22);

        await notifier.closeTab(a);
        // b is untouched; a is gone and comes back clean.
        expect(tabs.containerFor(b).read(_cursorProvider).value, 22);

        final reopened = await notifier.openTab(
          displayName: 'A2',
          payload: 'a',
        );
        expect(tabs.containerFor(reopened).read(_cursorProvider).value, 0);
      },
    );

    test(
      'a collapsed pane’s container is evicted by the split collapsing',
      () async {
        final (_, notifier) = await boot();
        await notifier.openTab(displayName: 'A', payload: 'a');
        await notifier.openTab(displayName: 'B', payload: 'b');
        final newPane = await notifier.splitPaneRight();
        panes.containerFor(newPane);
        expect(panes.hasContainerFor(newPane), isTrue);

        await notifier.closePane(newPane);

        expect(
          panes.hasContainerFor(newPane),
          isFalse,
          reason: 'closePane must evict the closed pane’s scope',
        );
      },
    );

    test('every mutation emits a snapshot of the live scope set', () async {
      final recorder = _RecordingReconciler();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier)
        ..addScopeReconciler(recorder);
      recorder.snapshots.clear();

      final a = await notifier.openTab(displayName: 'A', payload: 'a');
      expect(recorder.snapshots.last.tabIds, {a});

      final b = await notifier.openTab(displayName: 'B', payload: 'b');
      expect(recorder.snapshots.last.tabIds, {a, b});

      await notifier.closeTab(a);
      expect(recorder.snapshots.last.tabIds, {b});

      // A wholesale replacement emits the empty snapshot FIRST, so no
      // reconciler can mistake a reused id for a surviving scope.
      recorder.snapshots.clear();
      await notifier.resetWorkspace();
      expect(recorder.snapshots.first.tabIds, isEmpty);
      expect(recorder.snapshots.first.paneIds, isEmpty);
    });
  });

  group('incremental mutation preserves live scopes', () {
    /// Boots a subclass that exposes the protected [WorkspaceNotifier.mutate]
    /// seam, standing in for a product's own notifier subclass (WaveCrux's
    /// `setWindowBounds`, NetCrux's per-document extras, ...).
    Future<_ExtrasNotifier> bootExtras() async {
      final extrasProvider =
          AsyncNotifierProvider<_ExtrasNotifier, Workspace<String>>(
            () => _ExtrasNotifier(
              service: service,
              autoSaveDebounce: Duration.zero,
            ),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(extrasProvider.future);
      final notifier = container.read(extrasProvider.notifier)
        ..addScopeReconciler(tabs)
        ..addScopeReconciler(panes);
      return notifier;
    }

    test(
      'writing an extras entry keeps every tab and pane container identical',
      () async {
        final notifier = await bootExtras();
        final tabId = await notifier.openTab(displayName: 'A', payload: 'a');
        final paneId = (await notifier.future).activePaneId;
        final tabContainer = tabs.containerFor(tabId);
        final paneContainer = panes.containerFor(paneId);
        tabContainer.read(_cursorProvider).value = 5;

        // This is the window-resize path: geometry lands in `extras` many
        // times per drag while every tab stays on screen. Routing it through
        // `replaceWith` disposed all of these containers, and the host's
        // nested `ProviderScope`s then threw "rebuilt with a different
        // ProviderScope ancestor" on the next layout pass.
        await notifier.writeExtra('windowBounds', '0,0,1920,1080');

        expect(identical(tabs.containerFor(tabId), tabContainer), isTrue);
        expect(identical(panes.containerFor(paneId), paneContainer), isTrue);
        expect(tabContainer.read(_cursorProvider).value, 5);
        expect(
          (await notifier.future).extras['windowBounds'],
          '0,0,1920,1080',
        );
      },
    );

    test('mutate still evicts the scopes the new document dropped', () async {
      final notifier = await bootExtras();
      final a = await notifier.openTab(displayName: 'A', payload: 'a');
      final b = await notifier.openTab(displayName: 'B', payload: 'b');
      tabs
        ..containerFor(a)
        ..containerFor(b);

      await notifier.dropTab(a);

      expect(tabs.hasContainerFor(a), isFalse);
      expect(tabs.hasContainerFor(b), isTrue);
    });
  });

  group('reconciler registration', () {
    test('registering twice does not double-invoke', () async {
      final recorder = _RecordingReconciler();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier)
        ..addScopeReconciler(recorder)
        ..addScopeReconciler(recorder);
      recorder.snapshots.clear();

      await notifier.openTab(displayName: 'A', payload: 'a');
      expect(recorder.snapshots, hasLength(1));
    });

    test('registration immediately reconciles against current state', () async {
      final (_, notifier) = await boot();
      final a = await notifier.openTab(displayName: 'A', payload: 'a');
      await notifier.closeTab(a);

      // A manager that missed the close (registered late) is pruned on join.
      final joiner = TabContainerManager(rootContainer: root);
      addTearDown(joiner.dispose);
      joiner.containerFor(a);
      expect(joiner.hasContainerFor(a), isTrue);

      notifier.addScopeReconciler(joiner);
      expect(
        joiner.hasContainerFor(a),
        isFalse,
        reason: 'joining reconcilers are brought in line with current state',
      );
    });

    test('removeScopeReconciler stops the signal', () async {
      final recorder = _RecordingReconciler();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier)
        ..addScopeReconciler(recorder);

      expect(notifier.removeScopeReconciler(recorder), isTrue);
      recorder.snapshots.clear();
      await notifier.openTab(displayName: 'A', payload: 'a');
      expect(recorder.snapshots, isEmpty);
      expect(notifier.removeScopeReconciler(recorder), isFalse);
    });

    test('reconcilers passed to the constructor receive the signal', () async {
      final recorder = _RecordingReconciler();
      final ctorProvider =
          AsyncNotifierProvider<WorkspaceNotifier<String>, Workspace<String>>(
            () => WorkspaceNotifier<String>(
              service: service,
              autoSaveDebounce: Duration.zero,
              scopeReconcilers: [recorder],
            ),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(ctorProvider.future);
      // build() reconciles against the freshly-loaded document.
      expect(recorder.snapshots, isNotEmpty);

      await container
          .read(ctorProvider.notifier)
          .openTab(displayName: 'A', payload: 'a');
      expect(recorder.snapshots.last.tabIds, hasLength(1));
    });
  });

  group('manager-level reconcile()', () {
    test('reconcile disposes exactly the absent ids and reports them', () {
      final a = TabId.generate();
      final b = TabId.generate();
      tabs
        ..containerFor(a)
        ..containerFor(b);

      final evicted = tabs.reconcile({b});

      expect(evicted, {a});
      expect(tabs.hasContainerFor(a), isFalse);
      expect(tabs.hasContainerFor(b), isTrue);
    });

    test(
      'reconcile with an empty set clears but leaves the manager usable',
      () {
        final a = TabId.generate();
        tabs
          ..containerFor(a)
          ..reconcile(const {});
        expect(tabs.hasContainerFor(a), isFalse);

        // Unlike dispose(), the manager still works afterwards.
        expect(tabs.containerFor(a), isNotNull);
        expect(tabs.hasContainerFor(a), isTrue);
      },
    );

    test('pane manager reconcile behaves the same way', () {
      final a = PaneId.generate();
      final b = PaneId.generate();
      panes
        ..containerFor(a)
        ..containerFor(b);

      expect(panes.reconcile({a}), {b});
      expect(panes.hasContainerFor(a), isTrue);
      expect(panes.hasContainerFor(b), isFalse);
    });

    test('reconcile is a no-op when everything is live', () {
      final a = TabId.generate();
      final container = tabs.containerFor(a);

      expect(tabs.reconcile({a}), isEmpty);
      expect(identical(tabs.containerFor(a), container), isTrue);
    });
  });
}

/// Round-trips the current workspace through the codec, the way persistence
/// does, so the resulting document carries the same tab ids as strings.
Future<Workspace<String>> persistedRoundTrip(
  WorkspaceNotifier<String> notifier,
) async {
  final current = await notifier.future;
  return Workspace<String>.fromJson(
    current.toJson(const _StringCodec()),
    const _StringCodec(),
  );
}
