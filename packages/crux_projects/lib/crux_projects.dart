// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite multi-project workspace layer for the EDACrux suite.
///
/// One package, up to four consumers (WaveCrux, NetCrux, LintCrux,
/// SimCrux). Every product that supports keeping several projects open in
/// browser-style tabs wires the same primitives into its open-core and
/// Pro overlay: a stable `ProjectDescriptor` identity, a
/// `ProjectWorkspace` snapshot of what's open, the `ProjectRegistry`
/// extension point, and the `perProjectScope` Riverpod helper that keeps each
/// project's state from bleeding across the project switcher.
///
/// What is deliberately **not** here is the persistent multi-project
/// registry itself. It is the paid capability — pins, close-all-but-pinned,
/// recents that survive a restart — so it lives with the Pro overlays'
/// private shared code rather than in the open half, and installs itself by
/// overriding `projectRegistryProvider` exactly as this barrel's docs
/// describe. See `docs/adr/0005-pro-implementations-leave-crux-shared.md`.
///
/// Surface:
///
/// - `ProjectDescriptor` — stable, comparable, JSON-serializable metadata
///   for one open project (identity, config path, open/access timestamps,
///   pin flag). The `id` is a deterministic hash of the canonical path, so
///   a project re-opens with the same id across restarts and per-project
///   Riverpod scopes key off it.
/// - `ProjectWorkspace` — snapshot of which projects are open, which is
///   active, and which are remembered for one-click reopen (capped MRU
///   list). JSON-serializable with a versioned, forward-tolerant schema.
/// - `ProjectRegistry` — the extension-point interface. Open-core ships
///   `NoopProjectRegistry` (single-project: opening replaces the previous
///   project); the Pro overlay overrides `projectRegistryProvider` with a
///   persistent multi-project implementation.
/// - `projectRegistryProvider` / `projectWorkspaceProvider` /
///   `activeProjectProvider` / `activeProjectIdProvider` — the Riverpod
///   seam every project-aware surface consumes.
/// - `perProjectScope` / `perProjectScopeWithFamily` / `PerProjectScope` /
///   `emptyWorkspaceProjectId` — construct a widget-facing `Provider<T>`
///   whose state is scoped to the active project without leaking the
///   multi-project surface into call sites. Use the `WithFamily` variant when
///   you also need to address a specific project's slot directly (seeding,
///   tests); it is the only way to obtain the family the provider actually
///   reads.
/// - `ProjectLoadException` — thrown by `ProjectRegistry.openProject` when a
///   path cannot be loaded.
///
/// The barrel is **web-safe**: nothing reachable from it imports `dart:io`,
/// so a host with a `web/` target consumes the models and the Riverpod seam
/// without breaking its web build. `test/web_safety_test.dart` holds it to
/// that. A registry that needs the filesystem is the host's to supply.
library;

export 'src/per_project_scope.dart';
export 'src/project_descriptor.dart';
export 'src/project_registry.dart';
export 'src/project_registry_provider.dart';
export 'src/project_workspace.dart';
