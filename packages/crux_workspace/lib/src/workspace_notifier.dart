// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/workspace.dart';
import 'package:crux_workspace/src/workspace_codec.dart';
import 'package:crux_workspace/src/workspace_scopes.dart';
import 'package:crux_workspace/src/workspace_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Default debounce window for auto-saves triggered by workspace mutations.
const Duration kWorkspaceAutoSaveDebounce = Duration(seconds: 2);

/// Generic base class for the workspace `AsyncNotifier`.
///
/// Each product creates an
/// `AsyncNotifierProvider<WorkspaceNotifier<MyPayload>, Workspace<MyPayload>>`
/// whose factory hands in a [WorkspaceService] wired to that product's
/// payload codec:
///
/// ```dart
/// final workspaceProvider = AsyncNotifierProvider<
///   WorkspaceNotifier<MyPayload>,
///   Workspace<MyPayload>
/// >(
///   () => WorkspaceNotifier<MyPayload>(service: myService),
/// );
/// ```
///
/// The first read calls [WorkspaceService.load] and yields the result. Every
/// mutation method updates the in-memory state immediately and schedules a
/// debounced save so a burst of rapid edits collapses into a single disk
/// write. The notifier flushes any pending save on dispose.
///
/// Lifecycle integration is opt-in: products wire `flushPendingSave` into
/// their `WidgetsBindingObserver` (or use the supplied
/// `WorkspaceLifecycleObserver`) so that `AppLifecycleState.paused` and
/// `detached` trigger a synchronous final write.
class WorkspaceNotifier<P> extends AsyncNotifier<Workspace<P>> {
  /// Creates a workspace notifier backed by [service]. Pass an
  /// [autoSaveDebounce] of `Duration.zero` to disable debouncing in tests.
  WorkspaceNotifier({
    required this.service,
    this.autoSaveDebounce = kWorkspaceAutoSaveDebounce,
    Iterable<WorkspaceScopeReconciler> scopeReconcilers = const [],
  }) : _reconcilers = [...scopeReconcilers];

  /// Persistence backend supplied by the host product.
  final WorkspaceService<P> service;

  /// Debounce window between mutation and disk write.
  final Duration autoSaveDebounce;

  final List<WorkspaceScopeReconciler> _reconcilers;

  Timer? _pendingSave;
  Workspace<P>? _pendingPayload;

  /// Tail of the serialized save chain. Every save links onto this future so
  /// two writes can never be in flight at once — see [_startSave].
  Future<void> _saveChain = Future<void>.value();

  /// Whether the persisted workspace document is rehydrated at launch.
  ///
  /// Defaults to `true`. A product that exposes a "restore tabs on launch"
  /// preference overrides this to consult it — the gate has to live here,
  /// because [build] is the only production caller of
  /// [WorkspaceService.load] and a product cannot intercept it from outside.
  /// A product that instead closes the restored tabs after the fact has
  /// already paid for loading them, has already emitted a scope-reconcile for
  /// tabs it is about to discard, and races its own first save.
  ///
  /// Returning `false` starts from an empty workspace and **leaves the
  /// document on disk untouched**, so flipping the preference back on
  /// restores the session that was there. The document is only overwritten
  /// once the user mutates the fresh workspace, which is the point at which
  /// they have chosen a new session.
  ///
  /// It is asynchronous because settings usually arrive from asynchronous
  /// storage; resolving them eagerly here, before the first load, is what
  /// keeps the decision from being made against a default the user overrode.
  ///
  /// **Read the settings *service*, not another async provider.** Awaiting a
  /// second `AsyncNotifierProvider`'s `.future` from here hands the launch
  /// path to Riverpod's failure retry: a settings load that throws — no
  /// platform channel under a widget test, a plugin that has not registered
  /// yet — leaves this future pending across every retry, so the workspace
  /// never resolves and the app never renders. A plain service future either
  /// completes or throws once. Catch the throw and return `true`: losing a
  /// session because a *preference* was unreadable is the worse failure.
  Future<bool> shouldRestoreOnLaunch() async => true;

