// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The two checks that stand between a string and a subprocess: which binary
/// a spawn runs, and whether a path is safe to hand to one as an argument.
///
/// ## Spawn order — [resolveSpawnExecutable]
///
/// On Windows, `CreateProcess` resolves a **bare** executable name in this
/// order:
///
/// 1. the directory the calling application loaded from,
/// 2. **the current directory of the calling process**,
/// 3. the system directories,
/// 4. `PATH`.
///
/// Step 2 is the hole. No product in the suite moves its own current
/// directory, so it is whatever the launching shell had — and the way a
/// hardware engineer launches a tool is to `cd` into the repository and run
/// it from there. A `verilator.exe`, `code.exe` or `explorer.exe` committed
/// to that repository then beats every copy on `PATH` and in the system
/// directories, and runs the moment the product spawns that name. Passing
/// `workingDirectory` does not move the search: it uses the *parent's*
/// current directory, not the child's.
///
/// The fix is to resolve a bare name to an absolute path against `PATH`
/// *before* handing it to `Process.start` or `Process.run`, so
/// `CreateProcess` is given a path and never searches. POSIX has no
/// equivalent — `execvp` searches `PATH` only — so the resolution is a no-op
/// off Windows.
///
/// Resolution alone leaves one case open: a name that nothing on `PATH`
/// answers to. Handed on bare, it is still searched for in the launching
/// directory, so a planted binary runs for exactly the users who do not have
/// the tool installed. [requireSpawnExecutable] closes that by throwing the
/// same [ProcessException] a missing binary produces, before anything is
/// spawned. **A spawn site uses the `require` form**; the `resolve` form is
/// for a caller that needs the name back to decide for itself.
///
/// Each form takes every host fact as a parameter, including the on-disk
/// probe, so the Windows branch is exercised on the macOS and Linux machines
/// CI runs on rather than only on a Windows runner. [SpawnHost] bundles those
/// facts for a spawn layer that wants one injectable value, and
/// [requireSpawnExecutableForHost] / [resolveSpawnExecutableForHost] are the
/// forms against the live process.
///
/// ## Argument shape — [isAbsoluteSpawnPath]
///
/// A path that reaches an editor's argv from outside the product (a
/// cross-probe request from a socket, a location an engine printed) is
/// dangerous in one specific way even with no shell involved: the editor's
/// own option parser. The common editor command shapes carry a line number
/// as an argument beginning with `+`, and to `vim` and `emacs` an argument
/// beginning with `+` is an ex command rather than a filename. Quoting cannot
/// help, because there is no shell to quote for. An absolute path is the one
/// shape no editor's option parser reads as a flag, so a path that is not
/// absolute is refused before the spawn.
///
/// The near-miss worth naming: `file.length >= 2 && file[1] == ':'` is not an
/// absoluteness test. It is a drive-letter guess, and it admits any string
/// whose second character is a colon — which is exactly what an ex command
/// can be made to look like.
library;

import 'dart:io';

import 'package:crux_io/src/spawn_environment.dart';

/// Default `PATHEXT` when the environment does not supply one — the list
/// Windows itself falls back to.
const String kDefaultWindowsPathExt = '.COM;.EXE;.BAT;.CMD';

/// Matches a Windows-absolute path (`C:\…`, `C:/…`, or a `\\server\share`
/// UNC prefix) in *any* host context.
///
/// Deliberately not `p.isAbsolute`, which follows the host platform: a peer
/// running on Windows sends `C:\rtl\cpu.v` to a product running on macOS
/// during mixed-platform cross-probing, and that path is legitimate there.
final RegExp _windowsAbsolute = RegExp(r'^(?:[A-Za-z]:[\\/]|[\\/][\\/])');

/// Whether [path] is an absolute path in either the POSIX or the Windows
/// sense — the precondition for handing a path to a subprocess argv.
///
/// Note what this is *not*: a check that the file exists, or that it is
/// inside any particular tree. An out-of-tree absolute path is ordinary (a
/// peer cross-probing into a vendored library, a violation reported in a
/// system header), and an absolute path cannot be mistaken for an editor
/// option, which is the property that matters here.
///
/// An empty path, and a path carrying a NUL, answer `false`: neither is a
/// file, and `Process.run` would truncate the argv element at the NUL.
bool isAbsoluteSpawnPath(String path) {
  if (path.isEmpty) return false;
  if (path.contains('\u0000')) return false;
  return path.startsWith('/') || _windowsAbsolute.hasMatch(path);
}

