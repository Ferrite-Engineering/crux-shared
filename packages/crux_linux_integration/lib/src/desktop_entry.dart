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
/// is quoted with [quoteDesktopExecArgument] because AppImage files routinely
/// live under paths with spaces
/// (`~/Downloads/SimCrux Pro-0.1.0-x86_64.AppImage`).
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
///
/// URL schemes are not claimed here; see [buildUrlHandlerEntry].
String buildDesktopEntry(LinuxDesktopApp app, {required String appImagePath}) {
  final categories = app.categories.map((c) => '$c;').join();
  final mimeTypes = app.claimedTypeNames.map((m) => '$m;').join();
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=${app.name}\n'
      'Comment=${app.comment}\n'
      'Exec=${quoteDesktopExecArgument(appImagePath)} %F\n'
      'Icon=${app.appId}\n'
      'StartupWMClass=${app.appId}\n'
      'Terminal=false\n'
      'Categories=$categories\n'
      '${mimeTypes.isEmpty ? '' : 'MimeType=$mimeTypes\n'}';
}

/// The file name of [appId]'s hidden URL-handler entry, written beside
/// `<appId>.desktop`.
String urlHandlerDesktopFileName(String appId) => '$appId-url-handler.desktop';

final RegExp _schemePattern = RegExp(r'^[a-z][a-z0-9+.\-]*$');

/// Builds the hidden entry that claims [LinuxDesktopApp.urlSchemes] for the
/// AppImage at [appImagePath], or returns `null` when the application declares
/// none.
///
/// It is a second entry rather than a line on the main one because a link has
/// to arrive as one argument (`%u`), while the main entry passes double-clicked
/// files as paths (`%F`); `%U` on the main entry would deliver every file as a
/// `file://` URI. `NoDisplay=true` keeps it out of menus, and it carries no
/// `StartupWMClass`, so the dock keeps matching the window to the main entry.
///
/// Throws [ArgumentError] for a scheme that is not lowercase RFC 3986 syntax.
String? buildUrlHandlerEntry(
  LinuxDesktopApp app, {
  required String appImagePath,
}) {
  if (app.urlSchemes.isEmpty) return null;
  for (final scheme in app.urlSchemes) {
    if (!_schemePattern.hasMatch(scheme)) {
      throw ArgumentError.value(
        scheme,
        'urlSchemes',
        'a scheme is a lowercase letter followed by letters, digits, '
            '"+", "-" or "."',
      );
    }
  }
  final handlers = app.urlSchemes
      .map((s) => 'x-scheme-handler/$s;')
      .toSet()
      .join();
  return '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=${app.name}\n'
      'Exec=${quoteDesktopExecArgument(appImagePath)} %u\n'
      'Icon=${app.appId}\n'
      'Terminal=false\n'
      'NoDisplay=true\n'
      'MimeType=$handlers\n';
}

/// Quotes [argument] for an `Exec=` key so it reaches the program as exactly
/// one argument, whatever characters it holds.
///
/// The Desktop Entry Specification applies two layers, and a reader undoes
/// them in order: the general string escapes first (`\\`, `\n`, `\t`, `\r`),
/// then the `Exec` quoting rule. So this applies them in reverse:
///
/// 1. The quoting rule: the argument is enclosed in double quotes, and `"`,
///    `` ` ``, `$` and `\` inside it are each preceded by a backslash. A
///    literal `%` is written `%%`, so it is never read as a field code.
/// 2. The general string escapes: every backslash the first step produced is
///    doubled, and a newline, tab or carriage return becomes `\n`, `\t` or
///    `\r`.
///
/// That is why the specification writes a literal backslash as four
/// backslashes and a dollar sign as `\\$`. A path with none of these
/// characters is simply wrapped in double quotes.
String quoteDesktopExecArgument(String argument) {
  final quoted = StringBuffer();
  for (final rune in argument.runes) {
    final char = String.fromCharCode(rune);
    switch (char) {
      case '"' || '`' || r'$' || r'\':
        quoted.write('\\$char');
      case '%':
        quoted.write('%%');
      default:
        quoted.write(char);
    }
  }
  final escaped = StringBuffer('"');
  for (final rune in quoted.toString().runes) {
    final char = String.fromCharCode(rune);
    switch (char) {
      case r'\':
        escaped.write(r'\\');
      case '\n':
        escaped.write(r'\n');
      case '\t':
        escaped.write(r'\t');
      case '\r':
        escaped.write(r'\r');
      default:
        escaped.write(char);
    }
  }
  escaped.write('"');
  return escaped.toString();
}
