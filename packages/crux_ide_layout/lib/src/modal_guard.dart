// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// Process-global re-entrancy guard for exclusive modal surfaces — dialogs,
/// side drawers, popovers, and full-screen overlays.
///
/// ## Why this exists
///
/// Modal surfaces are opened from a keyboard shortcut, a menu item, a toolbar
/// button, or a panel button — and a single user gesture can fire the opener
/// more than once before the surface appears:
///
/// - An app's global `Shortcuts`/`Actions` machinery sits *above* the
///   `Navigator`. When a dialog is already open, keyboard focus moves into it,
///   but the global shortcut layer still sees the key event and re-dispatches
///   the same action — so tapping the chord twice stacks two copies of the
///   surface.
/// - OS key-repeat (holding the chord) fires the action many times.
/// - A fast double-tap on a menu item or button does the same.
///
/// Wrapping each opener in [run] makes it idempotent for the lifetime of the
/// surface: the first call opens it; every re-entrant call with the same
/// key while it is open is ignored; once the open future completes (the surface
/// closed) the key is released and it can be opened again.
///
/// ## Usage
///
/// The wrapped callback MUST return a future that completes when the surface
/// closes — `showDialog`, `showModalBottomSheet`, and `Overlay`-based drawers
/// with a completion future all qualify:
///
/// ```dart
/// // At a dispatch site:
/// unawaited(
///   ModalGuard.run('tabDiag', () => TabDiagnosticsDrawer.open(context)),
/// );
///
/// // Or inside a static opener so every caller is covered:
/// static Future<void> show(BuildContext context) =>
///     ModalGuard.run('signalSearch', () => showDialog<void>(...));
/// ```
abstract final class ModalGuard {
  static final Set<String> _open = <String>{};

  /// Runs [open] only when no surface with [key] is currently open.
  ///
  /// [open] must return a future that completes when the surface closes.
  /// Re-entrant calls with the same [key] while it is open are no-ops and
  /// complete immediately. The key is released in a `finally`, so a throwing
  /// or cancelled open still frees the guard.
  ///
  /// Returns the open future on the first call, or an already-completed future
  /// for a suppressed re-entrant call.
  static Future<void> run(String key, Future<void> Function() open) async {
    if (!_open.add(key)) return; // already open — suppress the duplicate
    try {
      await open();
    } finally {
      _open.remove(key);
    }
  }

  /// Whether a surface registered under [key] is currently open.
  ///
  /// Exposed for tests and for callers that need to reflect open state in the
  /// UI; prefer [run] for the open path.
  static bool isOpen(String key) => _open.contains(key);

  /// Clears all open-state. Test-only: the guard is process-global, so a
  /// widget test that pumps a guarded surface open and tears down without
  /// dismissing it would leak the key into the next test and suppress its
  /// open. Call this from `flutter_test_config.dart` before every test.
  @visibleForTesting
  static void reset() => _open.clear();
}