/// Resolves [executable] to an absolute path when it is a bare name, and
/// otherwise returns it unchanged.
///
/// Returns [executable] unchanged when:
///
/// * the host is not Windows ([windows] is false) — `execvp` never consults
///   the current directory, so there is nothing to close;
/// * the name already carries a path separator or a drive letter, which
///   means the caller named a concrete file and `CreateProcess` will not
///   search at all;
/// * nothing on [pathEnvironment] matches. **A bare name handed on from here
///   is still searched for in the launching directory**, so a spawn site
///   should call [requireSpawnExecutable] instead, which throws in this case
///   rather than returning the name.
///
/// [pathExt] defaults to [kDefaultWindowsPathExt]; a name that already ends
/// in one of its extensions is looked up as-is first.
///
/// [exists] is the on-disk probe, injectable so a test can lay out a
/// synthetic `PATH` without touching the filesystem — which is what makes
/// the Windows branch provable on a macOS or Linux run.
String resolveSpawnExecutable(
  String executable, {
  required String? pathEnvironment,
  required bool windows,
  String? pathExt,
  bool Function(String path)? exists,
}) {
  if (!windows) return executable;
  if (executable.isEmpty) return executable;
  if (_namesAFile(executable)) return executable;
  final probe = exists ?? _defaultExists;
  final dirs = (pathEnvironment ?? '')
      .split(';')
      .where((d) => d.trim().isNotEmpty);
  final extensions = _candidateExtensions(executable, pathExt);
  for (final dir in dirs) {
    final base = dir.endsWith(r'\') || dir.endsWith('/')
        ? dir.substring(0, dir.length - 1)
        : dir;
    for (final ext in extensions) {
      final candidate = '$base\\$executable$ext';
      if (probe(candidate)) return candidate;
    }
  }
  return executable;
}

/// [resolveSpawnExecutable] for a spawn site: on Windows, a name that nothing
/// on [pathEnvironment] answers to throws instead of coming back bare.
///
/// The throw is a [ProcessException] naming [executable], with the message
/// `not found on PATH` and error code 2 (`ERROR_FILE_NOT_FOUND`, and `ENOENT`
/// on POSIX) — the same exception type `Process.start` raises for a missing
/// binary. A spawn site that already reports a missing tool as "not
/// installed" therefore needs no new branch: it calls this in place of
/// `resolveSpawnExecutable`, and an uninstalled tool reaches the same
/// handler with nothing spawned. Returning the bare name instead would let
/// `CreateProcess` search the launching directory, where a planted binary
/// runs for exactly the users who do not have the real one.
///
/// Off Windows, and for a name that already carries a separator or drive
/// letter, this answers exactly what [resolveSpawnExecutable] does.
String requireSpawnExecutable(
  String executable, {
  required String? pathEnvironment,
  required bool windows,
  String? pathExt,
  bool Function(String path)? exists,
}) {
  final resolved = resolveSpawnExecutable(
    executable,
    pathEnvironment: pathEnvironment,
    windows: windows,
    pathExt: pathExt,
    exists: exists,
  );
  if (windows && !_namesAFile(resolved)) {
    throw ProcessException(
      executable,
      const <String>[],
      'not found on PATH',
      _fileNotFound,
    );
  }
  return resolved;
}

/// The host facts a spawn resolution depends on, as one injectable value.
///
/// A spawn layer takes a `SpawnHost` (defaulting to [SpawnHost.current]) so
/// its tests can hand it a Windows host with a synthetic `PATH` and probe on
/// any machine, and prove which binary it would start — or that it starts
/// none — without a Windows runner.
class SpawnHost {
  /// A host with the given facts. [environment] is the process environment
  /// the child inherits; [exists] is the on-disk probe, defaulting to a real
  /// file check.
  const SpawnHost({
    required this.windows,
    this.environment = const <String, String>{},
    this.exists,
  });

  /// The live process: `Platform.isWindows` and `Platform.environment`.
  ///
  /// Desktop only: it reads `Platform`, which a web build cannot.
  factory SpawnHost.current() => SpawnHost(
    windows: Platform.isWindows,
    environment: Platform.environment,
  );

  /// Whether `CreateProcess` rules apply — the only case where resolution
  /// does anything.
  final bool windows;

  /// The process environment, where `PATH` and `PATHEXT` are read from when
  /// the child's own environment does not set them.
  final Map<String, String> environment;

  /// The on-disk probe; `null` means a real file check.
  final bool Function(String path)? exists;

  /// [resolveSpawnExecutable] against this host.
  ///
  /// [childEnvironment] is the environment the child will be spawned with,
  /// when the caller builds one: an engine spawn that appends
  /// `engineSearchDirs` to `PATH`, say. Its `PATH` and `PATHEXT` are searched
  /// in place of the host's, so a binary found only through the augmentation
  /// still resolves. A variable it does not set falls back to [environment],
  /// as it does for the child under `Process.start`'s default
  /// `includeParentEnvironment`. Names match case-insensitively on Windows,
  /// which spells the variable `Path`.
  String resolveExecutable(
    String executable, {
    Map<String, String>? childEnvironment,
  }) => resolveSpawnExecutable(
    executable,
    pathEnvironment: _variable('PATH', childEnvironment),
    windows: windows,
    pathExt: _variable('PATHEXT', childEnvironment),
    exists: exists,
  );

  /// [requireSpawnExecutable] against this host: throws the `not found on
  /// PATH` [ProcessException] on Windows rather than returning a bare name.
  /// See [resolveExecutable] for [childEnvironment].
  String requireExecutable(
    String executable, {
    Map<String, String>? childEnvironment,
  }) => requireSpawnExecutable(
    executable,
    pathEnvironment: _variable('PATH', childEnvironment),
    windows: windows,
    pathExt: _variable('PATHEXT', childEnvironment),
    exists: exists,
  );

  String? _variable(String name, Map<String, String>? childEnvironment) =>
      (childEnvironment == null
          ? null
          : spawnEnvironmentValue(childEnvironment, name, windows: windows)) ??
      spawnEnvironmentValue(environment, name, windows: windows);
}

/// [resolveSpawnExecutable] against the live process. The identity off
/// Windows.
///
/// [environment] is the environment the child will be spawned with, when the
/// caller builds one; see [SpawnHost.resolveExecutable].
///
/// A spawn site should prefer [requireSpawnExecutableForHost], which never
/// hands a bare name to `CreateProcess`.
///
/// Desktop only: it reads `Platform`, which a web build cannot.
String resolveSpawnExecutableForHost(
  String executable, {
  Map<String, String>? environment,
}) => SpawnHost.current().resolveExecutable(
  executable,
  childEnvironment: environment,
);

/// [requireSpawnExecutable] against the live process — the form a real spawn
/// site uses. The identity off Windows; on Windows it returns an absolute
/// path or throws the `not found on PATH` [ProcessException].
///
/// [environment] is the environment the child will be spawned with, when the
/// caller builds one; see [SpawnHost.resolveExecutable].
///
/// Desktop only: it reads `Platform`, which a web build cannot.
String requireSpawnExecutableForHost(
  String executable, {
  Map<String, String>? environment,
}) => SpawnHost.current().requireExecutable(
  executable,
  childEnvironment: environment,
);

/// `ERROR_FILE_NOT_FOUND` on Windows, and `ENOENT` on POSIX: what the OS
/// reports for a binary that is not there.
const int _fileNotFound = 2;

/// Whether [executable] names a file rather than a command: it carries a
/// path separator or a drive letter, so `CreateProcess` will not search for
/// it. Absolute, relative-with-separator and drive-relative (`C:tool`) all
/// count.
bool _namesAFile(String executable) =>
    executable.contains(r'\') ||
    executable.contains('/') ||
    (executable.length >= 2 && executable[1] == ':');

/// The suffixes to try for [executable], in order: the empty suffix first
/// when the name already carries a known executable extension, otherwise
/// every `PATHEXT` entry.
List<String> _candidateExtensions(String executable, String? pathExt) {
  final exts = (pathExt == null || pathExt.trim().isEmpty)
      ? kDefaultWindowsPathExt
      : pathExt;
  final parsed = exts
      .split(';')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  final lower = executable.toLowerCase();
  if (parsed.any((e) => lower.endsWith(e.toLowerCase()))) {
    // Already carries an extension (`code.exe`): try it verbatim before
    // appending a second one.
    return <String>['', ...parsed];
  }
  return parsed;
}

bool _defaultExists(String path) =>
    FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
