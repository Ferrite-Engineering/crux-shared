// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/src/project_descriptor.dart';
import 'package:crux_projects/src/project_workspace.dart';

/// Extension-point interface managing the set of projects loaded into a
/// product's multi-project workspace.
///
/// Open-core ships [NoopProjectRegistry] as the default — a single-project
/// surface where opening a project replaces the previous one and recent
/// projects are never retained. The Pro overlay overrides
/// `projectRegistryProvider` with a persistent multi-project implementation
/// that loads / closes / pins / restores projects across app restarts. This
/// follows the suite-wide extension-point convention: the interface and a
/// no-op default ship in open-core, and the paid overlay supplies the real
/// implementation by overriding one provider, so no open-core widget ever
/// needs to know a Pro build exists. That implementation is the paid
/// capability itself, which is why it is not in this package.
abstract class ProjectRegistry {
  /// Open the project at [projectPath]. If the project is already
  /// open it is set active without reloading; otherwise a new
  /// [ProjectDescriptor] is added to the workspace and made active.
  ///
  /// Returns the resulting descriptor. Implementations are free to
  /// reject invalid paths by throwing [ProjectLoadException]; callers
  /// surface the failure to the user (snackbar, dialog).
  Future<ProjectDescriptor> openProject(String projectPath);

  /// Close the project identified by [projectId].
  ///
  /// Moves the descriptor to `recentProjects` (capped at
  /// [ProjectWorkspace.recentProjectsCap]) unless [hardClose] is
  /// true, in which case the descriptor is dropped entirely.
  /// Pinned projects survive `closeAllProjects` flows; closing a
  /// pinned project individually unpins it implicitly.
  ///
  /// If the closed project was active, the next-most-recent open
  /// project becomes active (or null when the workspace becomes
  /// empty). No-op when [projectId] is not currently open.
  Future<void> closeProject(String projectId, {bool hardClose = false});

  /// Close every project that is not pinned. Pinned projects remain
  /// open; the workspace falls back to single-pane / single-tab on
  /// the most-recently-active surviving project (or empty when
  /// none remain).
  Future<void> closeAllProjects();

  /// Set the active project to [projectId]. Updates
  /// `lastAccessedAt` on the descriptor. No-op when [projectId] is
  /// not currently open.
  Future<void> setActiveProject(String projectId);

  /// Pin or unpin [projectId]. Pinned projects survive
  /// [closeAllProjects]. No-op when [projectId] is not currently
  /// open.
  Future<void> pinProject(String projectId, {required bool pinned});

  /// Reorder open projects to match [newOrderIds]. Ids must each
  /// resolve to a currently-open project; ids not in the workspace
  /// are silently ignored. Used by the drag-to-reorder tab gesture.
  Future<void> reorderProjects(List<String> newOrderIds);

  /// Drop [projectId] from the recent-projects list. No-op when
  /// [projectId] is not currently in `recentProjects`.
  Future<void> clearRecentProject(String projectId);

  /// Tear down every project (open + recent) and clear persisted
  /// workspace state. Used by `resetWorkspace`. Pro implementations
  /// should also delete the persisted workspace.json file.
  Future<void> shutdownAll();

  /// Live workspace snapshot. Emits on every mutation; replays the
  /// current snapshot to new listeners.
  Stream<ProjectWorkspace> watch();

  /// Synchronous read of the current workspace snapshot.
  ProjectWorkspace get current;
}

/// Thrown by [ProjectRegistry.openProject] when [projectPath] cannot
/// be loaded — the file is missing, unreadable, or fails project
/// validation.
class ProjectLoadException implements Exception {
  /// Creates a [ProjectLoadException].
  const ProjectLoadException(this.projectPath, this.reason, {this.cause});

  /// Path the caller asked the registry to open.
  final String projectPath;

  /// Human-readable reason for the failure.
  final String reason;

  /// Underlying exception, when available.
  final Object? cause;

  @override
  String toString() => 'ProjectLoadException($projectPath: $reason)';
}

