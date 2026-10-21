// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';

/// Which implementation flow produced a run.
enum FlowKind {
  /// A LibreLane ASIC run directory (`runs/<tag>/`).
  librelane('librelane'),

  /// An FPGA place-and-route run through nextpnr.
  nextpnr('nextpnr');

  const FlowKind(this.wireName);

  /// The stable token written to JSON and used as a driver id.
  final String wireName;

  /// The kind named by [wireName].
  static FlowKind fromWireName(String wireName) {
    for (final kind in values) {
      if (kind.wireName == wireName) return kind;
    }
    throw FlowReadException(
      FlowReadFailure.malformed,
      'unknown flow kind ${describeFlowValue(wireName)}',
    );
  }
}
