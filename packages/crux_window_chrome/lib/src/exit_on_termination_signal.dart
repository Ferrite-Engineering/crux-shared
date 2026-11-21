// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show ProcessSignal;
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:crux_window_chrome/src/termination_signal_quit.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

TerminationSignalQuit? _installed;

/// Makes SIGTERM and SIGHUP the same exit request a window close is, then
/// ends the process.
///
/// A Linux session logout ends running apps with SIGTERM, and closing the
/// terminal an app was started from sends SIGHUP. By default either ends the
/// process with no Dart running, so the exit listeners a window close reaches
/// never run: the unclean-shutdown session marker, the cross-probe peer file
/// (which holds a port and an auth token) and any pending save stayed behind
/// until the next launch. This watches both signals and, on the first,
/// asks the engine for a cancelable exit through
/// [ServicesBinding.exitApplication], the request a window close sends, so
/// every `AppLifecycleListener.onExitRequested` runs. The process then ends
/// even if a listener declines, and at most [kTerminationSignalQuitDeadline]
/// after the signal however the request goes. A second signal starts nothing
/// new. See [TerminationSignalQuit].
///
/// Linux and macOS only: Windows has neither signal, and this returns false
/// there without watching anything. Idempotent; returns whether the signals
/// are watched. `initWindowChrome` calls it on Linux; a macOS host calls it
/// from its own startup.
bool routeTerminationSignalsThroughExitRequest() {
  if (!terminationSignalsWatchable) return false;
  return installTerminationSignalQuit(requestExit: _requestEngineExit) != null;
}

/// Installs the process-wide [TerminationSignalQuit] once, watching
/// [signals]. Returns the installed quit, or the one already installed.
///
/// The seam behind [routeTerminationSignalsThroughExitRequest]; tests pass
/// their own [requestExit], [exitProcess] and [signals], and call
/// [debugResetTerminationSignalQuit] in tear-down.
@visibleForTesting
TerminationSignalQuit? installTerminationSignalQuit({
  required Future<bool> Function() requestExit,
  void Function(int code)? exitProcess,
  Duration deadline = kTerminationSignalQuitDeadline,
  Iterable<ProcessSignal> signals = kTerminationSignals,
}) {
  final existing = _installed;
  if (existing != null) return existing;
  final quit = TerminationSignalQuit(
    requestExit: requestExit,
    exitProcess: exitProcess,
    deadline: deadline,
  );
  try {
    _subscriptions = quit.watch(signals);
  } on Object {
    // Watching is unsupported here: the default actions stay.
    return null;
  }
  return _installed = quit;
}

List<StreamSubscription<ProcessSignal>> _subscriptions =
    const <StreamSubscription<ProcessSignal>>[];

/// Stops watching and forgets the installed quit, restoring the default
/// signal actions. Tests only.
@visibleForTesting
Future<void> debugResetTerminationSignalQuit() async {
  final subscriptions = _subscriptions;
  _subscriptions = const <StreamSubscription<ProcessSignal>>[];
  _installed = null;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
}

/// The exit request a window close sends: cancelable, answered by every
/// `AppLifecycleListener`. True when the app agreed to exit.
@visibleForTesting
Future<bool> requestEngineExitForTerminationSignal() => _requestEngineExit();

Future<bool> _requestEngineExit() async =>
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable) ==
    AppExitResponse.exit;
