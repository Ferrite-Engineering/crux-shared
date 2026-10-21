// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/src_span.dart';
import 'package:crux_netlist/crux_netlist.dart';
import 'package:meta/meta.dart';

/// The port names a storage element is clocked or enabled through, across
/// Yosys's internal cells and the vendor and standard-cell libraries the
/// flows use (`SB_DFF` `C`, `TRELLIS_FF` and the sky130, gf180 and IHP
/// flip-flops `CLK`, latches `EN`, `GATE` or `E`).
const Set<String> _clockLikePorts = {
  'C',
  'CLK',
  'CK',
  'CLK_N',
  'clk',
  'EN',
  'E',
  'G',
  'GATE',
  'GATE_N',
};

/// Whether [cell] holds state: a flip-flop or a latch.
///
/// Judged by its ports, not by a table of type names, so a library this
/// package has never seen is still read correctly: a storage element drives
/// a `Q` and is clocked or enabled through one of a small set of port names.
/// Yosys's own `$`-prefixed cells with a `Q` port (`$dff`, `$adff`, `$sdff`,
/// `$dlatch`, `$_DFF_P_` and the rest) are storage by construction.
bool isStorageCell(Cell cell) {
  final ports = cell.connections.keys.toSet()..addAll(cell.portDirections.keys);
  if (!ports.contains('Q')) return false;
  if (cell.type.startsWith(r'$')) return true;
  return ports.any(_clockLikePorts.contains);
}

/// One module of a synthesized design, indexed for mapping a tool's cell and
/// net names back to the source spans Yosys recorded on them.
///
/// Built over the design a place-and-route or signoff tool read: nextpnr's
/// `--write` output, or a flow's post-synthesis JSON. Those designs are
/// flat, so one module is indexed: the top, or the one named.
@immutable
class NetlistSrcIndex {
  const NetlistSrcIndex._(this.moduleName, this._cells, this._nets);

  /// Indexes [module] of [design], or its top module when [module] is null.
  ///
  /// With no top marked, a design holding exactly one module that is not a
  /// black box indexes that one. Throws [FlowReadException] when the module
  /// named is absent or no module can be chosen.
  factory NetlistSrcIndex.fromModel(NetlistModel design, {String? module}) {
    final chosen = chooseModule(design, module);
    return NetlistSrcIndex._(
      chosen.name,
      {
        for (final MapEntry(:key, value: cell) in chosen.cells.entries)
          key: (
            type: cell.type,
            spans: SrcSpan.parseAll(cell.attributes['src']),
            storage: isStorageCell(cell),
          ),
      },
      {
        for (final MapEntry(:key, value: net) in chosen.nets.entries)
          key: SrcSpan.parseAll(net.attributes['src']),
      },
    );
  }

  /// Parses a Yosys `write_json` document within [limits] and indexes it as
  /// [NetlistSrcIndex.fromModel] does.
  ///
  /// Throws [FlowReadException] for an input over a limit, one that is not
  /// JSON, or one that is not a Yosys design.
  factory NetlistSrcIndex.parse(
    String text, {
    String? module,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) => NetlistSrcIndex.fromModel(
    parseYosysDesign(text, limits),
    module: module,
  );

  /// Reads the design at [path] within [limits]; see
  /// [NetlistSrcIndex.parse]. A missing or unreadable file throws the
  /// `FileSystemException` [readFlowFile] does.
  static Future<NetlistSrcIndex> read(
    String path, {
    String? module,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) async => NetlistSrcIndex.parse(
    await readFlowFile(path, limits),
    module: module,
    limits: limits,
  );

  /// The module indexed.
  final String moduleName;

  final Map<String, ({String type, List<SrcSpan> spans, bool storage})> _cells;
  final Map<String, List<SrcSpan>> _nets;

  /// The source spans on cell [name], declaration first; empty for a cell
  /// with none or a name not in the design.
  List<SrcSpan> spansOfCell(String name) =>
      _cells[name]?.spans ?? const <SrcSpan>[];

  /// The source spans on net [name]; empty for a net with none or a name not
  /// in the design.
  List<SrcSpan> spansOfNet(String name) => _nets[name] ?? const <SrcSpan>[];

  /// The type of cell [name], or null when the design has no such cell.
  String? typeOfCell(String name) => _cells[name]?.type;

  /// Whether cell [name] is a flip-flop or latch ([isStorageCell]); false
  /// for a name not in the design.
  bool isStorage(String name) => _cells[name]?.storage ?? false;

  /// Whether the design has a cell called [name].
  bool containsCell(String name) => _cells.containsKey(name);

  /// The cell names, in the design's own order.
  Iterable<String> get cellNames => _cells.keys;

  /// How many cells the module holds.
  int get cellCount => _cells.length;

  /// How many named nets the module holds.
  int get netCount => _nets.length;
}

/// Decodes [text] as a Yosys `write_json` document within [limits].
///
/// Throws [FlowReadException] for anything over a limit or not a design.
NetlistModel parseYosysDesign(String text, FlowInputLimits limits) {
  final decoded = decodeFlowJson(text, limits);
  if (decoded is! Map<String, Object?>) {
    throw const FlowReadException(
      FlowReadFailure.malformed,
      'the design is not a JSON object',
    );
  }
  try {
    return NetlistModel.fromJson(decoded);
  } on FormatException catch (e) {
    throw FlowReadException(
      FlowReadFailure.malformed,
      'the design is not a Yosys document: ${e.message}',
    );
  }
}

/// The module [name] of [design], or, when [name] is null, its top module,
/// else its only module that is not a black box.
///
/// Throws [FlowReadException] when there is no such module.
Module chooseModule(NetlistModel design, String? name) {
  if (name != null) {
    final named = design.modules[name];
    if (named == null) {
      throw FlowReadException(
        FlowReadFailure.malformed,
        'the design has no module ${describeFlowValue(name)}',
      );
    }
    return named;
  }
  final top = design.topModule;
  if (top != null) return top;
  final user = [
    for (final m in design.modules.values)
      if (!m.isBlackBox) m,
  ];
  if (user.length == 1) return user.single;
  throw FlowReadException(
    FlowReadFailure.malformed,
    'the design marks no top module and has ${user.length} candidates',
  );
}
