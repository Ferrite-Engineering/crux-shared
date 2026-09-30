// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:meta/meta.dart';

/// Immutable snapshot of the scope keys a workspace currently declares alive.
///
/// Produced by `WorkspaceNotifier` after every state transition and handed to
/// each registered [WorkspaceScopeReconciler]. A reconciler reads whichever
/// set it owns — [tabIds] for per-tab resources, [paneIds] for per-pane ones —
/// and evicts everything it holds that is *not* in that set.
///
/// Pure Dart — no Flutter imports.
@immutable
class WorkspaceScopeSnapshot {
  /// Creates a snapshot of the live tab and pane ids.
  const WorkspaceScopeSnapshot({
    required this.tabIds,
    required this.paneIds,
  });

  /// The snapshot in which nothing is alive. Emitted before a wholesale
  /// document replacement (`replaceWith` / `loadFrom` / `resetWorkspace`) so
  /// every scope is torn down even when the incoming document reuses the same
  /// ids — see [WorkspaceScopeReconciler] for why that matters.
  const WorkspaceScopeSnapshot.empty()
    : tabIds = const <TabId>{},
      paneIds = const <PaneId>{};

  /// Ids of every tab present in the workspace.
  final Set<TabId> tabIds;

  /// Ids of every pane present in the workspace.
  final Set<PaneId> paneIds;

  @override
  String toString() =>
      'WorkspaceScopeSnapshot(tabs: ${tabIds.length}, '
      'panes: ${paneIds.length})';
}

/// Sink for the workspace's **structural** scope-eviction signal.
///
/// ### Why this exists
///
/// Anything keyed by [TabId] or [PaneId] — a per-tab `ProviderContainer`, a
/// file watcher, a debounce timer, a decoded-waveform cache — outlives the tab
/// unless something tells it the tab is gone. Relying on each call site to
/// remember to call a `disposeTab`-style method is opt-in eviction, and opt-in
/// eviction fails in two ways that have both been observed in this suite:
///
/// 1. **Leak.** Nothing calls the disposal method, so every tab ever opened
///    retains its scope for the process lifetime.
/// 2. **Resurrection.** `TabId`s round-trip through the workspace JSON
///    document, so loading a saved workspace revives an id that a cache still
///    holds an entry for — and the "new" tab silently inherits the dead tab's
///    state. This is the more dangerous failure: it presents as cross-tab
///    state bleed, not as memory growth.
///
/// `WorkspaceNotifier` therefore emits a [WorkspaceScopeSnapshot] after every
/// state transition and every registered reconciler prunes itself against it.
/// Eviction becomes a property of the workspace's shape rather than a call a
/// contributor has to remember.
///
/// ### Replacement versus mutation
///
/// A mutation (close a tab, close a pane) emits the surviving snapshot, so
/// only the removed scopes are evicted. A wholesale replacement
/// (`replaceWith`, `loadFrom`, `resetWorkspace`) first emits
/// [WorkspaceScopeSnapshot.empty] and *then* the incoming snapshot: a
/// different workspace document that happens to reuse an id is a different
/// tab, and it must not inherit the previous document's scope.
///
/// ### Implementing one
///
/// `TabContainerManager` and `PaneContainerManager` already implement this.
/// Products with their own per-tab or per-pane resources implement it too and
/// register via `WorkspaceNotifier.addScopeReconciler`; each implementation
/// ignores the half of the snapshot it does not own.
///
/// Reconcilers are invoked **synchronously, after** the notifier's state has
/// been updated, so the host rebuilds against fresh scopes on the next frame.
/// An implementation must not throw and must not mutate the workspace.
// A named role implemented by several unrelated classes (the container
// managers here, product-side caches and watchers downstream) — not a
// callback type, so the single member is intentional.
// ignore: one_member_abstracts
abstract interface class WorkspaceScopeReconciler {
  /// Evicts every resource this reconciler holds whose owning tab or pane is
  /// absent from [live].
  void reconcileScopes(WorkspaceScopeSnapshot live);
}