  @override
  Future<Workspace<P>> build() async {
    ref.onDispose(_flushAndCancelTimer);
    final restore = await shouldRestoreOnLaunch();
    final loaded = restore ? await service.load() : Workspace<P>.empty();
    // The freshly-hydrated document defines the live scope set. Reconciling
    // here matters when the notifier is rebuilt (provider invalidation,
    // hot restart) while the host's container managers survive: without it,
    // a persisted TabId that the managers still hold a container for would be
    // served the previous session's scope.
    _reconcileScopes(loaded);
    return loaded;
  }

  // ---------------------------------------------------------------------------
  // Scope eviction seam
  // ---------------------------------------------------------------------------

  /// Registers [reconciler] to receive the structural scope-eviction signal
  /// after every workspace state transition, and immediately reconciles it
  /// against the current state when the workspace has already loaded.
  ///
  /// Products register their [WorkspaceScopeReconciler]s here — at minimum the
  /// `TabContainerManager` and `PaneContainerManager` — typically right after
  /// constructing them, since those need the root `ProviderContainer` that is
  /// not available at notifier-construction time. Registering the same
  /// instance twice is a no-op.
  ///
  /// A product that skips this leaks a container per tab ever opened and
  /// resurrects dead tabs' state on workspace reload; see
  /// [WorkspaceScopeReconciler].
  void addScopeReconciler(WorkspaceScopeReconciler reconciler) {
    if (_reconcilers.any((r) => identical(r, reconciler))) return;
    _reconcilers.add(reconciler);
    final current = state.value;
    if (current != null) reconciler.reconcileScopes(_snapshotOf(current));
  }

  /// Unregisters a previously added [reconciler]. Returns whether it was
  /// registered. Does not evict anything the reconciler still holds.
  bool removeScopeReconciler(WorkspaceScopeReconciler reconciler) =>
      _reconcilers.remove(reconciler);

  WorkspaceScopeSnapshot _snapshotOf(Workspace<P> ws) => WorkspaceScopeSnapshot(
    tabIds: {for (final t in ws.tabs) t.id},
    paneIds: {for (final p in ws.panes) p.id},
  );

  void _reconcileScopes(Workspace<P> ws) => _emit(_snapshotOf(ws));

  void _emit(WorkspaceScopeSnapshot snapshot) {
    // Snapshot the list: a reconciler is allowed to unregister itself.
    for (final reconciler in [..._reconcilers]) {
      reconciler.reconcileScopes(snapshot);
    }
  }

  // ---------------------------------------------------------------------------
  // Mutation API
  // ---------------------------------------------------------------------------

  /// Finds the open tab whose payload has the same identity as [payload],
  /// per [WorkspaceCodec.identityOf].
  ///
  /// Returns `null` when the codec gives [payload] no identity (the default
  /// for a codec that has not opted in) or when nothing open matches.
  TabId? tabWithSameIdentityAs(P payload) {
    final current = state.value;
    if (current == null) return null;
    final identity = service.codec.identityOf(payload);
    if (identity == null) return null;
    for (final tab in current.tabs) {
      if (service.codec.identityOf(tab.payload) == identity) return tab.id;
    }
    return null;
  }

