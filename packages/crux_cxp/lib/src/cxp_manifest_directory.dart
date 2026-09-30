// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/cxp_host.dart';
import 'package:path/path.dart' as p;

/// Resolves the suite-shared CXP manifest directory for this user.
///
/// Discovery only works if every Crux product publishes into (and scans)
/// the **same** directory. The pre-fix convention —
/// `getApplicationSupportDirectory()/crux/cxp/peers` resolved per app via
/// `path_provider` — silently violated that: application-support is
/// **bundle-/app-id-scoped on every desktop platform** (macOS
/// `~/Library/Application Support/<bundle-id>`, Linux
/// `~/.local/share/<app>`, Windows `%APPDATA%\<org>\<app>`), so each
/// product wrote its manifest into a private container no peer ever
/// scanned, and cross-product discovery ("No CXP peers connected") was
/// structurally impossible — including between a dev build and an
/// installed build of the *same* product, whose bundle ids differ.
///
/// This resolver is the single source of truth for the shared location.
/// It deliberately avoids `path_provider` (crux_cxp is a pure Dart
/// package) and derives the per-user base directory from the environment:
///
/// - **macOS**: `$HOME/Library/Application Support/crux/cxp/peers`
/// - **Windows**: `%APPDATA%\crux\cxp\peers`
/// - **Linux / other POSIX**: `${XDG_DATA_HOME:-$HOME/.local/share}/crux/cxp/peers`
///
/// The trailing `crux/cxp/peers` segment is fixed across the suite: peer
/// discovery only works if every product agrees on one directory, so this is
/// a wire-level constant, not a preference. The base must be the *user's*
/// application-data root rather than an app-private container for the same
/// reason. All suite apps run unsandboxed, so every product can read and
/// write it.
///
/// [environment] and [operatingSystem] are injectable for tests; they
/// default to the live process environment and operating system.
///
/// ### When there is no directory: [StateError]
///
/// Throws [StateError] — never anything else — when the directory cannot be
/// resolved. Callers treat that as "discovery unavailable", not a crash. It
/// happens in two cases:
///
/// - **A required variable is missing** — `$HOME`, or `%APPDATA%` on Windows
///   (a misconfigured headless CI runner).
/// - **The host has no process environment or operating system to ask** — a
///   web build in a browser. CXP discovery is a same-machine filesystem
///   mechanism, so a browser cannot publish into or scan the shared directory
///   at all, and gets the same "discovery unavailable" signal rather than an
///   `UnsupportedError` from `dart:io`. Supplying both [environment] and
///   [operatingSystem] makes resolution pure path arithmetic, which works on
///   any host.
String sharedCxpManifestDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? cxpHostEnvironment();
  final os = operatingSystem ?? cxpHostOperatingSystem();
  if (env == null || os == null) {
    throw StateError(
      'sharedCxpManifestDirectory: this platform has no process environment '
      'or operating system to resolve the shared CXP manifest directory from; '
      'CXP discovery is unavailable here',
    );
  }

  String requireEnv(String name) {
    final value = env[name];
    if (value == null || value.isEmpty) {
      throw StateError(
        'sharedCxpManifestDirectory: \$$name is not set; cannot resolve '
        'the shared CXP manifest directory',
      );
    }
    return value;
  }

  final String base;
  switch (os) {
    case 'macos':
      base = p.join(requireEnv('HOME'), 'Library', 'Application Support');
    case 'windows':
      base = requireEnv('APPDATA');
    default:
      // Linux and other POSIX: honor XDG, fall back to ~/.local/share.
      final xdg = env['XDG_DATA_HOME'];
      base = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : p.join(requireEnv('HOME'), '.local', 'share');
  }
  return p.join(base, 'crux', 'cxp', 'peers');
}
