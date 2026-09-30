# crux_io

Filesystem and process primitives shared by every Crux persistence layer and spawn
site. Pure Dart, `dart:io`, depends on no other Crux package.

Four primitives, each of which had been written several times across the suite before
it was written once here: **crash-safe atomic file replacement**, **path identity**,
**engine `PATH` augmentation**, and **spawn resolution**.

```dart
import 'package:crux_io/crux_io.dart';

await writeJsonAtomic(File(path), document);                       // durable (default)
await writeJsonAtomic(File(path), doc,
    durability: WriteDurability.ephemeral);                        // opt out, deliberately
```

## Why the package exists

Atomic write had been implemented five times across `crux_projects`, `crux_workspace`
(twice), `crux_cxp` and `crux_theme`. The copies had diverged on three axes — whether
they `fsync`ed before the rename, whether the scratch filename was unique per write, and
whether a failed write cleaned up after itself — and the divergence was accidental, not
designed. Three of the five would lose data on a crash in ways the other two would not.

## The durability decision

`write` + `rename` is only *nominally* atomic without an `fsync`: the filesystem may order
the rename ahead of the data blocks, so a crash between them can leave the destination
name pointing at a truncated file — and the previous good document is already gone.

`WriteDurability.durable` is therefore the default, and everything a user cannot trivially
reconstruct takes it. `WriteDurability.ephemeral` exists for state a running process
republishes on a bounded timer; the CXP peer manifest (rewritten every 30-second
heartbeat) is the only caller that qualifies. See the `WriteDurability` doc comment for
the full argument and the bar a new `ephemeral` call site has to clear.

## Engine `PATH` augmentation

A GUI-launched product does not inherit the `PATH` an interactive shell would resolve an
engine from: a macOS Finder or Dock launch gets `launchd`'s truncated `$PATH`, which
omits the Homebrew and MacPorts prefixes, and a Windows app launched from a stale shell
or an installer's "launch now" carries an older process `PATH` that omits toolchains the
user has since added. `yosys` then fails "not found" while sitting right there.

```dart
final dirs = engineSearchDirs();                       // platform-appropriate; const [] on Linux
final path = appendMissingPathDirs(
  Platform.environment['PATH'] ?? '',
  dirs,
  separator: Platform.isWindows ? ';' : ':',
  caseInsensitive: Platform.isWindows,
);                                                     // null when nothing needs adding
```

Every product that spawns an engine carried this as a byte-identical file whose header
asked to be moved here. `engineSearchDirs` is desktop-only, like the atomic writes: a
browser spawns no engines. The Windows half reads the persistent registry `PATH`
(Machine, then User) once per process through `reg query`; the parse of that output is a
pure function, `parseWindowsPersistentPath`, so it is tested on every host.

## Spawn resolution

On Windows, `CreateProcess` looks for a **bare** executable name in the launching
process's current directory before the system directories and `PATH`. No product moves
its own current directory, so a product launched from a terminal inside a repository
would run a `verilator.exe`, `code.exe` or `explorer.exe` committed to that repository in
place of the installed one. `workingDirectory` does not help: the search uses the
parent's current directory, not the child's.

Resolve the name to an absolute path first, so `CreateProcess` never searches — and
refuse to start anything when nothing on `PATH` answers to it, because a bare name would
still be searched for in the launching directory:

```dart
// Throws ProcessException('not found on PATH') on Windows when the tool is not
// installed; the handler that already reports "not installed" catches it.
final exe = requireSpawnExecutableForHost('verilator', environment: childEnv);
await Process.start(exe, args, workingDirectory: projectRoot, environment: childEnv);
```

- **A spawn site uses a `require` form.** `requireSpawnExecutableForHost` is the
  identity off Windows (`execvp` searches `PATH` only). On Windows it returns an absolute
  path found on the `PATH` and `PATHEXT` of `environment` when given — the child's,
  augmented or not — and the process's own otherwise, or throws a `ProcessException`
  (message `not found on PATH`, error code 2): the type `Process.start` throws for a
  missing binary, so no new branch is needed at the call site.
- `requireSpawnExecutable` is the same with every host fact a parameter, including the
  on-disk probe, so a test lays out a synthetic Windows `PATH` on any machine.
  `SpawnHost` bundles those facts into one value a spawn layer can take as a constructor
  argument (`SpawnHost.current()` by default); crux_yosys's `DefaultProcessRunner` does.
- The `resolve` forms (`resolveSpawnExecutable`, `resolveSpawnExecutableForHost`,
  `SpawnHost.resolveExecutable`) hand an unmatched name back unchanged, for a caller that
  wants to decide for itself. Handing that bare name to a spawn on Windows reopens the
  launch-directory search.
- A name with a separator or drive letter is returned unchanged by every form: the caller
  named a file, and `CreateProcess` will not search for it.
- `isAbsoluteSpawnPath` is the companion check for a path that reaches an editor's argv
  from outside the product. An absolute path is the one shape no editor's option parser
  reads as a flag; `vim +42 '+:!…'` shows what a relative one can become.

`revealInFileManager` resolves `open`, `explorer`, `dbus-send` and `xdg-open` this way,
and on Linux hands the file to D-Bus as a percent-encoded `file:` URI.
Its optional named parameters (`operatingSystem`, `environment`, `exists`,
`runCommand`) are the host, so each platform's branch is tested without spawning
anything; products pass none of them.

## Scope

Deliberately tiny. The next thing that lands here should have the same "implemented N
times, diverged N ways" story behind it — this is not a general-purpose utils package.

## On the web

Path identity is web-safe. It reaches the platform through a conditional export, so a
web build can key tabs and recent items with the same calls a desktop build uses. A
browser has no filesystem, no working directory and no symlinks, and a location there
is an uploaded file's name or a URL, which is already canonical:

- `canonicalizePath` returns the location trimmed and otherwise unchanged — not made
  absolute against the page URL, and not dot-normalised, which would rewrite a URL's
  query string.
- `filesystemIsCaseInsensitive` is `false`, so `canonicalPathKey` and `isSamePath`
  compare case-sensitively unless the caller passes `caseInsensitive: true`.
- `revealInFileManager` returns `false`.

The atomic writes are not web-safe and cannot be: they take a `dart:io` `File`, and a
browser has no filesystem for one to name. Libraries that write files and must also
compile for web keep that path behind a separate entry point or a host-supplied
implementation (see `crux_theme`'s `DirectoryThemePackStore`).
