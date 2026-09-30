# crux_projects

The multi-project workspace layer for the EDACrux suite — stable project
identity, the "which projects are open" snapshot, the registry extension
point, and the Riverpod scoping helper that stops one project's state from
bleeding into another.

Any product that lets a user keep several projects open in browser-style tabs
wires these same primitives into its open-core build and its Pro overlay.

## Surface

| Symbol | Purpose |
|---|---|
| `ProjectDescriptor` | Immutable, comparable, JSON-serializable metadata for one open project: identity, config path, opened/accessed timestamps, pin flag. |
| `ProjectWorkspace` | Snapshot of which projects are open, which one is active, and which are remembered for one-click reopen (a capped MRU list). Versioned, forward-tolerant JSON schema. |
| `ProjectRegistry` | The extension-point interface: open / close / pin / activate / restore. |
| `NoopProjectRegistry` | Open-core default. Single-project behaviour — opening a project replaces the previous one and recents are never retained. |
| `projectRegistryProvider` | The Riverpod seam every project-aware surface reads. The Pro overlays override it. |
| `perProjectScope` / `perProjectScopeWithFamily` / `PerProjectScope` | Build a widget-facing `Provider<T>` whose state is scoped to the active project. |
| `ProjectLoadException` | Thrown by `openProject` when a path cannot be loaded; callers surface it as a snackbar or dialog. |

## Project identity

`ProjectDescriptor.id` is a deterministic hash of the canonical project path,
not a random UUID. Two consequences that the rest of the package leans on:

- A project re-opens with the **same id across app restarts**, so persisted
  per-project state finds its way back to the right project.
- Per-project Riverpod scopes can key off the id without a lookup table.

If you are tempted to make the id random, note that both properties disappear.

## Per-project scoping

The failure mode this package exists to prevent is state bleed: the user
switches projects, and a notifier created for project A is still serving
project B. It has recurred often enough across the suite to be a named class
of bug.

`perProjectScope` gives each project its own instance of a provider's state,
keyed by descriptor id, and disposes it when the project closes:

```dart
final analysisProvider = perProjectScope<AnalysisState>(
  'analysisProvider',
  (ref, projectId) => AnalysisState.forProject(projectId),
);
```

The name is used for Riverpod debug labels, so make it match the variable.

Call sites read `analysisProvider` and never see the multi-project surface at
all. Use `perProjectScopeWithFamily` when you additionally need to address a
specific project's slot directly — seeding it in a test, or writing to a
project that is not the active one. It is the only way to obtain the family
the provider actually reads; reconstructing an equivalent family by hand
produces a *different* provider and silently defeats the scoping.

When `ProjectWorkspace` has no active project, scoping keys off
`emptyWorkspaceProjectId` so the provider still resolves rather than throwing
during an empty-state render.

## Web safety

The barrel is deliberately **web-safe**: nothing reachable from it imports
`dart:io`, so a host with a `web/` target can consume the models and the
Riverpod seam without breaking its web build. `test/web_safety_test.dart`
holds every `lib/*.dart` entry point to that, transitively.

Adding a `dart:io` import anywhere under `lib/` breaks every web consumer at
once and is the thing to watch for in review. A registry that needs the
filesystem is the host's to supply — see below.

## Where the persistent registry is, and why it is not here

The multi-project registry the Pro overlays sell — pins, close-all-but-pinned,
recents that survive a restart — is **not in this package**. It used to be,
behind a `crux_projects_io.dart` entry point, and it was moved out because it
fails the placement test this repository applies to every shared package: it
is the paid capability itself, not a mechanism whose paid inputs stay with the
overlays. The decision is recorded in
`docs/adr/0005-pro-implementations-leave-crux-shared.md`.

It lives with the Pro overlays' private shared code, implements
`ProjectRegistry` and nothing more, writes `<appSupportDir>/<product>/workspace.json`
through `crux_io`'s atomic write, and installs itself by overriding
`projectRegistryProvider`. Nothing in this package knows it exists, which is
the point: the seam here is complete on its own.

## Wiring it in

```dart
// Open-core: nothing to do. NoopProjectRegistry is the default.

// A host with its own registry — a web build over local storage, a test
// double, or the Pro overlays' persistent implementation — installs it by
// overriding the one provider every project-aware surface reads.
ProviderScope(
  overrides: [
    projectRegistryProvider.overrideWithValue(myRegistry),
  ],
  child: const MyApp(),
);
```

## Visibility & license

Private during the public beta; Apache 2.0 at the post-beta open-core flip,
alongside the rest of the suite.
