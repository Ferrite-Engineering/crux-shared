# Changelog

## Unreleased

- **Added spawn resolution: `resolveSpawnExecutable`,
  `resolveSpawnExecutableForHost`, `isAbsoluteSpawnPath` and
  `kDefaultWindowsPathExt`.** On Windows, `CreateProcess` searches the
  launching process's current directory before the system directories and
  `PATH`, so a product launched from a terminal inside a repository would run
  an engine or editor binary committed to that repository in place of the
  installed one. Resolving a bare name to an absolute path first closes that.
  Three products carried byte-identical copies of the resolver; this is the
  one implementation they move to. It is `PATHEXT`-aware, and takes every host
  fact — `PATH`, `PATHEXT`, whether the host is Windows, the on-disk probe — as
  a parameter, so the Windows branch is tested on every host.
  `resolveSpawnExecutableForHost` reads them from the live process, or from the
  environment the child will be spawned with when one is passed.
  `isAbsoluteSpawnPath` is the check that a path handed to an editor argv is
  absolute, so an editor cannot read it as an option; it was carried under two
  names, and this is the one it keeps.
- **Added the strict form for spawn sites: `requireSpawnExecutable`,
  `requireSpawnExecutableForHost` and `SpawnHost`.** The resolver hands back a
  bare name when nothing on `PATH` matches, and on Windows `CreateProcess` then
  searches the launching directory for it — so a planted binary would run for
  exactly the users who do not have the tool installed. The `require` forms
  throw instead: a `ProcessException` naming the executable, message
  `not found on PATH`, error code 2, the same type `Process.start` raises for a
  missing binary, so a spawn site's existing "not installed" handling applies
  unchanged and nothing is started. Off Windows, and for a name that already
  carries a path, they answer what the `resolve` forms do. `SpawnHost` bundles
  the host facts (whether it is Windows, the process environment, the on-disk
  probe) into one injectable value for a spawn layer, with `resolveExecutable`
  and `requireExecutable` methods that also search the child's environment
  first; `SpawnHost.current()` is the live process.
- **`revealInFileManager` resolves every command before spawning it.** It ran
  `open`, `explorer`, `dbus-send` and `xdg-open` by bare name. On Windows it
  now spawns Explorer by absolute path, and spawns nothing when no `PATH`
  directory holds it. Its host is injectable through new optional named
  parameters (`operatingSystem`, `environment`, `exists`, `runCommand`, with
  the `RevealCommandRunner` typedef), so each platform's branch is tested on
  any machine. Existing calls are unchanged.
- **On Linux, `revealInFileManager` passes the file to D-Bus as a
  percent-encoded `file:` URI.** It pasted the path in raw, so a name holding
  a `#` (read as a fragment), a `%` (read as an escape) or a space did not
  name the file, and the reveal fell back to opening the folder or selected
  nothing.
- **The Windows registry read behind `engineSearchDirs` runs `reg` by absolute
  path**, and reads nothing when no `PATH` directory holds it.

## 0.3.0

- Added engine `PATH` augmentation: `engineSearchDirs` and
  `appendMissingPathDirs`, plus the `resetEngineSearchDirsCacheForTesting`
  seam. Every product that spawns an EDA engine carried this as a
  byte-identical file whose own header asked to be moved here; the three
  copies are retired in favour of this one.
- The Windows registry parse is a pure function, `parseWindowsPersistentPath`,
  so the `REG_SZ` / `REG_EXPAND_SZ` handling and `%VAR%` expansion are tested
  on every host rather than only on a Windows runner. The `reg query` spawn
  around it is unchanged.

## 0.2.1

- Path identity is web-safe. In a browser `filesystemIsCaseInsensitive`,
  `canonicalPathKey` and `isSamePath` threw `UnsupportedError` from
  `Platform.isMacOS`, and `canonicalizePath` did not throw but was wrong:
  `package:path` resolved a bare name against the page URL
  (`design.vcd` → `http://host/…/design.vcd`) and normalised URLs, collapsing a
  `..` inside a query string. A product keying tabs by location on the web had
  to special-case the browser to avoid all three.
- The platform half now sits behind a conditional export. In a browser a
  location — an uploaded file's name, a URL, a `blob:` id — is treated as
  already canonical: `canonicalizePath` returns it trimmed and otherwise
  unchanged, `filesystemIsCaseInsensitive` is `false`, and keys preserve case
  unless the caller passes `caseInsensitive: true`. On the VM nothing changes.
- The library doc no longer says the package is `dart:io`-only; only the atomic
  writes, which take a `File`, are off limits to a web build.

## 0.2.0

- Added path identity: `canonicalizePath`, `canonicalPathKey`, `isSamePath`
  and `filesystemIsCaseInsensitive`. Deciding whether two strings name the
  same file had been open-coded three ways across the suite — as
  `p.normalize(p.absolute(path))` in the project registry, as a raw
  `Map<String, TabId>` keyed on the unprocessed string in the workspace sync,
  and not at all on the three products' command-line open paths. None of them
  survived a symlink or a case-insensitive volume, which is how a single
  project came to occupy seven tabs, one per relaunch.
- `canonicalizePath` returns a real path (case preserved, symlinks resolved,
  absolute, normalized); `canonicalPathKey` returns a *comparison key* that is
  additionally case-folded on macOS and Windows and must never be stored,
  displayed or opened.
- New dependency: `package:path`.

## 0.1.0

- Initial release. `writeStringAtomic` / `writeJsonAtomic` + `WriteDurability`, unifying
  the five divergent atomic-write implementations that previously lived in
  `crux_projects`, `crux_workspace`, `crux_cxp` and `crux_theme`.
