// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Filesystem primitives shared by every Crux persistence layer.
///
/// Every primitive here earned its place the same way: it had been written
/// several times across the suite and the copies had silently diverged.
///
/// * **Crash-safe file replacement** was implemented five separate times
///   across `crux_projects`, `crux_workspace` (twice), `crux_cxp` and
///   `crux_theme`, diverging on durability, on scratch-file naming, and on
///   cleanup after a failed write. Three of the five would lose data on a
///   crash in ways the other two would not — not by decision, but because
///   nobody had put them side by side.
/// * **Path identity** — deciding whether two strings name the same file —
///   existed as `p.normalize(p.absolute(path))` in the project registry, as a
///   raw `Map<String, TabId>` keyed on the unprocessed string in the
///   workspace/registry sync, and not at all on the three CLI open paths.
///   None of them handled symlinks or a case-insensitive volume, which is how
///   one project came to occupy seven tabs.
/// * **Engine `PATH` augmentation** — the directories a GUI launch loses and
///   an engine spawn needs back — was three byte-identical files, one in each
///   product that spawns an engine, every header of which asked to be moved
///   here. Identical today; the next Windows registry fix would have been
///   applied three times by hand or, more likely, twice.
/// * **Spawn resolution** — turning a bare executable name into an absolute
///   path before a spawn, so Windows cannot run a same-named binary from the
///   directory the product was launched in — was three byte-identical copies
///   in three products, with a fourth product and this package's own file
///   manager reveal still spawning bare names. The absolute-path check that
///   guards an editor argv had two names for one function.
///
/// `crux_io` is a **pure-Dart leaf**: it depends on no other Crux package, so
/// every persistence layer in the suite can depend on it without creating a
/// sibling edge between packages that should not know about each other. It is
/// deliberately tiny. Resist the urge to grow it into a general "utils"
/// package — the next thing that lands here should be another primitive with
/// the same "implemented N times, diverged N ways" story behind it.
///
/// **Importable from a web build, and the path functions work there.** Path
/// identity reaches the platform through a conditional export, so in a
/// browser `canonicalizePath`, `canonicalPathKey` and `isSamePath` treat a
/// location — an uploaded file's name or a URL — as already canonical, and
/// `filesystemIsCaseInsensitive` is false. `revealInFileManager` returns
/// false. `resolveSpawnExecutable`, `requireSpawnExecutable` and
/// `isAbsoluteSpawnPath` are pure and answer the same anywhere. The atomic
/// writes, `engineSearchDirs`, `SpawnHost.current` and the two `…ForHost`
/// resolvers are the exceptions: the writes take a `dart:io` `File`, and a
/// browser has no filesystem for one to name and spawns nothing, so a web
/// build must not call them.
library;

export 'src/atomic_write.dart';
export 'src/engine_path_augmentation.dart';
export 'src/path_identity.dart';
export 'src/reveal_in_file_manager.dart';
export 'src/spawn_guards.dart';