  /// Opens a tab for [payload], or focuses the tab already showing it.
  ///
  /// When [dedupe] is set and [WorkspaceCodec.identityOf] gives [payload] an
  /// identity that matches an open tab, no new tab is created: the existing
  /// one is activated (along with its pane) and its [TabId] is returned. This
  /// is what makes a command-line open of a project the user already has open
  /// *focus* that project rather than stack a second copy of it — the
  /// behaviour whose absence let one project accumulate a tab per launch,
  /// without bound.
  ///
  /// Dedupe is on by default and inert until a product's codec overrides
  /// `identityOf`, so it cannot change behaviour behind a product's back.
  /// Pass `dedupe: false` for the deliberate second view of one thing — a
  /// side-by-side comparison of the same file in two panes, say.
  ///
  /// Otherwise the tab is appended to the active pane unless [paneId] is
  /// supplied, and activated in its hosting pane.
  ///
  /// Returns the [TabId] of the tab now showing [payload], whether it was
  /// created or found.
  Future<TabId> openTab({
    required String displayName,
    required P payload,
    PaneId? paneId,
    bool dedupe = true,
  }) async {
    if (dedupe) {
      final existing = tabWithSameIdentityAs(payload);
      if (existing != null) {
        await setActiveTab(existing);
        return existing;
      }
    }
    final id = TabId.generate();
    await mutate((current) {
      final targetPane = paneId ?? current.activePaneId;
      if (!current.panes.any((p) => p.id == targetPane)) {
        throw StateError('openTab: unknown paneId $targetPane');
      }
      final tab = WorkspaceTab<P>(
        id: id,
        displayName: displayName,
        paneId: targetPane,
        payload: payload,
      );
      final tabs = [...current.tabs, tab];
      final panes = [
        for (final p in current.panes)
          if (p.id == targetPane) p.copyWith(activeTabId: id) else p,
      ];
      return current.copyWith(
        tabs: tabs,
        panes: panes,
        activePaneId: targetPane,
      );
    });
    return id;
  }

  /// Closes the tab identified by [id]. When the closed tab was the active
  /// tab in its pane, picks the adjacent surviving tab (next, then previous)
  /// as the new active tab. When the pane has no remaining tabs and is not
  /// the sole pane, the pane itself is removed and the surviving sibling
  /// pane becomes the active pane.
  Future<void> closeTab(TabId id) async {
    await mutate((current) {
      final idx = current.tabs.indexWhere((t) => t.id == id);
      if (idx == -1) return current;
      final removed = current.tabs[idx];
      final remainingTabs = [...current.tabs]..removeAt(idx);

      final paneSiblings = remainingTabs
          .where((t) => t.paneId == removed.paneId)
          .toList();

      final panes = <WorkspacePane>[];
      var activePaneId = current.activePaneId;
      for (final pane in current.panes) {
        if (pane.id != removed.paneId) {
          panes.add(pane);
          continue;
        }
        if (paneSiblings.isEmpty) {
          if (current.panes.length > 1) {
            if (activePaneId == pane.id) {
              activePaneId = current.panes
                  .firstWhere((p) => p.id != pane.id)
                  .id;
            }
            continue;
          }
          panes.add(pane.withoutActiveTab());
          continue;
        }
        if (pane.activeTabId == id) {
          final paneTabsInOrder = remainingTabs
              .where((t) => t.paneId == pane.id)
              .toList(growable: false);
          // Adjacency is pane-local: the removed tab's position within its
          // pane's (filtered) tab list, not its position in the global tab
          // list. The survivor now occupying that pane-local slot is the
          // "next" tab; when the removed tab was the pane's last, fall back
          // to the previous one.
          final paneLocalIdx = current.tabs
              .where((t) => t.paneId == pane.id)
              .toList(growable: false)
              .indexWhere((t) => t.id == id);
          final newActive =
              paneTabsInOrder[paneLocalIdx < paneTabsInOrder.length
                  ? paneLocalIdx
                  : paneTabsInOrder.length - 1];
          panes.add(pane.copyWith(activeTabId: newActive.id));
        } else {
          panes.add(pane);
        }
      }

      return current.copyWith(
        tabs: remainingTabs,
        panes: panes,
        activePaneId: activePaneId,
      );
    });
  }

  /// Moves the tab identified by [id] to position [newIndex] within the
  /// workspace tab list. Cross-pane reordering preserves
  /// [WorkspaceTab.paneId] — use [moveTabToPane] to switch panes.
  Future<void> reorderTab(TabId id, int newIndex) async {
    await mutate((current) {
      final idx = current.tabs.indexWhere((t) => t.id == id);
      if (idx == -1) return current;
      final tabs = [...current.tabs];
      final tab = tabs.removeAt(idx);
      final clamped = newIndex.clamp(0, tabs.length);
      tabs.insert(clamped, tab);
      return current.copyWith(tabs: tabs);
    });
  }

