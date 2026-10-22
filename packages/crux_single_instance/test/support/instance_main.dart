// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A stand-in application for the multi-process tests: claims, reports the
// outcome on stdout, and, as the running instance, prints each link it is
// handed until it has the number expected or its time is up.
//
//   instance_main <dir> <unix|tcp> <expected links> <hold ms> [link]

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
      final subscription = primary.links.listen((value) {
        stdout.writeln('link $value');
        received++;
        if (received >= expected && !done.isCompleted) done.complete();
      });
      if (expected == 0) done.complete();
      await done.future.timeout(hold, onTimeout: () {});
      await subscription.cancel();
      await primary.close();
      stdout.writeln('closed');
      await stdout.flush();
      exit(0);
  }
}
