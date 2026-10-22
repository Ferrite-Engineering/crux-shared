// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/mapping/netlist_src_index.dart';
import 'package:crux_flow/src/mapping/rtl_register_resolver.dart';
import 'package:crux_flow/src/mapping/rtl_registers.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/rtl_mapping.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:crux_netlist/crux_netlist.dart';
import 'package:meta/meta.dart';

/// The synthesis sidecar of a LibreLane run
/// (`NN-yosys-synthesis/<design>.nl.v.json`, Yosys `write_json` of the
/// netlist the rest of the flow reads), indexed so the instance names the
/// timing reports use map back to the source design.
///
/// The reports name instances as `write_verilog` printed them: a cell Yosys
/// left anonymous (`$auto$...`) becomes `_NNN_`. This class rebuilds that
/// numbering the way `write_verilog` assigns it (anonymous wires first, then
/// anonymous cells, each list in name order, numbered after the highest
/// `_NNN_` name already present), so `_400_` in an OpenSTA listing finds its
/// sidecar cell. Place and route keeps synthesis instance names (the
/// resizer swaps the master, not the instance); cells it adds (buffers,
/// clock tree, fill) have no sidecar entry and map unmapped.
///
/// **What a mapping here claims.** On LibreLane runs the endpoint register
/// is found by the public net on its flip-flop's output (`Q`), because most
/// flip-flops carry no `src` of their own (553 of 1,597 on the PicoRV32
/// measurement). Measured at 98% of the worst 100 setup endpoints on a
/// 1,597 flip-flop sky130A design, which places ASIC mapping in the plan's
/// "nearest register" band: a register named here is the nearest register
/// the synthesized design records, not a proof of source.
@immutable
class LibreLaneNetlist {
  const LibreLaneNetlist._(this.index, this._aliases, this._outputNets);

  /// Indexes [module] of [design] (its top when null).
  factory LibreLaneNetlist.fromModel(NetlistModel design, {String? module}) {
    final chosen = chooseModule(design, module);
    final aliases = writeVerilogAutoNames(chosen);
    final labels = <int, List<String>>{};
    for (final net in chosen.nets.values) {
      if (net.hideName || net.name.startsWith(r'$')) continue;
      for (final (i, bit) in net.bits.indexed) {
        if (bit is! NetBit) continue;
        final label = net.bits.length == 1 ? net.name : '${net.name}[$i]';
        (labels[bit.netId] ??= <String>[]).add(label);
      }
    }
    final outputs = <String, List<String>>{};
    for (final MapEntry(key: name, value: cell) in chosen.cells.entries) {
      if (!isStorageCell(cell)) continue;
      final found = <String>{
        for (final port in const ['Q', 'Q_N', 'QN'])
          for (final bit in cell.connections[port] ?? const <BitRef>[])
            if (bit is NetBit) ...?labels[bit.netId],
      };
      if (found.isNotEmpty) {
        outputs[name] = List.unmodifiable(found.toList()..sort());
      }
    }
    return LibreLaneNetlist._(
      NetlistSrcIndex.fromModel(design, module: chosen.name),
      Map.unmodifiable(aliases),
      Map.unmodifiable(outputs),
    );
  }

