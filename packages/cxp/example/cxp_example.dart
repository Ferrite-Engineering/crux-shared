// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// An example reports to the console; that is its output.
// ignore_for_file: avoid_print

import 'package:cxp/cxp.dart';

/// Cross-probes the EDACrux apps that are running on this machine.
///
/// Start WaveCrux and NetCrux with CXP switched on, open the same design in
/// both, then run `dart run example/cxp_example.dart`.
Future<void> main() async {
  final probe = await CxpProbe.start(name: 'my-tool', version: '1.0.0');

  // What the apps select, as the user clicks.
  probe.events.listen((event) {
    if (event is CxpSelectionReceived) {
      print('${event.peer.productName} selected ${event.elements}');
    }
  });

  try {
    // Wait for the first app to answer, then show a signal in every app
    // that can show one.
    await probe.waitForPeer();
    final replies = await probe.showSignal('top.cpu.alu.result', timePs: 41250);
    for (final reply in replies) {
      print('${reply.peer.productName}: ${reply.outcome.name} ${reply.reason}');
    }

    // Highlight a net in NetCrux only, and open a source line anywhere.
    await probe.highlightNet('top.cpu.alu.carry', product: 'netcrux');
    await probe.openSource('/work/rtl/alu.sv', 214, column: 9);
  } on Object catch (error) {
    print('No EDACrux app answered: $error');
  } finally {
    await probe.close();
  }
}
