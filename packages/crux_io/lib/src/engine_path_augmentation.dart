// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/src/spawn_guards.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Directories to append to a spawned engine's `PATH` so that a GUI-launched
/// product finds the EDA toolchains an interactive shell would resolve.
///
/// A desktop app does not always inherit the `PATH` from which an engine
/// resolves. A macOS Finder or Dock launch gets `launchd`'s truncated `$PATH`,
/// which omits the Homebrew and MacPorts prefixes; a Windows app launched from
/// a stale shell or an installer's "launch now" carries an older process
/// `PATH` that can omit engines the user has since added (oss-cad-suite, say).
/// Either way `yosys` or `verilator` fails "not found" even though it is
/// installed. Every product that spawns an engine appends these to the child's
/// `PATH` through [appendMissingPathDirs].
///
/// - **macOS**: the Homebrew and MacPorts bin directories,
///   `/opt/homebrew/bin` and `/usr/local/bin`, then the Nix profiles below.
/// - **Linux**: the Nix profiles: the user's `~/.nix-profile/bin`, then the
///   system default profile `/nix/var/nix/profiles/default/bin`. A desktop
///   session inherits the login `PATH`, but a Nix install adds its profiles
///   from a shell rc file that a desktop launcher does not read, and the
///   LibreLane toolchain is installed through Nix.
/// - **Windows**: the persistent (registry) `PATH` — Machine then User — that
///   a freshly-logged-in process inherits, including the `lib` DLL directory
///   Yosys and Verilator need. Appending it restores the post-reboot view
///   without an actual reboot.
///
/// Computed once and cached for the process lifetime on every platform, so a
/// spawn loop calling this per engine reads neither the registry nor `HOME`
/// more than once.
///
/// Desktop only: it reads `Platform`, which a web build cannot, and a browser
/// spawns no engines. Like the atomic writes, a web build must not call it.
///
/// This was carried as three byte-identical copies, one per product that
/// spawns an engine, each header asking to be moved here.
List<String> engineSearchDirs() {
  if (Platform.isWindows) return _windowsPersistentPathDirs();
  return _cachedPosixDirs ??= posixEngineSearchDirs(
    macOS: Platform.isMacOS,
    home: Platform.environment['HOME'],
  );
}

List<String>? _cachedPosixDirs;

/// The Nix system default profile's bin directory.
const String kNixDefaultProfileBin = '/nix/var/nix/profiles/default/bin';

/// The directories [engineSearchDirs] returns on macOS ([macOS] true) and
/// Linux, for the user whose home directory is [home].
///
/// The user's `~/.nix-profile/bin` is included only when [home] is an
/// absolute path that cannot split a `PATH`: one holding a `:` would add a
/// second, unintended entry, and a relative one would be searched from the
/// directory the product was launched in.
///
/// Pure, so both platforms' answers are testable on every host.
@visibleForTesting
List<String> posixEngineSearchDirs({required bool macOS, String? home}) {
  final userProfile = home == null || !_isUsableHome(home)
      ? null
      : p.posix.join(home, '.nix-profile', 'bin');
  return List<String>.unmodifiable(<String>[
    if (macOS) ...const <String>['/opt/homebrew/bin', '/usr/local/bin'],
    ?userProfile,
    kNixDefaultProfileBin,
  ]);
}

bool _isUsableHome(String home) =>
    home.startsWith('/') &&
    !home.contains(':') &&
    !home.contains('\x00') &&
    home.trim() == home &&
    home != '/';

List<String>? _cachedWindowsPathDirs;

List<String> _windowsPersistentPathDirs() =>
    _cachedWindowsPathDirs ??= _readWindowsPersistentPathDirs();

/// The registry keys holding the persistent `PATH`, Machine first so that a
/// per-user addition lands after the system's, the way a login shell sees it.
const List<String> _windowsPathKeys = <String>[
  r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
  r'HKCU\Environment',
];

/// Best-effort read of the persistent Windows `PATH` via `reg query`. Returns
/// `const []` on any failure and never throws — a missing or locked registry
/// must degrade to "no augmentation", not a crash on the engine-spawn path.
///
/// `reg` is resolved to an absolute path first, like every spawn in the
/// suite, and not run at all when nothing on `PATH` answers to it: this runs
/// on the engine-spawn path, where the launching directory is the user's
/// repository, and a bare name would be searched for there.
List<String> _readWindowsPersistentPathDirs() {
  final String reg;
  try {
    reg = requireSpawnExecutableForHost('reg');
  } on ProcessException {
    return const <String>[];
  }
  final dirs = <String>[];
  for (final key in _windowsPathKeys) {
    try {
      final result = Process.runSync(reg, <String>[
        'query',
        key,
        '/v',
        'Path',
      ]);
      if (result.exitCode != 0) continue;
      final out = result.stdout;
      if (out is! String) continue;
      dirs.addAll(
        parseWindowsPersistentPath(out, environment: Platform.environment),
      );
    } on Object {
      // reg.exe absent / access denied / malformed output — skip this key.
    }
  }
  return List<String>.unmodifiable(dirs);
}

/// Extracts the directories of a `Path` value from one `reg query` output.
///
/// The value line has the shape `    Path    REG_SZ    <dirs to end-of-line>`
/// (also `REG_EXPAND_SZ`, whose value may hold `%VAR%` references that are
/// expanded against [environment], unknown variables left intact). The
/// `(?<!\S)` guard keeps `PATHEXT`, and paths that merely contain "Path", from
/// matching: the type token must follow the value name `Path` itself.
///
/// Pure, so the parse is testable on every host; the registry read that
/// feeds it only runs on Windows.
@visibleForTesting
List<String> parseWindowsPersistentPath(
  String regQueryOutput, {
  required Map<String, String> environment,
}) {
  final match = RegExp(
    r'(?<!\S)Path\s+REG(?:_EXPAND)?_SZ\s+(.+)',
  ).firstMatch(regQueryOutput);
  if (match == null) return const <String>[];
  final dirs = <String>[];
  for (final segment in match.group(1)!.split(';')) {
    final dir = _expandWindowsEnv(segment, environment).trim();
    if (dir.isNotEmpty) dirs.add(dir);
  }
  return dirs;
}

