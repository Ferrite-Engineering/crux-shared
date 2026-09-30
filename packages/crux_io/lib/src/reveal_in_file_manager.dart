// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/src/spawn_environment.dart';
import 'package:crux_io/src/spawn_guards.dart';

/// Runs one file-manager command and answers its exit code. The seam
/// [revealInFileManager] spawns through.
typedef RevealCommandRunner =
    Future<int> Function(String executable, List<String> arguments);

/// Best-effort reveal of [filePath] in the platform file manager, selecting
/// the file where the platform supports it.
///
/// - macOS: `open -R <path>` (Finder, file selected)
/// - Windows: `explorer /select,<path>` (Explorer, file selected). The switch
///   and the path are one argument; split in two, Explorer ignores the switch
///   and opens the folder without selecting anything.
/// - Linux: `dbus-send` to org.freedesktop.FileManager1 (file selected),
///   falling back to `xdg-open` on the containing directory. The file is
///   passed to D-Bus as a `file:` URI, percent-encoded, so a name holding a
///   space, `#` or `%` still names the file.
///
/// Every command goes through [requireSpawnExecutable] before it is spawned.
/// On Windows that turns `explorer` into an absolute path, so an
/// `explorer.exe` in the directory the product was launched from cannot run
/// in its place; and if nothing on `PATH` answers to the name, nothing is
/// spawned at all, because a bare name would be searched for in that same
/// directory.
///
/// Failures are swallowed — a reveal is a convenience, never worth an error
/// surface. Returns whether a reveal command was launched.
///
/// The suite's tab context menus ("Reveal in Finder / Explorer / Files")
/// call this; it replaced a per-app no-op stub that silently did nothing.
///
/// The named parameters are the host, injectable so every platform's branch
/// runs on any machine without spawning anything. Each defaults to the live
/// value, and a product passes none of them:
///
/// - [operatingSystem]: a `Platform.operatingSystem` value (`macos`,
///   `windows`, `linux`).
/// - [environment]: where `PATH` and `PATHEXT` are read from.
/// - [exists]: the on-disk probe the resolution uses.
/// - [runCommand]: the spawn itself.
Future<bool> revealInFileManager(
  String filePath, {
  String? operatingSystem,
  Map<String, String>? environment,
  bool Function(String path)? exists,
  RevealCommandRunner? runCommand,
}) async {
  try {
    final os = operatingSystem ?? Platform.operatingSystem;
    final windows = os == 'windows';
    final env = environment ?? Platform.environment;
    final run = runCommand ?? _runCommand;

    // Throws the not-found ProcessException on Windows rather than handing
    // back a bare name; the catch below turns that into "nothing revealed".
    String resolve(String name) => requireSpawnExecutable(
      name,
      pathEnvironment: spawnEnvironmentValue(env, 'PATH', windows: windows),
      windows: windows,
      pathExt: spawnEnvironmentValue(env, 'PATHEXT', windows: windows),
      exists: exists,
    );

    switch (os) {
      case 'macos':
        await run(resolve('open'), <String>['-R', filePath]);
        return true;
      case 'windows':
        await run(resolve('explorer'), <String>['/select,$filePath']);
        return true;
      case 'linux':
        final viaDbus = await run(resolve('dbus-send'), <String>[
          '--session',
          '--dest=org.freedesktop.FileManager1',
          '--type=method_call',
          '/org/freedesktop/FileManager1',
          'org.freedesktop.FileManager1.ShowItems',
          'array:string:${Uri.file(filePath, windows: false)}',
          'string:',
        ]);
        if (viaDbus == 0) return true;
        final dir = File(filePath).parent.path;
        await run(resolve('xdg-open'), <String>[dir]);
        return true;
    }
  } on Object {
    // Best-effort: no file manager, sandboxed, or command missing.
  }
  return false;
}

Future<int> _runCommand(String executable, List<String> arguments) async =>
    (await Process.run(executable, arguments)).exitCode;
