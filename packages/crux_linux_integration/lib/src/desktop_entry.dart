// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/src/linux_desktop_app.dart';

/// Builds the freedesktop `.desktop` entry text for [app] pointing at the
/// AppImage at [appImagePath].
///
/// The field set mirrors the entry each AppImage recipe
/// (`scripts/package_appimage.sh`) bakes into the AppDir, with one deliberate
/// difference: the host-side `Exec` points at the concrete AppImage file
/// (which is not on `PATH`) rather than the bare executable name, and the path
/// is double-quoted because AppImage files routinely live under paths with
/// spaces (`~/Downloads/SimCrux Pro-0.1.0-x86_64.AppImage`).
///
/// `Icon` and `StartupWMClass` both resolve to [LinuxDesktopApp.appId] so the
/// Wayland compositor can match the running window (whose `app_id` the GTK
/// runner sets to the same id) to this entry and show the installed icon.
///
/// `MimeType` lists every type the application claims — the ones it declares
/// itself and the ones the system already maps — because that list is what
/// makes a file manager offer it for the files it opens. It is written only
/// when there is something to claim: an empty `MimeType=` claims nothing and
/// is a line some launchers refuse to parse. An extension left unmapped on
/// purpose contributes nothing here.
String buildDesktopEntry(
  LinuxDesktopApp app, {
  required String appImagePath,
}) {
  final categories = app.categories.map((c) => '$c;').join();
  final mimeTypes = app.claimedTypeNames.map((m) => '$m;').join();
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=${app.name}\n'
      'Comment=${app.comment}\n'
      'Exec="$appImagePath" %F\n'
      'Icon=${app.appId}\n'
      'StartupWMClass=${app.appId}\n'
      'Terminal=false\n'
      'Categories=$categories\n'
      '${mimeTypes.isEmpty ? '' : 'MimeType=$mimeTypes\n'}';
}
