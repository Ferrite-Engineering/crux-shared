// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Tracks live child processes so a host can terminate them at shutdown.
///
/// ## Why this exists
///
/// A `cancelSignal` handles the cases the application knows about — a tab
/// closing, a superseding re-run. It does not handle the application simply
/// going away. On a hard quit, a crash, or a `SIGKILL` of the parent, any
/// child still running is re-parented and keeps consuming a core with nobody
/// left to reap it. Long-running EDA tools make that expensive and very
/// visible.
///
/// ## The seam
///
/// This package is pure Dart and deliberately knows nothing about Flutter,
/// so it cannot observe an application lifecycle itself. Instead it keeps the
/// registry and exposes [killAll]; the host drains it. In a Flutter app that
/// means a `WidgetsBindingObserver` calling [killAll] on
/// `AppLifecycleState.detached`:
///
/// ```dart
/// @override
/// void didChangeAppLifecycleState(AppLifecycleState state) {
///   if (state == AppLifecycleState.detached) {
///     ProcessRegistry.instance.killAll();
///   }
/// }
/// ```
///
/// `DefaultProcessRunner` registers and unregisters automatically, so a host
/// that wires up the drain gets coverage of every process this package
/// spawns without touching individual call sites.
class ProcessRegistry {
  /// Creates an empty registry. Most callers want [instance]; a fresh
  /// registry is useful in tests and when a host wants to scope termination
  /// to a subsystem rather than the whole process.
  ProcessRegistry();

  /// Process-wide registry that `DefaultProcessRunner` uses by default.
  static final ProcessRegistry instance = ProcessRegistry();

  final Set<Process> _live = <Process>{};

  /// Number of processes currently registered as running.
  int get liveCount => _live.length;

  /// Records [process] as live. Called by the runner immediately after a
  /// successful spawn.
  void register(Process process) => _live.add(process);

  /// Removes [process] from the registry. Called by the runner once the
  /// process has exited, however it exited.
  void unregister(Process process) => _live.remove(process);

  /// Sends `SIGKILL` to every registered process and clears the registry.
  ///
  /// Returns how many processes were signalled. `SIGKILL` rather than
  /// `SIGTERM` because this runs at shutdown, when there is no longer a
  /// meaningful opportunity for a child to clean up and no time budget to
  /// wait for it to try.
  ///
  /// Safe to call more than once and safe to call when empty.
  int killAll() {
    if (_live.isEmpty) return 0;
    final targets = List<Process>.of(_live);
    _live.clear();
    for (final process in targets) {
      // A process that already exited yields false rather than throwing;
      // either way there is nothing further to do for it.
      process.kill(ProcessSignal.sigkill);
    }
    return targets.length;
  }
}