/// Default open-core [ProjectRegistry] implementing single-project
/// semantics.
///
/// Behavior:
///   * [openProject] **replaces** any currently-open project (rather
///     than tabbing alongside it). This matches the pre-multi-project
///     UX where opening a project from the file picker swaps out the
///     dashboard's content.
///   * [closeProject] hard-clears — `recentProjects` always returns
///     empty under the no-op default.
///   * [pinProject] silently no-ops (single-project mode has nothing
///     to survive a close-all action).
///   * [reorderProjects] silently no-ops (one tab has no order).
///   * [closeAllProjects] is the same as closing the active project.
///
/// The Pro overlay installs a richer multi-project registry via
/// `proOverrides`; that registry persists workspace state, supports
/// many open tabs, and retains recent projects.
class NoopProjectRegistry implements ProjectRegistry {
  /// Creates a [NoopProjectRegistry] with an optional injected clock
  /// for deterministic tests.
  NoopProjectRegistry({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _Bus<ProjectWorkspace> _bus = _Bus<ProjectWorkspace>();
  ProjectWorkspace _workspace = ProjectWorkspace.empty();

  @override
  ProjectWorkspace get current => _workspace;

  @override
  Future<ProjectDescriptor> openProject(String projectPath) async {
    final now = _clock();
    final descriptor = ProjectDescriptor(
      id: ProjectDescriptor.idForPath(projectPath),
      displayName: _basename(projectPath),
      projectPath: projectPath,
      loadedAt: now,
      lastAccessedAt: now,
    );
    _workspace = ProjectWorkspace(
      openProjects: <ProjectDescriptor>[descriptor],
      activeProjectId: descriptor.id,
    );
    _bus.add(_workspace);
    return descriptor;
  }

  @override
  Future<void> closeProject(
    String projectId, {
    bool hardClose = false,
  }) async {
    if (!_workspace.openProjects.any((p) => p.id == projectId)) return;
    _workspace = ProjectWorkspace.empty();
    _bus.add(_workspace);
  }

  @override
  Future<void> closeAllProjects() async {
    _workspace = ProjectWorkspace.empty();
    _bus.add(_workspace);
  }

  @override
  Future<void> setActiveProject(String projectId) async {
    if (!_workspace.openProjects.any((p) => p.id == projectId)) return;
    // Single-project mode: the only open project is always active.
    _workspace = _workspace.copyWith(activeProjectId: projectId);
    _bus.add(_workspace);
  }

  @override
  Future<void> pinProject(String projectId, {required bool pinned}) async {
    // Single-project mode: nothing to pin against; surface the
    // attempt as a no-op so callers can still wire the action.
  }

  @override
  Future<void> reorderProjects(List<String> newOrderIds) async {
    // Single-project mode: one tab has no order.
  }

  @override
  Future<void> clearRecentProject(String projectId) async {
    // Single-project mode: recent list is always empty.
  }

  @override
  Future<void> shutdownAll() async {
    _workspace = ProjectWorkspace.empty();
    _bus.add(_workspace);
  }

  @override
  Stream<ProjectWorkspace> watch() => _bus.stream(_workspace);

  static String _basename(String path) {
    final unixIdx = path.lastIndexOf('/');
    final winIdx = path.lastIndexOf(r'\');
    final idx = unixIdx > winIdx ? unixIdx : winIdx;
    return idx < 0 ? path : path.substring(idx + 1);
  }
}

/// Tiny replay-on-subscribe broadcast helper. New subscribers get
/// the current value before subsequent events flow.
class _Bus<T> {
  final List<StreamController<T>> _subs = <StreamController<T>>[];

  void add(T value) {
    for (final s in _subs) {
      if (!s.isClosed) s.add(value);
    }
  }

  Stream<T> stream(T initial) {
    late StreamController<T> controller;
    controller = StreamController<T>(
      onCancel: () {
        _subs.remove(controller);
      },
    );
    _subs.add(controller);
    scheduleMicrotask(() {
      if (!controller.isClosed) controller.add(initial);
    });
    return controller.stream;
  }
}
