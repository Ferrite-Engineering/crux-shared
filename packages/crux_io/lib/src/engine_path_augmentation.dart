// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/src/spawn_guards.dart';
import 'package:meta/meta.dart';

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
///   `/opt/homebrew/bin` and `/usr/local/bin`.
/// - **Windows**: the persistent (registry) `PATH` — Machine then User — that
///   a freshly-logged-in process inherits, including the `lib` DLL directory
///   Yosys and Verilator need. Appending it restores the post-reboot view
///   without an actual reboot. Read from the registry once and cached for the
///   process lifetime.
/// - **Linux**: none; the desktop session's `PATH` is inherited normally.
///
/// Desktop only: it reads `Platform`, which a web build cannot, and a browser
/// spawns no engines. Like the atomic writes, a web build must not call it.
///
/// This was carried as three byte-identical copies, one per product that
/// spawns an engine, each header asking to be moved here.
List<String> engineSearchDirs() {
  if (Platform.isMacOS) {
    return const <String>['/opt/homebrew/bin', '/usr/local/bin'];
  }
  if (Platform.isWindows) return _windowsPersistentPathDirs();
  return const <String>[];
}

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

/// Test seam: clears the cached Windows registry read so a test can force a
/// re-read (the production cache is process-lifetime).
@visibleForTesting
void resetEngineSearchDirsCacheForTesting() => _cachedWindowsPathDirs = null;
