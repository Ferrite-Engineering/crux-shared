// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/src/linux_mime_type.dart';
import 'package:meta/meta.dart';

/// Immutable description of one Crux application's freedesktop identity, used
/// to synthesize its host-side `.desktop` entry during AppImage
/// self-integration.
///
/// The four suite apps each construct one of these from the constants baked
/// into their AppImage recipe (`scripts/package_appimage.sh`): the
/// [appId] is the reverse-DNS application id the GTK runner also sets as the
/// window's Wayland `app_id` / X11 `WM_CLASS`, so the generated entry's
/// `StartupWMClass` and `Icon` both key on it and GNOME/Ubuntu can match the
/// running window to this entry's dock icon.
@immutable
class LinuxDesktopApp {
  /// Creates a description of a Crux app's freedesktop identity.
  const LinuxDesktopApp({
    required this.appId,
    required this.name,
    required this.comment,
    required this.execName,
    this.categories = const ['Development', 'Electronics'],
    this.mimeTypes = const <String>[],
    this.fileTypes = const <LinuxMimeType>[],
  });

  /// Reverse-DNS application id, e.g. `com.ferriteengineering.simcrux_pro`.
  ///
  /// This is the value the GTK runner assigns as the window's `app_id` /
  /// `WM_CLASS`, so it is also used verbatim as the `.desktop` filename, the
  /// installed icon filename, and the `Icon` / `StartupWMClass` fields.
  final String appId;

  /// Human-readable application name, e.g. `SimCrux Pro`.
  final String name;

  /// One-line description shown by launchers, e.g.
  /// `Simulation regression runner and dashboard for HDL testbenches`.
  final String comment;

  /// The bundle's executable name, e.g. `simcrux_pro`.
  ///
  /// Carried for completeness / diagnostics; the host `Exec=` line points at
  /// the AppImage path rather than this bare name (an AppImage is not on the
  /// user's `PATH`).
  final String execName;

  /// freedesktop menu categories, rendered as a semicolon-terminated list.
  ///
  /// Defaults to `Development;Electronics;`, matching every suite AppImage
  /// recipe.
  final List<String> categories;

  /// Bare MIME names for the entry's `MimeType=` list.
  ///
  /// **Superseded by [fileTypes], and inert for a type of our own.** A name
  /// here reaches the entry and nothing else, so a file manager — which types
  /// a file before it looks for handlers — never matches
  /// `application/x-netcrux-project` against anything: nothing maps the
  /// extension. Only a type the desktop already maps works this way.
  ///
  /// Move each entry to [fileTypes], which installs the mapping our own types
  /// need. This list is kept until the four products have; it is an error to
  /// pass both.
  final List<String> mimeTypes;

  /// The file kinds this application opens: what goes in the entry's
  /// `MimeType=` list, what goes in the installed `shared-mime-info` package,
  /// and what is deliberately left to other applications. Empty — the default
  /// — omits `MimeType=` and installs no package.
  ///
  /// **Both halves are needed for a type of ours.** "Open With" reads the
  /// entry, but a file manager types the file first: with nothing mapping
  /// `*.netcrux-project` the file is typed as JSON or text and the
  /// application is never offered, however completely the entry lists it.
  /// [LinuxMimeType.declared] supplies the mapping and the description;
  /// [LinuxMimeType.registered] names a type the system already maps, without
  /// replacing the description every file of that type shows;
  /// [LinuxMimeType.unmapped] records an extension left alone on purpose,
  /// with the reason.
  ///
  /// The host passes its own list, because which files an application opens
  /// is the application's fact, not this package's. It is the Linux half of
  /// the document types a macOS bundle registers, so the two describe the
  /// same extensions — or double-clicking works on one platform and not the
  /// other.
  ///
  /// The association reaches the file manager when `DesktopIntegrator`
  /// refreshes the caches: `update-mime-database` compiles the installed
  /// package, and `update-desktop-database` rebuilds `mimeinfo.cache` from
  /// the entries it finds.
  final List<LinuxMimeType> fileTypes;

  /// Every type the entry claims: [fileTypes] when the host has moved to it,
  /// and the superseded [mimeTypes] otherwise.
  List<String> get claimedTypeNames => fileTypes.isEmpty
      ? List<String>.unmodifiable(mimeTypes)
      : List<String>.unmodifiable(
          fileTypes.where((t) => t.isNamed).map((t) => t.name),
        );
}
