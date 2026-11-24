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
///
/// A non-null [version] is written as `X-AppImage-Version`, the key the
/// integrator reads to avoid replacing a newer AppImage's entry.
String buildDesktopEntry(
  LinuxDesktopApp app, {
  required String appImagePath,
  String? version,
}) {
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
      '${version == null ? '' : '$appImageVersionKey=$version\n'}'
      '${mimeTypes.isEmpty ? '' : 'MimeType=$mimeTypes\n'}';
}

/// The desktop-entry key holding the version of the AppImage the entry names.
const String appImageVersionKey = 'X-AppImage-Version';

/// The program path in [entryText]'s `Exec=` line, or `null` when absent.
///
/// Undoes [quoteDesktopExecArgument]: the general string escapes first, then
/// the `Exec` quoting rule. An unquoted program ends at the first space.
String? parseDesktopExecProgram(String entryText) {
  for (final line in entryText.split('\n')) {
    if (!line.startsWith('Exec=')) continue;
    final value = line.substring('Exec='.length);
    final unescaped = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == r'\' && i + 1 < value.length) {
        i++;
        unescaped.write(switch (value[i]) {
          'n' => '\n',
          't' => '\t',
          'r' => '\r',
          final other => other,
        });
      } else {
        unescaped.write(char);
      }
    }
    final text = unescaped.toString();
    final program = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '"') {
        if (inQuotes) break;
        inQuotes = true;
      } else if (inQuotes && char == r'\' && i + 1 < text.length) {
        i++;
        program.write(text[i]);
      } else if (char == '%' && i + 1 < text.length && text[i + 1] == '%') {
        i++;
        program.write('%');
      } else if (!inQuotes && char == ' ') {
        break;
      } else {
        program.write(char);
      }
    }
    return program.isEmpty ? null : program.toString();
  }
  return null;
}

/// The value of `X-AppImage-Version` in [entryText], or `null`.
String? parseAppImageVersion(String entryText) {
  const prefix = '$appImageVersionKey=';
  for (final line in entryText.split('\n')) {
    if (line.startsWith(prefix)) {
      final value = line.substring(prefix.length).trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

final RegExp _fileNameVersion = RegExp(r'-(\d+\.\d+\.\d+)(?=-|\.AppImage$)');

/// The version in an AppImage file name such as
/// `SimCrux Pro-1.2.0-x86_64.AppImage`, or `null` when it carries none.
String? appImageVersionFromFileName(String appImagePath) {
  final name = appImagePath.split(RegExp(r'[\\/]')).last;
  return _fileNameVersion.firstMatch(name)?.group(1);
}

/// Whether version [a] is strictly newer than [b], comparing the leading
/// numeric dot-separated parts. `false` when either has none.
bool isNewerAppImageVersion(String a, String b) {
  List<int>? parts(String v) {
    final match = RegExp(r'^\d+(\.\d+)*').firstMatch(v.trim());
    return match?.group(0)?.split('.').map(int.parse).toList();
  }

  final left = parts(a);
  final right = parts(b);
  if (left == null || right == null) return false;
  for (var i = 0; i < left.length || i < right.length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x > y;
  }
  return false;
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