  /// Reorders the tab identified by [id] to a pane-local [paneLocalIndex]
  /// within [pane], translating that pane-local position into the correct
  /// global tab-list index.
  ///
  /// A per-pane tab strip filters the workspace's tabs by `paneId`, so the
  /// drop index it computes is relative to that pane's own (filtered) list.
  /// Passing such a pane-local index straight to [reorderTab] — which indexes
  /// the *global* tab list — lands the tab at the wrong position whenever an
  /// earlier pane already holds tabs (the split-pane case). This method does
  /// the local→global mapping so a per-pane reorder is correct regardless of
  /// how many tabs other panes hold.
  Future<void> reorderTabInPane(
    TabId id,
    PaneId pane,
    int paneLocalIndex,
  ) async {
    await mutate((current) {
      final idx = current.tabs.indexWhere((t) => t.id == id);
      if (idx == -1) return current;
      final paneTabs = current.tabsForPane(pane);
      final globalIndex = paneLocalIndex < paneTabs.length
          ? current.tabs.indexOf(paneTabs[paneLocalIndex])
          : (paneTabs.isEmpty
                ? current.tabs.length
                : current.tabs.indexOf(paneTabs.last) + 1);
      final tabs = [...current.tabs];
      final tab = tabs.removeAt(idx);
      final clamped = globalIndex.clamp(0, tabs.length);
      tabs.insert(clamped, tab);
      return current.copyWith(tabs: tabs);
    });
  }

  /// Reassigns [tabId] to [targetPane] and activates it there. When the move
  /// empties the source pane and it is not the sole pane, the source pane is
  /// removed and the active pane follows the moved tab — mirroring
  /// [closeTab]'s empty-pane pruning so a tab dragged out of a pane never
  /// leaves a phantom empty pane behind. When the source pane survives but
  /// the moved tab was its active tab, the first surviving sibling becomes
  /// the source pane's active tab. No-op when the tab is already hosted by
  /// [targetPane] or when [targetPane] does not exist.
  Future<void> moveTabToPane(TabId tabId, PaneId targetPane) async {
    await mutate((current) {
      if (!current.panes.any((p) => p.id == targetPane)) return current;
      final idx = current.tabs.indexWhere((t) => t.id == tabId);
      if (idx == -1) return current;
      final sourcePane = current.tabs[idx].paneId;
      if (sourcePane == targetPane) return current;

      final tabs = [...current.tabs];
      tabs[idx] = tabs[idx].copyWith(paneId: targetPane);

      // Tabs that remain in the source pane after the move.
      final sourceSiblings = tabs
          .where((t) => t.paneId == sourcePane)
          .toList(growable: false);
      // Collapse the source pane when the move empties it, unless it is the
      // sole pane (mirrors closeTab's empty-pane pruning).
      final collapseSource = sourceSiblings.isEmpty && current.panes.length > 1;

      var activePaneId = current.activePaneId;
      final panes = <WorkspacePane>[];
      for (final pane in current.panes) {
        if (pane.id == targetPane) {
          panes.add(pane.copyWith(activeTabId: tabId));
          continue;
        }
        if (pane.id != sourcePane) {
          panes.add(pane);
          continue;
        }
        // The source pane.
        if (collapseSource) {
          // Drop the now-empty pane; move focus onto the tab's new home if
          // the emptied pane was the active one.
          if (activePaneId == pane.id) activePaneId = targetPane;
          continue;
        }
        if (pane.activeTabId == tabId) {
          // The moved tab was active here but the pane still has tabs — pick
          // the first survivor so the pane never renders without a selection.
          panes.add(pane.copyWith(activeTabId: sourceSiblings.first.id));
        } else {
          panes.add(pane);
        }
      }

      return current.copyWith(
        tabs: tabs,
        panes: panes,
        activePaneId: activePaneId,
      );
    });
  }

