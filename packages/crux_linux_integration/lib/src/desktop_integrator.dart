// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_linux_integration/src/desktop_entry.dart';
import 'package:crux_linux_integration/src/linux_desktop_app.dart';
import 'package:crux_linux_integration/src/mime_package.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Runs a best-effort desktop-cache refresh command (`executable` +
/// `arguments`).
///
/// Injected into [DesktopIntegrator] so tests can record the two refresh
/// invocations without spawning processes. The default implementation shells
/// out with [Process.run]; any failure (command absent, non-zero exit) is
/// swallowed by the integrator, never surfaced to the caller.
typedef DesktopCacheRunner =
    Future<void> Function(
      String executable,
      List<String> arguments,
    );

Future<void> _defaultCacheRunner(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// Why an [DesktopIntegrator.integrate] call did no work.
enum DesktopIntegrationSkipReason {
  /// The process is not running from an AppImage (`APPIMAGE` is unset), so
  /// there is nothing to self-integrate — native/deb installs already own a
  /// host-side `.desktop`.
  notAppImage,

  /// The marker file already records this exact AppImage path and mtime, so
  /// the host entry is current and was left untouched.
  alreadyCurrent,
}

/// Outcome of an [DesktopIntegrator.integrate] call.
///
/// Integration never throws; every path — including internal failure —
/// resolves to one of these so a caller can log the result without a
/// `try`/`catch`.
@immutable
class DesktopIntegrationResult {
  const DesktopIntegrationResult._(
    this.status, {
    this.skipReason,
    this.error,
    this.desktopFilePath,
    this.mimePackagePath,
    this.iconCount = 0,
  });

  /// The host entry and icons were written (or rewritten after a move/update).
  factory DesktopIntegrationResult.integrated({
    required String desktopFilePath,
    required int iconCount,
    String? mimePackagePath,
  }) => DesktopIntegrationResult._(
    DesktopIntegrationStatus.integrated,
    desktopFilePath: desktopFilePath,
    mimePackagePath: mimePackagePath,
    iconCount: iconCount,
  );

  /// No work was needed; see [reason].
  factory DesktopIntegrationResult.skipped(
    DesktopIntegrationSkipReason reason,
  ) => DesktopIntegrationResult._(
    DesktopIntegrationStatus.skipped,
    skipReason: reason,
  );

  /// Integration was attempted but an unexpected error was caught and
  /// swallowed; [error] carries its string form for logging.
  factory DesktopIntegrationResult.failed(String error) =>
      DesktopIntegrationResult._(
        DesktopIntegrationStatus.failed,
        error: error,
      );

  /// Coarse outcome bucket.
  final DesktopIntegrationStatus status;

  /// Populated when [status] is [DesktopIntegrationStatus.skipped].
  final DesktopIntegrationSkipReason? skipReason;

  /// Populated when [status] is [DesktopIntegrationStatus.failed].
  final String? error;

  /// Absolute path of the written `.desktop` file, when integrated.
  final String? desktopFilePath;

  /// Absolute path of the installed `shared-mime-info` package, when the app
  /// declares types of its own. Null when it declares none — including when a
  /// package this app had installed before was removed because it no longer
  /// declares any.
  final String? mimePackagePath;

  /// Number of icon sizes copied to the host, when integrated.
  final int iconCount;
}

/// Coarse outcome bucket for [DesktopIntegrationResult].
enum DesktopIntegrationStatus {
  /// The host entry/icons were written.
  integrated,

  /// Nothing was done; see [DesktopIntegrationResult.skipReason].
  skipped,

  /// An error was caught and swallowed; see [DesktopIntegrationResult.error].
  failed,
}

/// Idempotent AppImage first-run desktop self-integration.
///
/// When a suite app runs from an AppImage, the compositor has no host-side
/// `.desktop` whose `StartupWMClass` matches the running window's `app_id`, so
/// GNOME/Ubuntu shows a generic dock icon. [integrate] fixes that the standard
/// AppImage way: it writes the app's own `.desktop` and hicolor icons into the
/// user's XDG data dir (`~/.local/share`), keyed on the application id.
///
/// All filesystem roots and the cache-refresh command are injected so the
/// whole flow is unit-testable off-Linux against a fake `HOME`/`APPDIR` tree.
class DesktopIntegrator {
  /// Creates an integrator rooted at [homeDir], reading AppImage location from
  /// [env] (`APPIMAGE`, `APPDIR`), refreshing caches through [cacheRunner]
  /// (defaults to a real [Process.run]).
  DesktopIntegrator({
    required this.homeDir,
    required this.env,
    DesktopCacheRunner? cacheRunner,
  }) : cacheRunner = cacheRunner ?? _defaultCacheRunner;

  /// The user's home directory (`$HOME`), the root of `.local/share`.
  final String homeDir;

  /// The process environment; `APPIMAGE` (the AppImage file) and `APPDIR`
  /// (its mount point) are read from it.
  final Map<String, String> env;

  /// Best-effort desktop/icon cache refresher.
  final DesktopCacheRunner cacheRunner;

  /// The user's XDG data home: `$XDG_DATA_HOME` when the session sets it,
  /// and `$HOME/.local/share` otherwise, which is what the specification says
  /// it defaults to. Writing to the default while the session points
  /// elsewhere installs entries nothing reads.
  String get _dataHome {
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    return p.join(homeDir, '.local', 'share');
  }

  /// Directory holding host `.desktop` entries.
  Directory get _applicationsDir =>
      Directory(p.join(_dataHome, 'applications'));

  /// Root of the host hicolor icon theme.
  Directory get _hicolorDir => Directory(p.join(_dataHome, 'icons', 'hicolor'));

  /// The user's MIME database, and the directory `shared-mime-info` packages
  /// are installed into.
  Directory get _mimeDir => Directory(p.join(_dataHome, 'mime'));

  /// The per-app marker recording which AppImage was last integrated.
  File _markerFile(String appId) =>
      File(p.join(_dataHome, 'crux', '$appId.appimage-integrated'));

  /// Writes [app]'s host `.desktop` + icons if running from an AppImage and
  /// the marker is missing or stale.
  ///
  /// Never throws: any error is caught and returned as
  /// [DesktopIntegrationResult.failed].
  Future<DesktopIntegrationResult> integrate(LinuxDesktopApp app) async {
    try {
      final appImage = env['APPIMAGE'];
      if (appImage == null || appImage.isEmpty) {
        return DesktopIntegrationResult.skipped(
          DesktopIntegrationSkipReason.notAppImage,
        );
      }

      final signature = _signatureFor(appImage);
      final marker = _markerFile(app.appId);
      if (signature != null &&
          marker.existsSync() &&
          marker.readAsStringSync() == signature) {
        return DesktopIntegrationResult.skipped(
          DesktopIntegrationSkipReason.alreadyCurrent,
        );
      }

      final desktopFile = File(
        p.join(_applicationsDir.path, '${app.appId}.desktop'),
      );
      desktopFile.parent.createSync(recursive: true);
      desktopFile.writeAsStringSync(
        buildDesktopEntry(app, appImagePath: appImage),
      );

      final mimePackage = _installMimePackage(app);
      final iconCount = _installIcons(app);

      await _refreshCaches(mimeChanged: mimePackage.changed);

      if (signature != null) {
        marker.parent.createSync(recursive: true);
        marker.writeAsStringSync(signature);
      }

      return DesktopIntegrationResult.integrated(
        desktopFilePath: desktopFile.path,
        mimePackagePath: mimePackage.path,
        iconCount: iconCount,
      );
    } on Object catch (e) {
      return DesktopIntegrationResult.failed(e.toString());
    }
  }

  /// A stable fingerprint of the current AppImage: its path plus size and
  /// mtime, so a moved *or* updated AppImage produces a fresh value and
  /// triggers re-integration. Returns `null` if the file cannot be stat-ed.
  String? _signatureFor(String appImagePath) {
    try {
      final stat = File(appImagePath).statSync();
      if (stat.type == FileSystemEntityType.notFound) return null;
      return '$appImagePath\n'
          '${stat.size}\n'
          '${stat.modified.microsecondsSinceEpoch}';
    } on FileSystemException {
      return null;
    }
  }

  /// Copies every `<size>/apps/<appId>.png` present under the mounted AppDir's
  /// hicolor theme to the matching host path. Missing `APPDIR`, a missing
  /// theme dir, or a missing size are all tolerated. Returns the count copied.
  int _installIcons(LinuxDesktopApp app) {
    final appDir = env['APPDIR'];
    if (appDir == null || appDir.isEmpty) return 0;

    final srcHicolor = Directory(
      p.join(appDir, 'usr', 'share', 'icons', 'hicolor'),
    );
    if (!srcHicolor.existsSync()) return 0;

    var copied = 0;
    for (final entry in srcHicolor.listSync().whereType<Directory>()) {
      final size = p.basename(entry.path);
      final src = File(p.join(entry.path, 'apps', '${app.appId}.png'));
      if (!src.existsSync()) continue;
      final dest = File(
        p.join(_hicolorDir.path, size, 'apps', '${app.appId}.png'),
      );
      dest.parent.createSync(recursive: true);
      src.copySync(dest.path);
      copied++;
    }
    return copied;
  }

  /// Writes [app]'s `shared-mime-info` package, or removes the one it left
  /// behind when it no longer declares any type of its own.
  ///
  /// The second half is what keeps a withdrawn type from outliving the
  /// application: the file is the only place the user's MIME database learns
  /// it from, so leaving it behind would keep a `.desktop` entry that no
  /// longer claims the type matched against files nothing opens.
  ({String? path, bool changed}) _installMimePackage(LinuxDesktopApp app) {
    final file = File(
      p.join(_mimeDir.path, 'packages', '${app.appId}.xml'),
    );
    final xml = buildMimePackage(app);
    if (xml == null) {
      if (!file.existsSync()) return (path: null, changed: false);
      file.deleteSync();
      return (path: null, changed: true);
    }
    file.parent.createSync(recursive: true);
    // Rewritten every time the entry is, so a changed glob or description
    // lands with it rather than a release later.
    file.writeAsStringSync(xml);
    return (path: file.path, changed: true);
  }

  /// Best-effort refresh of the MIME, desktop and icon caches. Every command
  /// may be absent or fail; each error is swallowed so integration never
  /// breaks on a minimal desktop that lacks the freedesktop tooling.
  ///
  /// The MIME database goes first: `update-desktop-database` maps types to
  /// applications, and a type it has not been taught yet maps to none.
  Future<void> _refreshCaches({required bool mimeChanged}) async {
    if (mimeChanged) {
      await _runQuietly('update-mime-database', [_mimeDir.path]);
    }
    await _runQuietly('update-desktop-database', [_applicationsDir.path]);
    await _runQuietly('gtk-update-icon-cache', ['-f', '-t', _hicolorDir.path]);
  }

  Future<void> _runQuietly(String executable, List<String> arguments) async {
    try {
      await cacheRunner(executable, arguments);
    } on Object {
      // Best-effort: a missing or failing cache tool must never abort
      // integration — the entry, the MIME package and the icons are already
      // on disk, and a desktop that gains the tooling later picks them up.
    }
  }
}
