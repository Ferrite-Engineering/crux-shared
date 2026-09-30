// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The suite's shared elaborated-netlist model.
///
/// A pure, immutable mirror of Yosys's `write_json` schema — modules, cells,
/// nets, ports, bit references and the hierarchy — plus the parser that builds
/// it. Zero Flutter imports, so it is usable from a headless engine.
///
/// **Why this is shared rather than NetCrux's.** It was NetCrux's, because
/// NetCrux was the only product that elaborated RTL. It stopped being only
/// NetCrux's when LintCrux's CDC engine needed the same graph: CDC is domain
/// analysis over exactly the structure a schematic is drawn from. Two copies of
/// a netlist model would have diverged on the first Yosys schema change, and
/// the two products would then have disagreed about what a design *is* — which
/// is the one thing cross-probing between them depends on.
///
/// The model deliberately stays a thin mirror of the wire format. Derived views
/// — schematic layout, domain partitions, cones — belong to the consumer that
/// needs them, not here.
library;

export 'src/bit_ref.dart';
export 'src/cell.dart';
export 'src/hierarchy_node.dart';
export 'src/module.dart';
export 'src/net.dart';
export 'src/netlist_model.dart';
export 'src/port.dart';
export 'src/port_direction.dart';
export 'src/yosys_json_parser.dart';