  /// Activates [id] in its hosting pane and focuses that pane.
  Future<void> setActiveTab(TabId id) async {
    await mutate((current) {
      final tab = current.tabs.firstWhere(
        (t) => t.id == id,
        orElse: () => throw StateError('setActiveTab: unknown tab $id'),
      );
      final panes = [
        for (final p in current.panes)
          if (p.id == tab.paneId) p.copyWith(activeTabId: id) else p,
      ];
      return current.copyWith(panes: panes, activePaneId: tab.paneId);
    });
  }

  /// Marks [paneId] as the active pane. No-op when [paneId] is not part of
  /// the workspace or is already active. Does not change either pane's
  /// active tab.
  Future<void> setActivePane(PaneId paneId) async {
    await mutate((c) {
      if (c.activePaneId == paneId) return c;
      if (!c.panes.any((p) => p.id == paneId)) return c;
      return c.copyWith(activePaneId: paneId);
    });
  }

  /// Splits the workspace into two panes. When the active pane has more than
  /// one tab, the active tab moves into the new (right) pane; otherwise the
  /// new pane opens empty. No-op when the workspace is already split — the
  /// active pane id is returned in that case.
  ///
  /// Returns the id of the newly-created (or already-active) pane.
  Future<PaneId> splitPaneRight() async {
    var resultId = state.requireValue.activePaneId;
    await mutate((c) {
      if (c.panes.length >= 2) {
        resultId = c.activePaneId;
        return c;
      }
      final newPane = WorkspacePane(id: PaneId.generate());
      resultId = newPane.id;

      // Move the active tab into the new pane when the source pane has more
      // than one tab. When the source has exactly one tab, the new pane
      // opens empty.
      final sourcePaneTabs = c.tabs
          .where((t) => t.paneId == c.activePaneId)
          .toList();
      final activeTabId = c.activePane.activeTabId;
      if (sourcePaneTabs.length > 1 && activeTabId != null) {
        final tabs = [
          for (final t in c.tabs)
            if (t.id == activeTabId) t.copyWith(paneId: newPane.id) else t,
        ];
        final remainingInSource = sourcePaneTabs
            .where((t) => t.id != activeTabId)
            .toList();
        final panes = [
          for (final p in c.panes)
            if (p.id == c.activePaneId)
              p.copyWith(activeTabId: remainingInSource.first.id)
            else
              p,
          newPane.copyWith(activeTabId: activeTabId),
        ];
        return c.copyWith(
          tabs: tabs,
          panes: panes,
          activePaneId: newPane.id,
        );
      }
      return c.copyWith(
        panes: [...c.panes, newPane],
        activePaneId: newPane.id,
      );
    });
    return resultId;
  }

  /// Closes [paneId], merging any tabs it hosts into the surviving pane.
  /// Refuses to close the sole pane (no-op).
  Future<void> closePane(PaneId paneId) async {
    await mutate((c) {
      if (c.panes.length < 2) return c;
      if (!c.panes.any((p) => p.id == paneId)) return c;
      final survivor = c.panes.firstWhere((p) => p.id != paneId).id;
      final tabs = [
        for (final t in c.tabs)
          if (t.paneId == paneId) t.copyWith(paneId: survivor) else t,
      ];
      final panes = c.panes.where((p) => p.id != paneId).toList();
      final activePaneId = c.activePaneId == paneId ? survivor : c.activePaneId;
      return c.copyWith(tabs: tabs, panes: panes, activePaneId: activePaneId);
    });
  }

  /// Toggles focus to the other pane when split, no-op otherwise.
  Future<void> focusOtherPane() async {
    await mutate((c) {
      if (c.panes.length < 2) return c;
      final other = c.panes.firstWhere((p) => p.id != c.activePaneId).id;
      return c.copyWith(activePaneId: other);
    });
  }

