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
    this.urlHandlerFilePath,
    this.iconCount = 0,
  });

  /// The host entry and icons were written (or rewritten after a move/update).
  factory DesktopIntegrationResult.integrated({
    required String desktopFilePath,
    required int iconCount,
    String? mimePackagePath,
    String? urlHandlerFilePath,
  }) => DesktopIntegrationResult._(
    DesktopIntegrationStatus.integrated,
    desktopFilePath: desktopFilePath,
    mimePackagePath: mimePackagePath,
    urlHandlerFilePath: urlHandlerFilePath,
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
      DesktopIntegrationResult._(DesktopIntegrationStatus.failed, error: error);

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

  /// Absolute path of the hidden `<appId>-url-handler.desktop` entry, when
  /// the app declares URL schemes. Null when it declares none — including when
  /// an entry an earlier integration wrote was removed.
  final String? urlHandlerFilePath;

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

      // Built before anything is written, so an invalid scheme fails the
      // integration without leaving a half-updated pair of entries behind.
      final urlHandlerText = buildUrlHandlerEntry(app, appImagePath: appImage);

      final desktopFile = File(
        p.join(_applicationsDir.path, '${app.appId}.desktop'),
      );
      desktopFile.parent.createSync(recursive: true);
      desktopFile.writeAsStringSync(
        buildDesktopEntry(app, appImagePath: appImage),
      );

      final urlHandler = _installUrlHandler(app, urlHandlerText);
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
        urlHandlerFilePath: urlHandler,
        iconCount: iconCount,
      );
    } on Object catch (e) {
      return DesktopIntegrationResult.failed(e.toString());
    }
  }

  /// Removes everything [integrate] installed for [app]: the main entry, the
  /// hidden URL-handler entry, the MIME package, the copied icons and the
  /// marker, then refreshes the caches so no launcher, file manager or browser
  /// keeps offering an application that is gone.
  ///
  /// It does not look at `APPIMAGE`, so it works from a native build or a
  /// script as well as from the AppImage being removed. Returns the paths it
  /// deleted. Never throws: a file that cannot be deleted is left in place and
  /// omitted from the list.
  Future<List<String>> uninstall(LinuxDesktopApp app) async {
    final removed = <String>[];
    var mimeChanged = false;
    void delete(File file, {bool mime = false}) {
      try {
        if (!file.existsSync()) return;
        file.deleteSync();
        removed.add(file.path);
        if (mime) mimeChanged = true;
      } on Object {
        // Best-effort: a file that cannot be deleted stays, and the rest of
        // the removal goes ahead.
      }
    }

    delete(File(p.join(_applicationsDir.path, '${app.appId}.desktop')));
    delete(
      File(p.join(_applicationsDir.path, urlHandlerDesktopFileName(app.appId))),
    );
    delete(
      File(p.join(_mimeDir.path, 'packages', '${app.appId}.xml')),
      mime: true,
    );
    try {
      if (_hicolorDir.existsSync()) {
        for (final size in _hicolorDir.listSync().whereType<Directory>()) {
          delete(File(p.join(size.path, 'apps', '${app.appId}.png')));
        }
      }
    } on Object {
      // An unreadable icon theme leaves the icons; the entries are gone.
    }
    delete(_markerFile(app.appId));

    await _refreshCaches(mimeChanged: mimeChanged);
    return removed;
  }

  /// Writes [app]'s hidden URL-handler entry [text], or, when it is null
  /// because the app declares no scheme, removes the one an earlier
  /// integration left behind. Returns the entry's path when one was written.
  ///
  /// Removal matters for the same reason as the MIME package's: a stale entry
  /// keeps routing `<scheme>://` links to an AppImage that no longer handles
  /// them, or no longer exists.
  String? _installUrlHandler(LinuxDesktopApp app, String? text) {
    final file = File(
      p.join(_applicationsDir.path, urlHandlerDesktopFileName(app.appId)),
    );
    if (text == null) {
      if (file.existsSync()) file.deleteSync();
      return null;
    }
    file.writeAsStringSync(text);
    return file.path;
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
    final file = File(p.join(_mimeDir.path, 'packages', '${app.appId}.xml'));
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
