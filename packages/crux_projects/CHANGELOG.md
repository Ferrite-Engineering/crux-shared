# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## 0.3.0

- **Removed** `JsonFileProjectRegistry` and the `crux_projects_io.dart` entry
  point that carried it. The persistent multi-project registry — pins,
  close-all-but-pinned, recents that survive a restart — is the paid
  capability the Pro overlays sell, not a seam over it, so it fails the
  placement test in `docs/adr/0002-pro-only-consumers-of-shared-packages.md`
  and now lives with the Pro overlays' private shared code.
  `docs/adr/0005-pro-implementations-leave-crux-shared.md` records the
  decision. This is the one removal the deprecation policy allows in a single
  step: it had no open-core consumer, and every consumer it did have moves in
  the same change.
- What stays is the whole open contract: `ProjectDescriptor`,
  `ProjectWorkspace`, `ProjectRegistry`, `NoopProjectRegistry`, the Riverpod
  seam and `perProjectScope`. Nothing a product's open core imports changed.
- The package no longer depends on `crux_io`; the registry was its only user.
- `test/web_safety_test.dart` now holds **every** `lib/*.dart` entry point to
  the no-`dart:io` rule rather than one named barrel, so a new entry point
  cannot reintroduce the web breakage the split was made to fix.

## 0.2.0

- `JsonFileProjectRegistry` persistence failure is no longer silent:
  `lastSaveError` / `acknowledgeSaveError` surface a failed write (read-only
  directory, full disk) that previously left every action looking successful
  while the whole workspace was gone on next launch.
- Restore failure is no longer silent: `lastRestoreError` /
  `restoreQuarantinePath` / `acknowledgeRestoreError` report an unreadable
  `workspace.json`, and the corrupt bytes are quarantined to
  `workspace.json.corrupt-<timestamp>` so the next save cannot overwrite them.
  This covers both a decode error and the unsupported-version /
  non-object-root case that `ProjectWorkspace.fromJson` returns `null` for.
- `restore()` is genuinely idempotent: `_loaded` flips only once the read has
  completed, so two concurrent restores share one hydration instead of one
  returning an empty workspace mid-flight.
- Subscriber lifecycle: `dispose()` closes every outstanding `watch()`
  subscription, `_publish` skips paused subscribers (a paused listener no
  longer buffers an unbounded backlog of full snapshots), and publishing
  after dispose is a no-op rather than a `StateError`.
- Writes go through `crux_io`'s single atomic-write helper (scratch + fsync +
  rename), and saves are serialized so interleaved mutations cannot truncate
  or double the JSON document.

## 0.1.0

- Initial release. The multi-project workspace layer for products that let a
  user keep several projects open in browser-style tabs.
- `ProjectDescriptor` — immutable, comparable, JSON-serializable per-project
  metadata. `id` is a deterministic hash of the canonical path
  (`ProjectDescriptor.idForPath`), so a project re-opens with the same id
  across restarts and per-project Riverpod scopes can key off it directly.
- `ProjectWorkspace` — snapshot of open projects, the active project, and a
  capped MRU list of recents, with a versioned, forward-tolerant JSON schema.
  An unreadable or future-versioned document returns `null` so the host can
  substitute a fresh workspace, rather than throwing and bricking launch.
- `ProjectRegistry` extension point with `NoopProjectRegistry` as the
  open-core default (single-project: opening replaces the previous project,
  recents are never retained), surfaced through `projectRegistryProvider`.
- `perProjectScope` / `perProjectScopeWithFamily` / `PerProjectScope` — the
  scoping helper that gives each project its own provider state keyed by
  descriptor id, so state cannot bleed across the project switcher.
  `emptyWorkspaceProjectId` covers the no-project-open case.
- `JsonFileProjectRegistry` — the persistent multi-project registry the
  Pro overlays install: atomic-write persistence via `crux_io`, MRU
  recents, pinned projects, and graceful degradation when a restored project
  path no longer exists.
- Exported from a **separate** `package:crux_projects/crux_projects_io.dart`
  entry point, because it imports `dart:io` and the main barrel is kept
  web-safe for hosts with a `web/` target.
