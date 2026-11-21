// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A plain Dart process for termination_signal_quit_test.dart: it watches
// SIGTERM and SIGHUP with [TerminationSignalQuit] and stands in for the app
// with a marker file and an exit request that either declines after removing
// the marker (`decline`) or never answers (`hang`).
//
// Usage: termination_signal_child.dart <marker path> <decline|hang>

import 'dart:async';
import 'dart:io';

import 'package:crux_window_chrome/src/termination_signal_quit.dart';

void main(List<String> args) {
  final marker = File(args[0])..writeAsStringSync('running');
  final hang = args[1] == 'hang';
  TerminationSignalQuit(
    requestExit: () {
      stdout.writeln('request');
      if (hang) return Completer<bool>().future;
      marker.deleteSync();
      return Future<bool>.value(false);
    },
    deadline: const Duration(milliseconds: 500),
  ).watch();
  stdout.writeln('ready');
  // Never reached when the quit works: a distinct code says it did not.
  Timer(const Duration(seconds: 30), () => exit(3));
}
