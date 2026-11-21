// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

/// How long the orderly quit a termination signal starts may take before the
/// process ends anyway.
///
/// Longer than the longest work any exit listener in the suite does (a
/// running regression's drain allows itself eight seconds), and well inside
/// the time a session manager waits after SIGTERM before it sends SIGKILL.
const Duration kTerminationSignalQuitDeadline = Duration(seconds: 10);

/// The signals that end a desktop app from outside: SIGTERM (a session
/// logout, `kill`, a service manager) and SIGHUP (the terminal the app was
/// started from was closed).
const List<ProcessSignal> kTerminationSignals = <ProcessSignal>[
  ProcessSignal.sigterm,
  ProcessSignal.sighup,
];

/// Whether this host can watch [kTerminationSignals]: Linux and macOS.
/// Windows supports neither signal; a Windows logoff reaches a window as
/// `WM_QUERYENDSESSION` and `WM_ENDSESSION` instead.
bool get terminationSignalsWatchable => Platform.isLinux || Platform.isMacOS;

/// Turns the first termination signal into one orderly quit, then makes
/// sure the process ends.
///
/// Without a watcher, SIGTERM and SIGHUP end the process with the default
/// action and no Dart runs, so nothing an orderly quit does (removing the
/// session marker, removing the cross-probe peer file, flushing pending
/// state) happens. Watching them replaces the default action, so this class
/// must always end the process itself:
///
/// - The first signal calls [requestExit], which asks the app to quit the
///   way a window close does. If the app agrees (`true`), the embedder ends
///   the process. If a listener declines (`false`), every listener has still
///   run, and the process ends at once: a signal is not a question.
/// - If [requestExit] throws (another quit is already in flight, say) or
///   never answers, the process ends when [deadline] passes.
/// - A second signal while the quit is under way starts nothing new: the
///   quit already started, and [deadline] bounds it.
///
/// The process ends through [exitProcess] with code 0.
class TerminationSignalQuit {
  /// A quit that calls [requestExit] on the first signal.
  TerminationSignalQuit({
    required this.requestExit,
    void Function(int code)? exitProcess,
    this.deadline = kTerminationSignalQuitDeadline,
  }) : exitProcess = exitProcess ?? exit;

  /// Asks the app to quit; completes with whether it agreed.
  final Future<bool> Function() requestExit;

  /// Ends the process. `dart:io`'s `exit` in production.
  final void Function(int code) exitProcess;

  /// How long the quit may take before the process ends anyway.
  final Duration deadline;

  bool _quitting = false;
  bool _ended = false;
  Timer? _deadline;

  /// Whether a signal has started the quit.
  bool get quitting => _quitting;

  /// Watches [signals] and quits on the first one. Returns the
  /// subscriptions; cancelling them restores the default actions.
  List<StreamSubscription<ProcessSignal>> watch([
    Iterable<ProcessSignal> signals = kTerminationSignals,
  ]) => [for (final signal in signals) signal.watch().listen(onSignal)];

  /// Handles one received [signal].
  void onSignal(ProcessSignal signal) {
    if (_quitting) return;
    _quitting = true;
    _deadline = Timer(deadline, _end);
    unawaited(_ask());
  }

  Future<void> _ask() async {
    final bool agreed;
    try {
      agreed = await requestExit();
    } on Object {
      // Left to the deadline: the failure may be a quit already under way,
      // whose listeners should be given their time.
      return;
    }
    if (!agreed) _end();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _deadline?.cancel();
    exitProcess(0);
  }
}
