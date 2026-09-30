// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// AppImage first-run desktop self-integration for the EDACrux suite.
///
/// Each suite app's AppImage recipe (`scripts/package_appimage.sh`) installs a
/// `.desktop` file and hicolor icons keyed on the application id — but only
/// *inside* the AppDir. Nothing lands on the host, so the Wayland compositor
/// has no host-side `.desktop` whose `StartupWMClass` matches the running
/// window's `app_id` (set by the GTK runner to that same application id), and
/// GNOME/Ubuntu shows a generic dock icon. Native/deb installs don't have this
/// problem; AppImages do.
///
/// The fix is the standard AppImage self-integration pattern: on launch, when
/// running from an AppImage, the app writes its own `.desktop` + icons into
/// `~/.local/share` (XDG user data), idempotently. [maybeIntegrateDesktopEntry]
/// is the one call an app makes; [DesktopIntegrator] is the injectable,
/// unit-testable core behind it.
///
/// `dart:io` only — no Flutter. Apps call [maybeIntegrateDesktopEntry] early in
/// `bootstrap()`, before `runApp`; it no-ops off Linux and off AppImage.
library;

import 'dart:io';

import 'package:crux_linux_integration/src/desktop_integrator.dart';
import 'package:crux_linux_integration/src/linux_desktop_app.dart';

export 'src/desktop_entry.dart';
export 'src/desktop_integrator.dart';
export 'src/linux_desktop_app.dart';
export 'src/linux_mime_type.dart';
export 'src/mime_coverage.dart';
export 'src/mime_package.dart';

/// Integrates [app]'s host desktop entry when appropriate, swallowing every
/// error — desktop integration must never crash app startup.
///
/// No-ops immediately unless running on Linux. Otherwise it constructs a
/// [DesktopIntegrator] from the real [Platform.environment] and `$HOME` and
/// calls [DesktopIntegrator.integrate], which itself is a no-op unless the
/// process is running from an AppImage (`APPIMAGE` set) and the host entry is
/// missing or stale. Fast and side-effect-free on dev machines and native
/// installs, so it is safe to `await` on the startup path.
Future<void> maybeIntegrateDesktopEntry(LinuxDesktopApp app) async {
  try {
    // `Platform.isLinux` MUST be inside the try: on web, `dart:io`'s Platform
    // is unavailable and throws (UnsupportedError). Evaluated outside the
    // guard, that throw escapes and — awaited on the startup path before
    // runApp — hangs a web app's bootstrap on its loading spinner. Inside the
    // try it is swallowed like any other failure, so a web-capable app may call
    // this unconditionally.
    if (!Platform.isLinux) return;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    await DesktopIntegrator(
      homeDir: home,
      env: Platform.environment,
    ).integrate(app);
  } on Object {
    // Never let desktop integration abort startup.
  }
}