  /// Parses a sidecar within [limits]; see [LibreLaneNetlist.fromModel].
  factory LibreLaneNetlist.parse(
    String text, {
    String? module,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) => LibreLaneNetlist.fromModel(
    parseYosysDesign(text, limits),
    module: module,
  );

  /// Reads the sidecar at [path] within [limits].
  static Future<LibreLaneNetlist> read(
    String path, {
    String? module,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) async => LibreLaneNetlist.parse(
    await readFlowFile(path, limits),
    module: module,
    limits: limits,
  );

  /// The sidecar's cells and nets with their source spans.
  final NetlistSrcIndex index;

  final Map<String, String> _aliases;
  final Map<String, List<String>> _outputNets;

  /// The sidecar's name for [instance], a name from a timing report or the
  /// final netlist: its `write_verilog` alias resolved, or [instance] as
  /// written (with a leading `\` escape dropped) when the sidecar has a
  /// cell of that name; null when it has none.
  String? sidecarName(String instance) {
    final alias = _aliases[instance];
    if (alias != null) return alias;
    if (index.containsCell(instance)) return instance;
    final unescaped = instance.startsWith(r'\')
        ? instance.substring(1)
        : instance;
    return index.containsCell(unescaped) ? unescaped : null;
  }

  /// Whether [instance] is a flip-flop or latch of the sidecar.
  bool isStorage(String instance) {
    final name = sidecarName(instance);
    return name != null && index.isStorage(name);
  }

  /// The public nets on [instance]'s output (`Q`, `Q_N`, `QN`), one label
  /// per bit (`sum_q[3]`), sorted; empty for a cell that is not storage or
  /// whose output carries no public name.
  List<String> outputNets(String instance) {
    final name = sidecarName(instance);
    return name == null ? const <String>[] : _outputNets[name] ?? const [];
  }

  /// Maps [path] (from an OpenSTA listing of this run) to [registers], the
  /// source elaboration's registers.
  ///
  /// Each end is mapped through its flip-flop's output net when it has one
  /// that names a register, else through the cell's own spans; a routing
  /// segment by its net, any other by the cell it reaches.
  TimingPathMapping resolvePath(TimingPath path, RtlRegisterSet registers) {
    final resolver = RtlRegisterResolver(registers, index: index);
    RtlMapping end(String instance) {
      final storage = isStorage(instance);
      return resolver.resolve(
        cell: sidecarName(instance),
        net: storage ? registerNet(outputNets(instance), registers) : null,
        storage: storage,
      );
    }

    final start = isStorage(path.startpoint)
        ? end(path.startpoint)
        : resolver.resolve(net: path.startpoint);
    final finish = isStorage(path.endpoint)
        ? end(path.endpoint)
        : resolver.resolve(net: path.endpoint);
    return TimingPathMapping(
      startpoint: start,
      endpoint: finish,
      segments: [
        for (final s in path.segments)
          switch (s.type) {
            TimingSegmentType.routing => resolver.resolve(net: s.net),
            TimingSegmentType.clkToQ when s.fromCell == path.startpoint =>
              start,
            TimingSegmentType.setup ||
            TimingSegmentType.hold when s.toCell == path.endpoint => finish,
            _ => resolver.resolve(cell: sidecarName(s.toCell)),
          },
      ],
    );
  }

  /// The first of [labels] that names a register of [registers] once
  /// trailing bit and word selects are removed (`cpuregs[21][19]` names
  /// `cpuregs`), as that register's own name; else the first label, or null
  /// when there is none.
  static String? registerNet(List<String> labels, RtlRegisterSet registers) {
    final select = RegExp(r'\[\d+\]$');
    for (final label in labels) {
      var candidate = label;
      while (true) {
        if (registers[candidate] != null) return candidate;
        final shorter = candidate.replaceFirst(select, '');
        if (shorter == candidate) break;
        candidate = shorter;
      }
    }
    return labels.isEmpty ? null : labels.first;
  }
}

/// `write_verilog`'s names for [module]'s anonymous wires and cells:
/// `_NNN_` to the `$`-prefixed name in the design.
///
/// Anonymous wires come first, then anonymous cells, each in name order;
/// numbering starts after the highest `_NNN_` name the module already has,
/// and every number is padded to the width of the largest.
Map<String, String> writeVerilogAutoNames(Module module) {
  final wires = module.nets.keys.toList()..sort();
  final cells = module.cells.keys.toList()..sort();
  final numbered = RegExp(r'^_(\d+)_?$');
  var offset = 0;
  for (final name in [...wires, ...cells]) {
    final m = numbered.firstMatch(name);
    if (m == null) continue;
    final next = int.parse(m.group(1)!) + 1;
    if (next > offset) offset = next;
  }
  final ids = [
    ...wires.where((n) => n.startsWith(r'$')),
    ...cells.where((n) => n.startsWith(r'$')),
  ];
  final total = offset + ids.length;
  var digits = 1;
  var bound = 10;
  while (bound < total) {
    digits++;
    bound *= 10;
  }
  return {
    for (var k = 0; k < ids.length; k++)
      '_${(offset + k).toString().padLeft(digits, '0')}_': ids[k],
  };
}
