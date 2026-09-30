// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/id_providers.dart';
import 'package:crux_workspace/src/pane_container_manager.dart';
import 'package:crux_workspace/src/scoped_container_manager.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/workspace_scopes.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Function that produces the per-tab override list applied on top of
/// [tabIdProvider] for a freshly-created tab `ProviderContainer`.
///
/// Products implement this to register their per-tab providers (cursor,
/// zoom, signal groups, etc.) inside the container. The supplied [TabId]
/// is the same value used to override [tabIdProvider].
typedef TabOverridesFactory = List<Override> Function(TabId tabId);

/// Manages the lifecycle of per-tab `ProviderContainer` instances.
///
/// Each tab gets its own container parented to the supplied root container.
/// The container carries the tab's [TabId] (via [tabIdProvider]) plus any
/// per-tab providers contributed by the supplied [TabOverridesFactory].
///
/// Containers are cached by tab id. Eviction is **structural**: the manager
/// implements [WorkspaceScopeReconciler], so once it is registered with the
/// product's `WorkspaceNotifier` (via `addScopeReconciler`) every workspace
/// mutation prunes the containers of tabs that no longer exist. [disposeTab]
/// remains available for one-off eviction and [dispose] tears down every
/// container.
///
/// Registering the manager is not optional in a product: without it, closed
/// tabs leak their container *and* a workspace reload that revives a persisted
/// [TabId] hands the "new" tab the dead tab's container — see
/// [WorkspaceScopeReconciler] for the full rationale.
///
/// The caching, eviction and reconcile behaviour lives in
/// [ScopedContainerManager]; this class binds it to the tab key space. It is a
/// distinct type from [PaneContainerManager] on purpose — see
/// [ScopedContainerManager] for why the two id types are never unified.
class TabContainerManager extends ScopedContainerManager<TabId> {
  /// Creates a tab container manager whose new containers are parented to
  /// the supplied root container, optionally extended with per-tab
  /// overrides supplied by the factory.
  /// [overridesFactory] is a [TabOverridesFactory] — the alias is retained as
  /// the documented product-facing name; structurally it is the base class's
  /// `ScopeOverridesFactory<TabId>`.
  TabContainerManager({
    required super.rootContainer,
    super.overridesFactory,
  }) : super(idProvider: tabIdProvider);

  /// Reads the tab half of the snapshot; the pane half is ignored.
  @override
  Set<TabId> liveIdsIn(WorkspaceScopeSnapshot live) => live.tabIds;

  /// Disposes the container for [tabId] and removes it from the cache.
  /// No-op when no container exists for [tabId].
  void disposeTab(TabId tabId) => disposeScope(tabId);
}
