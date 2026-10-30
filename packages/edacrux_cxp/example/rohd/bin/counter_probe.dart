// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:edacrux_cxp/edacrux_cxp.dart';
import 'package:rohd/rohd.dart';

/// A 4-bit counter that raises `overflow` while it holds its maximum, 15.
class Counter extends Module {
  Counter(Logic clk, Logic reset) : super(name: 'counter') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);
    final count = addOutput('count', width: 4);
    final overflow = addOutput('overflow');

    Sequential(clk, [
      If(
        reset,
        then: [count < 0],
        orElse: [count < count + 1],
      ),
    ]);
    Combinational([overflow < count.eq(Const(15, width: 4))]);
  }

  Logic get count => output('count');
  Logic get overflow => output('overflow');
}

/// Simulates the counter. The first time `overflow` rises, this program asks
/// WaveCrux to show the `count` signal at that simulation time and NetCrux to
/// highlight the net that raised the flag.
///
/// Pass `--peers <directory>` to probe a private set of peers; by default it
/// probes the apps running for the current user.
Future<void> main(List<String> args) async {
  final peersFlag = args.indexOf('--peers');
  final probe = await CxpProbe.start(
    name: 'rohd-counter',
    manifestDirectory: peersFlag >= 0 ? args[peersFlag + 1] : null,
  );

  final clk = SimpleClockGenerator(10).clk;
  final reset = Logic();
  final counter = Counter(clk, reset);
  await counter.build();

  // The probes run when the condition is first seen. Sending is
  // asynchronous and the simulator is not, so start the sends from the
  // simulation and collect them after it ends.
  final sent = <Future<List<CxpProbeReply>>>[];
  var probed = false;
  counter.overflow.posedge.listen((_) {
    if (probed) return;
    probed = true;
    final time = Simulator.time;
    stdout.writeln('overflow at t=$time');
    // ROHD simulation time is in the units of the clock period above; this
    // example treats one unit as one picosecond.
    sent
      ..add(
        probe.showSignal(
          '${counter.name}.count',
          timePs: time,
          product: 'wavecrux',
        ),
      )
      ..add(
        probe.highlightNet(
          '${counter.name}.overflow',
          product: 'netcrux',
        ),
      );
  });

  // Give the probe a moment to connect to the running apps before the
  // simulation starts; a probe that finds nobody sends to nobody.
  try {
    await probe.waitForPeer(timeout: const Duration(seconds: 3));
  } on Object {
    stdout.writeln('No EDACrux app is running; simulating without them.');
  }

  Simulator.registerAction(1, () => reset.put(1));
  Simulator.registerAction(22, () => reset.put(0));
  Simulator.setMaxSimTime(500);
  await Simulator.run();

  for (final replies in await Future.wait(sent)) {
    for (final reply in replies) {
      stdout.writeln(
        '${reply.peer.productName}: ${reply.outcome.name}'
        '${reply.reason == null ? '' : ' (${reply.reason})'}',
      );
    }
  }
  await probe.close();
}
