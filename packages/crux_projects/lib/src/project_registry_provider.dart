// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/src/project_descriptor.dart';
import 'package:crux_projects/src/project_registry.dart';
import 'package:crux_projects/src/project_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Extension-point seam for the active [ProjectRegistry].
///
/// **Open-core default.** Returns [NoopProjectRegistry] — a single-project
/// surface (opening a project replaces the previous one, recent projects
/// empty, pin / reorder no-ops). The dashboard, project tab strip, and
/// command-palette actions all consume the same provider in single-project
/// and multi-project modes; only the active registry changes.
///
/// **Pro override.** The Pro overlay registers a persistent multi-project
/// registry that writes the workspace to `<appSupportDir>/<product>/workspace.json`
/// through `crux_io`'s atomic write, retains up to
/// [ProjectWorkspace.recentProjectsCap] recent projects, and survives app
/// restarts. It implements [ProjectRegistry] and nothing more; the seam is
/// this provider.
final Provider<ProjectRegistry> projectRegistryProvider =
    Provider<ProjectRegistry>(
      (_) => NoopProjectRegistry(),
    );

/// Live workspace snapshot. Re-emits on every registry mutation.
final StreamProvider<ProjectWorkspace> projectWorkspaceProvider =
    StreamProvider<ProjectWorkspace>((ref) {
      final registry = ref.watch(projectRegistryProvider);
      return registry.watch();
    });

/// Currently-active [ProjectDescriptor], or null when the workspace
/// is empty (or hydration is still pending). Convenience derived
/// view of [projectWorkspaceProvider] so widgets that only care about
/// "which project am I rendering" don't have to re-derive it.
final Provider<ProjectDescriptor?> activeProjectProvider =
    Provider<ProjectDescriptor?>((ref) {
      final async = ref.watch(projectWorkspaceProvider);
      return async.maybeWhen(
        data: (ws) => ws.activeProject,
        orElse: () => null,
      );
    });

/// The active project's id, or null when the workspace is empty.
/// This is the key per-project Riverpod scopes derive from — see
/// `perProjectScope`.
final Provider<String?> activeProjectIdProvider = Provider<String?>((ref) {
  return ref.watch(activeProjectProvider)?.id;
});
