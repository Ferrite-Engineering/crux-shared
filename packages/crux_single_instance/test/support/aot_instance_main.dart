// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A stand-in application for the ahead-of-time tests, compiled with
// `dart compile exe`. Unlike instance_main.dart it never calls
// SingleInstancePrimary.close, as an application that leaves the claim to
// the process ending does, so the compiler sees no reader of the running
// instance's lock file. As the running instance it makes the garbage
// collector run, reports `ready`, then prints each link it is handed until it
// has the number expected or its time is up, and exits without closing.
//
//   aot_instance_main <dir> <unix|tcp> <expected links> <hold ms> [link]

import 'dart:async';
import 'dart:io';

import 'package:crux_single_instance/crux_single_instance.dart';

Future<void> main(List<String> args) async {
  final directory = args[0];
  final transport = args[1] == 'tcp'
      ? SingleInstanceTransport.loopbackTcp
      : SingleInstanceTransport.unixSocket;
  final expected = int.parse(args[2]);
  final hold = Duration(milliseconds: int.parse(args[3]));
  final link = args.length > 4 ? args[4] : null;

  final claim = await SingleInstance(
    appId: 'com.example.single_instance_test',
    policy: SingleInstanceLinkPolicy(schemes: const ['example']),
    directory: directory,
    transport: transport,
    timeout: const Duration(seconds: 10),
  ).claim(link: link);

  switch (claim) {
    case SingleInstanceDelivered():
      stdout.writeln('claim delivered');
      await stdout.flush();
      exit(0);
    case SingleInstanceStandalone(:final reason):
      stdout.writeln('claim standalone ${reason.name}');
      await stdout.flush();
      exit(0);
    case final SingleInstancePrimary primary:
      stdout.writeln('claim primary');
      var received = 0;
      final done = Completer<void>();
      primary.links.listen((value) {
        stdout.writeln('link $value');
        received++;
        if (received >= expected && !done.isCompleted) done.complete();
      });
      await _churn();
      stdout.writeln('ready');
      await done.future.timeout(hold, onTimeout: () {});
      await stdout.flush();
      exit(0);
  }
}

/// Allocates enough, across several event-loop turns, that the garbage
/// collector runs and finalizes whatever is unreachable, as a running
/// application's would within moments of startup.
Future<void> _churn() async {
  var junk = <List<int>>[];
  for (var i = 0; i < 400; i++) {
    junk.add(List<int>.filled(100000, i));
    if (junk.length > 20) junk = <List<int>>[];
    if (i % 50 == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
}