/// Expands `%VAR%` references using [environment], leaving unknown variables
/// intact. `REG_EXPAND_SZ` stores `PATH` unexpanded (`%USERPROFILE%\bin`).
String _expandWindowsEnv(String value, Map<String, String> environment) =>
    value.replaceAllMapped(
      RegExp('%([^%]+)%'),
      (m) => environment[m.group(1)!] ?? m.group(0)!,
    );

/// Appends every directory in [extraDirs] not already present in
/// [currentPath] (compared case-insensitively when [caseInsensitive], which
/// callers set on Windows), preserving order and never shadowing an existing
/// entry. Returns `null` when nothing needs adding, so callers can leave the
/// inherited environment untouched.
String? appendMissingPathDirs(
  String currentPath,
  List<String> extraDirs, {
  required String separator,
  required bool caseInsensitive,
}) {
  final segments = currentPath
      .split(separator)
      .where((s) => s.isNotEmpty)
      .toList();
  bool present(String dir) => caseInsensitive
      ? segments.any((s) => s.toLowerCase() == dir.toLowerCase())
      : segments.contains(dir);
  final missing = extraDirs.where((d) => !present(d)).toList(growable: false);
  if (missing.isEmpty) return null;
  return <String>[...segments, ...missing].join(separator);
}

/// The environment to spawn [executable] with so that an OSS CAD Suite tool
/// loads its own DLLs, or [environment] unchanged when no adjustment applies.
///
/// On Windows the suite keeps `yosys.exe` and its siblings in `bin` and the
/// DLLs they load in `lib`; its `environment.bat` puts both at the **front**
/// of `PATH`. A user who adds them to `PATH` by hand usually adds them after
/// other entries, and a toolchain earlier on `PATH` that ships a same-named
/// DLL (a MinGW runtime, say) is then loaded instead. The tool starts, prints
/// nothing and exits, and the product reports it as unusable although the
/// install is fine.
///
/// So when [executable] is an absolute path inside an install's `bin`,
/// recognised by `environment.bat` beside it, the child's `PATH` gets that
/// `bin` and `lib` first, as `environment.bat` would set them. Only this child
/// is affected; [parentEnvironment] (the variables the child would otherwise
/// inherit) is copied, never changed. Off Windows, or for any other binary,
/// [environment] is returned as given, `null` included.
///
/// [isFile] and [isDirectory] are seams so the rule is testable on any host.
Map<String, String>? ossCadSuiteSpawnEnvironment(
  String executable,
  Map<String, String>? environment, {
  required bool windows,
  required Map<String, String> parentEnvironment,
  bool Function(String path)? isFile,
  bool Function(String path)? isDirectory,
}) {
  if (!windows) return environment;
  final ctx = p.windows;
  if (!ctx.isAbsolute(executable)) return environment;
  final bin = ctx.dirname(ctx.normalize(executable));
  if (ctx.basename(bin).toLowerCase() != 'bin') return environment;
  final root = ctx.dirname(bin);
  final lib = ctx.join(root, 'lib');
  final fileExists = isFile ?? (path) => File(path).existsSync();
  final dirExists = isDirectory ?? (path) => Directory(path).existsSync();
  try {
    if (!fileExists(ctx.join(root, 'environment.bat')) || !dirExists(lib)) {
      return environment;
    }
  } on Object {
    return environment;
  }
  final base = environment ?? parentEnvironment;
  final pathKey = base.keys.firstWhere(
    (k) => k.toUpperCase() == 'PATH',
    orElse: () => parentEnvironment.keys.firstWhere(
      (k) => k.toUpperCase() == 'PATH',
      orElse: () => 'Path',
    ),
  );
  final current =
      base[pathKey] ??
      parentEnvironment.entries
          .where((e) => e.key.toUpperCase() == 'PATH')
          .map((e) => e.value)
          .firstOrNull ??
      '';
  final reordered = prependPathDirs(
    current,
    <String>[bin, lib],
    separator: ';',
    caseInsensitive: true,
  );
  if (reordered == null) return environment;
  return <String, String>{...base, pathKey: reordered};
}

/// Puts [dirs] at the front of [currentPath], in order, removing their other
/// occurrences (compared case-insensitively when [caseInsensitive]). Returns
/// `null` when [currentPath] already starts with exactly [dirs].
String? prependPathDirs(
  String currentPath,
  List<String> dirs, {
  required String separator,
  required bool caseInsensitive,
}) {
  String key(String s) => caseInsensitive ? s.toLowerCase() : s;
  final segments = currentPath
      .split(separator)
      .where((s) => s.isNotEmpty)
      .toList();
  final wanted = dirs.map(key).toSet();
  final alreadyFirst =
      segments.length >= dirs.length &&
      List<int>.generate(
        dirs.length,
        (i) => i,
      ).every((i) => key(segments[i]) == key(dirs[i]));
  if (alreadyFirst) return null;
  return <String>[
    ...dirs,
    ...segments.where((s) => !wanted.contains(key(s))),
  ].join(separator);
}

/// Test seam: clears the cached answer (the Windows registry read, or the
/// macOS and Linux list) so a test can force a re-read (the production cache
/// is process-lifetime).
@visibleForTesting
void resetEngineSearchDirsCacheForTesting() {
  _cachedWindowsPathDirs = null;
  _cachedPosixDirs = null;
}
