// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/workspace_scopes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:meta/meta.dart';

/// Produces the per-scope override list applied on top of the scope's id
/// provider when a fresh `ProviderContainer` is created for [Id].
typedef ScopeOverridesFactory<Id extends Object> =
    List<Override> Function(Id id);

/// Shared implementation behind `TabContainerManager` and
/// `PaneContainerManager`: a cache of child `ProviderContainer`s keyed by a
/// scope id, with structural eviction driven by [WorkspaceScopeReconciler].
///
/// ### Why this is generic and the subclasses are not
///
/// The tab and pane managers were token-for-token identical modulo
/// `Tab`→`Pane`, and both grew the same `reconcile` contract, so keeping two
/// copies meant every future change to the eviction contract had to be made
/// twice and stay in sync by inspection.
///
/// The generic parameter is deliberately **not** erased to a common `ScopeId`
/// supertype. `TabId` and `PaneId` have no common ancestor beyond [Object],
/// and that is the point: handing a `PaneId` to something expecting a `TabId`
/// is precisely the bug class this substrate exists to prevent, and a shared
/// supertype would make that mistake compile. `ScopedContainerManager<TabId>`
/// and `ScopedContainerManager<PaneId>` are unrelated types with unrelated
/// method signatures — deduplicating the *implementation* costs nothing at
/// the type level.
///
/// Products do not name this class; they use `TabContainerManager` and
/// `PaneContainerManager`, whose public surface is unchanged.
abstract class ScopedContainerManager<Id extends Object>
    implements WorkspaceScopeReconciler {
  /// Creates a manager whose containers are parented to [rootContainer] and
  /// each carry their own [Id] via [idProvider], plus whatever
  /// [overridesFactory] contributes.
  ScopedContainerManager({
    required ProviderContainer rootContainer,
    required Provider<Id> idProvider,
    ScopeOverridesFactory<Id>? overridesFactory,
  }) : this._(
         rootContainer,
         idProvider,
         overridesFactory ?? _noOverrides,
       );

  ScopedContainerManager._(
    this._rootContainer,
    this._idProvider,
    this._overridesFactory,
  );

  static List<Override> _noOverrides(Object _) => const [];

  final ProviderContainer _rootContainer;
  final Provider<Id> _idProvider;
  final ScopeOverridesFactory<Id> _overridesFactory;
  final Map<Id, ProviderContainer> _containers = {};

  /// The half of [WorkspaceScopeSnapshot] this manager owns.
  ///
  /// Implemented by each subclass — the tab manager reads
  /// [WorkspaceScopeSnapshot.tabIds], the pane manager
  /// [WorkspaceScopeSnapshot.paneIds] — so that neither can accidentally
  /// reconcile itself against the other's key space.
  @protected
  Set<Id> liveIdsIn(WorkspaceScopeSnapshot live);

  /// Returns the existing `ProviderContainer` for [id] or creates one if none
  /// exists. The returned container is parented to the root container and
  /// remains alive until it is evicted by [reconcile], [disposeScope], or
  /// [dispose].
  ProviderContainer containerFor(Id id) {
    final existing = _containers[id];
    if (existing != null) return existing;
    final container = ProviderContainer(
      parent: _rootContainer,
      overrides: <Override>[
        _idProvider.overrideWithValue(id),
        ..._overridesFactory(id),
      ],
    );
    _containers[id] = container;
    return container;
  }

  /// Returns whether a container has been created for [id].
  bool hasContainerFor(Id id) => _containers.containsKey(id);

  /// Disposes the container for [id] and removes it from the cache.
  /// No-op when no container exists for [id].
  void disposeScope(Id id) => _containers.remove(id)?.dispose();

  /// Disposes and removes the container of every cached scope that is **not**
  /// in [liveIds]. Returns the ids that were evicted (empty when nothing
  /// changed), which callers can use for diagnostics.
  ///
  /// Passing an empty set evicts everything while leaving the manager usable —
  /// unlike [dispose], which is terminal. That is the wholesale-replacement
  /// path: a freshly loaded workspace document must not inherit scopes from
  /// the document it replaced, even when the two share ids.
  Set<Id> reconcile(Set<Id> liveIds) {
    final stale = _containers.keys.where((id) => !liveIds.contains(id)).toSet();
    for (final id in stale) {
      _containers.remove(id)?.dispose();
    }
    return stale;
  }

  @override
  void reconcileScopes(WorkspaceScopeSnapshot live) =>
      reconcile(liveIdsIn(live));

  /// Disposes every cached container and clears the cache. After this call
  /// the manager is unusable; create a fresh instance if needed.
  void dispose() {
    for (final container in _containers.values) {
      container.dispose();
    }
    _containers.clear();
  }
}