  /// Replaces the workspace with [Workspace.empty]. Triggers a save.
  ///
  /// Every per-tab and per-pane scope is evicted first — this is a wholesale
  /// document replacement, so nothing from the outgoing workspace may survive
  /// into the new one.
  Future<void> resetWorkspace() async {
    await _replaceDocument((_) => Workspace<P>.empty());
  }

  /// Replaces the per-tab payload of [tabId] by running [update] over the
  /// current payload. The update function must return a new immutable
  /// payload; in-place mutations are not detected by Riverpod and will not
  /// trigger a rebuild.
  Future<void> updateTabPayload(TabId tabId, P Function(P payload) update) =>
      mutate((c) {
        final idx = c.tabs.indexWhere((t) => t.id == tabId);
        if (idx == -1) return c;
        final tab = c.tabs[idx];
        final tabs = [...c.tabs];
        tabs[idx] = tab.copyWith(payload: update(tab.payload));
        return c.copyWith(tabs: tabs);
      });

  /// Updates the displayed tab title for [tabId].
  Future<void> updateTabDisplayName(TabId tabId, String displayName) =>
      mutate((c) {
        final idx = c.tabs.indexWhere((t) => t.id == tabId);
        if (idx == -1) return c;
        final tab = c.tabs[idx];
        if (tab.displayName == displayName) return c;
        final tabs = [...c.tabs];
        tabs[idx] = tab.copyWith(displayName: displayName);
        return c.copyWith(tabs: tabs);
      });

  /// Replaces the current workspace with [next]. Use when loading a named
  /// workspace document via [loadFrom].
  ///
  /// Every per-tab and per-pane scope is evicted before [next] is installed.
  /// This is deliberately unconditional: workspace documents persist their
  /// [TabId]s, so a loaded document can legitimately reuse an id the outgoing
  /// document also used, and the reused id must NOT inherit the outgoing
  /// tab's scope. Pruning to "ids not present in [next]" would silently keep
  /// it — the resurrection bug this seam exists to prevent.
  ///
  /// **Not a general-purpose setter.** Because the eviction is unconditional,
  /// routing an *incremental* change (a new tab, a pane split, an `extras`
  /// write) through this method tears down the containers of tabs that are
  /// still on screen. Subclasses use [mutate] for those; see its doc comment
  /// for the failure mode.
  Future<void> replaceWith(Workspace<P> next) => _replaceDocument((_) => next);

  // ---------------------------------------------------------------------------
  // Named workspace API
  // ---------------------------------------------------------------------------

  /// Writes the current workspace to [path] as a named workspace document.
  /// Wraps [WorkspaceService.saveToPath]; I/O failures propagate so callers
  /// can surface a save-failure dialog.
  Future<void> saveAs(String path) async {
    final current = await future;
    await service.saveToPath(path, current);
  }

  /// Loads a named workspace document from [path] and replaces the current
  /// in-memory workspace with it. Returns the loaded workspace.
  ///
  /// When the document cannot be read, [WorkspaceService.loadFromPath] throws
  /// a `WorkspaceLoadException` and the current workspace is left untouched —
  /// the replacement (and the auto-save it schedules) only happens for a
  /// successfully decoded document. Callers catch the exception to present
  /// the failure.
  Future<Workspace<P>> loadFrom(String path) async {
    final loaded = await service.loadFromPath(path);
    await replaceWith(loaded);
    return loaded;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Forces any pending debounced save to flush immediately. Wired into the
  /// host product's `AppLifecycleState.paused` / `detached` handlers so that
  /// the app's last in-memory state survives a hard quit.
  ///
  /// Also awaits any save already in flight so callers reliably observe the
  /// post-save filesystem state.
  Future<void> flushPendingSave() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    final payload = _pendingPayload;
    _pendingPayload = null;
    if (payload != null) unawaited(_startSave(payload));
    // Await the TAIL of the chain, not just the most recently started write:
    // an earlier save may still be running, and returning before it settles
    // would let a caller observe a stale on-disk document (or, worse, race a
    // subsequent write against it).
    await _saveChain;
  }

