// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/id_providers.dart';
import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/scoped_container_manager.dart';
import 'package:crux_workspace/src/tab_container_manager.dart';
import 'package:crux_workspace/src/workspace_scopes.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Function that produces the per-pane override list applied on top of
/// [paneIdProvider] for a freshly-created pane `ProviderContainer`.
///
/// Products implement this to register their per-pane providers (render
/// stats, focus, etc.) inside the container. The supplied [PaneId] is the
/// same value used to override [paneIdProvider].
typedef PaneOverridesFactory = List<Override> Function(PaneId paneId);

/// Manages the lifecycle of per-pane `ProviderContainer` instances.
///
/// Each pane gets its own container parented to the supplied root
/// container. The container carries the pane's [PaneId] (via
/// [paneIdProvider]) plus any per-pane providers contributed by the
/// supplied [PaneOverridesFactory].
///
/// Containers are cached by pane id. Eviction is **structural**: the manager
/// implements [WorkspaceScopeReconciler], so once it is registered with the
/// product's `WorkspaceNotifier` (via `addScopeReconciler`) every workspace
/// mutation prunes the containers of panes that no longer exist — closing a
/// split, collapsing an emptied pane, or loading a different workspace
/// document. [disposePane] remains available for one-off eviction and
/// [dispose] tears down every container.
///
/// The caching, eviction and reconcile behaviour lives in
/// [ScopedContainerManager]; this class binds it to the pane key space. It is
/// a distinct type from [TabContainerManager] on purpose — see
/// [ScopedContainerManager] for why the two id types are never unified.
class PaneContainerManager extends ScopedContainerManager<PaneId> {
  /// Creates a pane container manager whose new containers are parented to
  /// the supplied root container, optionally extended with per-pane
  /// overrides supplied by the factory.
  ///
  /// [overridesFactory] is a [PaneOverridesFactory] — the alias is retained as
  /// the documented product-facing name; structurally it is the base class's
  /// `ScopeOverridesFactory<PaneId>`.
  PaneContainerManager({
    required super.rootContainer,
    super.overridesFactory,
  }) : super(idProvider: paneIdProvider);

  /// Reads the pane half of the snapshot; the tab half is ignored.
  @override
  Set<PaneId> liveIdsIn(WorkspaceScopeSnapshot live) => live.paneIds;

  /// Disposes the container for [paneId] and removes it from the cache.
  /// No-op when no container exists for [paneId].
  void disposePane(PaneId paneId) => disposeScope(paneId);
}