  /// Applies [update] to the current document **in place**: the resulting
  /// state is installed, scopes are reconciled against it (only the ids the
  /// new document no longer declares are evicted), and a debounced save is
  /// scheduled.
  ///
  /// **This — not [replaceWith] — is the mutation primitive a subclass reaches
  /// for.** Every incremental change (adding a tab, splitting a pane, writing
  /// an `extras` entry) must go through here. [replaceWith] is a *wholesale
  /// document replacement*: it evicts **every** per-tab and per-pane
  /// `ProviderContainer` before installing the next document, which is correct
  /// only when the incoming document is a different document (workspace open,
  /// reset). Routing an incremental change through it destroys the live
  /// containers of tabs that are still on screen; the host's per-tab
  /// `UncontrolledProviderScope` then rebuilds with a *fresh* container under
  /// a widget subtree whose keys kept the old elements alive, and any nested
  /// `ProviderScope` inside that subtree throws `ProviderScope was rebuilt
  /// with a different ProviderScope ancestor` (WaveCrux hit exactly this by
  /// persisting window geometry through [replaceWith] on every window resize).
  @protected
  Future<void> mutate(
    Workspace<P> Function(Workspace<P> current) update,
  ) async {
    final current = await future;
    final next = update(current);
    if (identical(next, current) || next == current) return;
    state = AsyncData(next);
    // Emit AFTER the state update so the host rebuilds against fresh scopes.
    _reconcileScopes(next);
    _scheduleSave(next);
  }

  /// Wholesale document replacement: evicts every scope before installing the
  /// new document, then reconciles against it. See [replaceWith].
  Future<void> _replaceDocument(
    Workspace<P> Function(Workspace<P> current) update,
  ) async {
    final current = await future;
    final next = update(current);
    _emit(const WorkspaceScopeSnapshot.empty());
    if (identical(next, current) || next == current) {
      // Same shape, but the scopes are gone — reconcile so any reconciler
      // that rebuilt lazily is consistent with the (unchanged) state.
      _reconcileScopes(next);
      return;
    }
    state = AsyncData(next);
    _reconcileScopes(next);
    _scheduleSave(next);
  }

  void _scheduleSave(Workspace<P> payload) {
    _pendingPayload = payload;
    _pendingSave?.cancel();
    if (autoSaveDebounce == Duration.zero) {
      // Kick off the save eagerly so back-to-back mutations coalesce on the
      // most-recent payload; [flushPendingSave] awaits the chain tail.
      unawaited(_startSave(payload));
      _pendingPayload = null;
      return;
    }
    _pendingSave = Timer(autoSaveDebounce, () {
      unawaited(flushPendingSave());
    });
  }

  /// Links a save for [payload] onto the end of [_saveChain].
  ///
  /// Serializing writes is not a nicety: [WorkspaceService.save] writes a temp
  /// sibling and renames it over the destination, so two overlapping saves
  /// would race — the second rename can land on a path the first already
  /// consumed (silently dropping a save) or, in the worst interleaving,
  /// publish a half-written document. A quit during the debounce window is
  /// enough to produce the overlap: `flushPendingSave` starts a write while
  /// the debounced one is still running.
  Future<void> _startSave(Workspace<P> payload) {
    final next = _saveChain
        // The service swallows and logs its own I/O errors; this guard only
        // stops one failed link from poisoning every later save in the chain.
        .then((_) => service.save(payload))
        .catchError((Object _) {});
    _saveChain = next;
    return next;
  }

  void _flushAndCancelTimer() {
    final pending = _pendingPayload;
    _pendingSave?.cancel();
    _pendingSave = null;
    _pendingPayload = null;
    if (pending != null) {
      // Fire-and-forget: the provider is being disposed, but the write is
      // still chained behind any in-flight save, and the service's atomic
      // write protects against a partial document.
      unawaited(_startSave(pending));
    }
  }
}
