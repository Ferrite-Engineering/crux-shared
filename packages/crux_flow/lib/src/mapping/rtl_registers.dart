// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/mapping/netlist_src_index.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/src_span.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:crux_netlist/crux_netlist.dart';
import 'package:meta/meta.dart';

/// One register the source design declares, as its elaboration records it.
@immutable
class RtlRegister {
  /// Creates a register.
  const RtlRegister({
    required this.name,
    this.declaration = const <SrcSpan>[],
    this.assignments = const <SrcSpan>[],
    this.blocks = const <SrcSpan>[],
  });

  /// The register's name: the instance path from the top, `.`-joined, then
  /// the declared name (`sum_q`, `u_div.cnt_q`).
  final String name;

  /// Where it is declared: the spans on the register's own net.
  final List<SrcSpan> declaration;

  /// The statements that compute its next value: the spans of the cells
  /// feeding its data input, through any multiplexers, up to the next
  /// register or input.
  final List<SrcSpan> assignments;

  /// The block that assigns it (an `always` or `process`): the spans on the
  /// storage cell the elaboration made for it.
  final List<SrcSpan> blocks;

  @override
  bool operator ==(Object other) =>
      other is RtlRegister &&
      other.name == name &&
      listEquals(other.declaration, declaration) &&
      listEquals(other.assignments, assignments) &&
      listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(
    name,
    Object.hashAll(declaration),
    Object.hashAll(assignments),
    Object.hashAll(blocks),
  );

  @override
  String toString() => 'RtlRegister($name)';
}

/// The registers of a source design, read from its elaboration: Yosys
/// `write_json` after `hierarchy` and `proc` and before any synthesis, which
/// is what NetCrux shows and what `YosysRunner` produces. A register is a
/// flip-flop or latch output with a public name, or a memory (a register
/// file is one register whatever its words and bits).
///
/// Mapping a synthesized cell back to source asks three questions of it,
/// and each is answered here: which register a cell's name descends from
/// ([registerForCellName]), which register a source span declares
/// ([declaredAt]) or assigns ([assignedAt]), and whether a span names one of
/// the design's own files at all ([sourceFileOf]).
@immutable
class RtlRegisterSet {
  const RtlRegisterSet._(this._byName, this.sourceFiles);

  /// Collects every register of [elaboration], walking the instance tree
  /// from [top] (the design's top module when null; see
  /// [NetlistSrcIndex.fromModel] for how one is chosen).
  ///
  /// The walk is bounded: [maxDepth] instance levels below the top and
  /// [maxInstances] module instances in all (over that is a
  /// [FlowReadException] of [FlowReadFailure.tooLarge]), so a hostile
  /// document cannot make it run away.
  /// A module that instantiates itself, directly or not, is not re-entered.
  factory RtlRegisterSet.fromModel(
    NetlistModel elaboration, {
    String? top,
    int maxDepth = 64,
    int maxInstances = 100000,
  }) {
    final root = chooseModule(elaboration, top);
    final byName = <String, RtlRegister>{};
    final files = <String>{};
    var instances = 0;

    void visit(Module module, String prefix, List<String> stack) {
      instances++;
      if (instances > maxInstances) {
        throw FlowReadException(
          FlowReadFailure.tooLarge,
          'the design instantiates more than $maxInstances modules',
        );
      }
      _collect(module, prefix, byName, files);
      if (stack.length > maxDepth) return;
      for (final MapEntry(key: name, value: cell) in module.cells.entries) {
        final child = elaboration.modules[cell.type];
        if (child == null || child.isBlackBox) continue;
        if (stack.contains(child.name)) continue;
        visit(child, '$prefix$name.', [...stack, child.name]);
      }
    }

    visit(root, '', [root.name]);
    return RtlRegisterSet._(Map.unmodifiable(byName), Set.unmodifiable(files));
  }

  /// Parses an elaboration within [limits]; see [RtlRegisterSet.fromModel].
  ///
  /// Throws [FlowReadException] for an input over a limit or not a design.
  factory RtlRegisterSet.parse(
    String text, {
    String? top,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) => RtlRegisterSet.fromModel(parseYosysDesign(text, limits), top: top);

  /// Reads the elaboration at [path] within [limits]; see
  /// [RtlRegisterSet.parse].
  static Future<RtlRegisterSet> read(
    String path, {
    String? top,
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) async => RtlRegisterSet.parse(
    await readFlowFile(path, limits),
    top: top,
    limits: limits,
  );

  final Map<String, RtlRegister> _byName;

  /// Every file the elaboration's own spans name: the design's sources, as
  /// Yosys recorded them.
  final Set<String> sourceFiles;

  /// The registers, by name.
  Iterable<RtlRegister> get registers => _byName.values;

  /// The register called [name], or null.
  RtlRegister? operator [](String name) => _byName[name];

  /// How many registers the design has.
  int get length => _byName.length;

  /// The register a synthesized cell's name descends from, or null.
  ///
  /// Synthesis names a flip-flop after the register it implements and then
  /// appends its own suffixes (`ra_SB_DFF_Q_2_DFFLC` from `ra`,
  /// `sum_q_TRELLIS_FF_Q_10` from `sum_q`). The longest register name that
  /// is the whole of [cellName], or a prefix of it ending at a `_`, `$`,
  /// `[` or `.`, is the answer, so `sum_q_...` is `sum_q` even when a
  /// register `sum` exists. A name with no such prefix (GateMate's
  /// `$auto$ff.cc:337:slice$139`) has none.
  RtlRegister? registerForCellName(String cellName) {
    for (var end = cellName.length; end > 0; end--) {
      if (end < cellName.length && !_stemBoundary(cellName.codeUnitAt(end))) {
        continue;
      }
      final hit = _byName[cellName.substring(0, end)];
      if (hit != null) return hit;
    }
    return null;
  }

  /// The design file a recorded span file names (by [matchSourceBySuffix]
  /// over [sourceFiles]), or null for a file that is not one of the
  /// design's: a Yosys techmap or simulation library, or a file of another
  /// design.
  String? sourceFileOf(String recordedFile) {
    if (isToolLibraryPath(recordedFile)) return null;
    return matchSourceBySuffix(recordedFile, sourceFiles);
  }

  /// The registers whose declaration is at [span].
  List<RtlRegister> declaredAt(SrcSpan span) =>
      _matching(span, (r) => r.declaration);

  /// The registers whose next value a statement at [span] computes.
  List<RtlRegister> assignedAt(SrcSpan span) =>
      _matching(span, (r) => r.assignments);

  /// The registers assigned in the block at [span].
  List<RtlRegister> assignedInBlock(SrcSpan span) =>
      _matching(span, (r) => r.blocks);

  List<RtlRegister> _matching(
    SrcSpan span,
    List<SrcSpan> Function(RtlRegister) spansOf,
  ) {
    final file = sourceFileOf(span.file);
    if (file == null) return const <RtlRegister>[];
    return [
      for (final r in _byName.values)
        if (spansOf(r).any((s) => s.file == file && sameSourceRange(s, span)))
          r,
    ];
  }
}

bool _stemBoundary(int c) =>
    c == 0x5F /* _ */ ||
    c == 0x24 /* $ */ ||
    c == 0x5B /* [ */ ||
    c == 0x2E /* . */;

/// Whether [a] and [b] cover the same lines, and the same columns wherever
/// both record them. Files are not compared.
bool sameSourceRange(SrcSpan a, SrcSpan b) {
  if (a.startLine != b.startLine) return false;
  if ((a.endLine ?? a.startLine) != (b.endLine ?? b.startLine)) return false;
  if (a.startCol != null && b.startCol != null && a.startCol != b.startCol) {
    return false;
  }
  if (a.endCol != null && b.endCol != null && a.endCol != b.endCol) {
    return false;
  }
  return true;
}

/// Whether [file] is one of Yosys's own techmap or simulation libraries
/// rather than a design source: under a `share/yosys` or `techlibs`
/// directory, or written with a scrubbed `<yosys-share>` prefix.
bool isToolLibraryPath(String file) {
  final segments = file.split(RegExp(r'[/\\]'));
  if (segments.isNotEmpty && segments.first == '<yosys-share>') return true;
  for (var i = 0; i < segments.length; i++) {
    if (segments[i] == 'techlibs') return true;
    if (segments[i] == 'share' &&
        i + 1 < segments.length &&
        segments[i + 1] == 'yosys') {
      return true;
    }
  }
  return false;
}

/// How far back from a register's data input the walk for its assigning
/// statements goes, in cells, and how many cells it reads at most.
const int _assignmentDepth = 16;
const int _assignmentCells = 256;

/// Adds [module]'s registers, named under [prefix], to [out], and the files
/// its spans name to [files].
void _collect(
  Module module,
  String prefix,
  Map<String, RtlRegister> out,
  Set<String> files,
) {
  void addFiles(String? src) {
    for (final span in SrcSpan.parseAll(src)) {
      if (!isToolLibraryPath(span.file)) files.add(span.file);
    }
  }

  addFiles(module.attributes['src']);
  final driverOf = <int, Cell>{};
  for (final cell in module.cells.values) {
    addFiles(cell.attributes['src']);
    for (final MapEntry(key: port, value: bits) in cell.connections.entries) {
      if (!_drives(cell, port)) continue;
      for (final bit in bits) {
        if (bit is NetBit) driverOf[bit.netId] = cell;
      }
    }
  }
  final publicNetsOf = <int, List<Net>>{};
  for (final net in module.nets.values) {
    addFiles(net.attributes['src']);
    if (net.hideName) continue;
    for (final bit in net.bits) {
      if (bit is NetBit) (publicNetsOf[bit.netId] ??= <Net>[]).add(net);
    }
  }

  for (final cell in module.cells.values) {
    if (!isStorageCell(cell)) continue;
    final named = <Net>{
      for (final bit in cell.connections['Q'] ?? const <BitRef>[])
        if (bit is NetBit) ...?publicNetsOf[bit.netId],
    };
    if (named.isEmpty) continue;
    final assignments = _assigningSpans(cell, driverOf, const ['D', 'AD']);
    final blocks = _userSpans(cell.attributes['src']);
    for (final net in named) {
      final name = '$prefix${_registerNameOf(net)}';
      out.putIfAbsent(
        name,
        () => RtlRegister(
          name: name,
          declaration: _userSpans(net.attributes['src']),
          assignments: assignments,
          blocks: blocks,
        ),
      );
    }
  }
  _collectMemories(module, prefix, driverOf, out);
}

/// Adds [module]'s memories to [out], named under [prefix]: a register file
/// is one register, whatever its words and bits.
///
/// A source elaboration (`hierarchy; proc`) holds each as an entry of the
/// `memories` section, accessed by `$memrd` and `$memwr` cells that name it
/// in `MEMID`; once the `memory` passes have run it is a `$mem` or `$mem_v2`
/// cell instead. Both forms are read. The declaration is the memory's own
/// span; its blocks are its write ports' spans, and its assignments what
/// computes the data they write.
void _collectMemories(
  Module module,
  String prefix,
  Map<int, Cell> driverOf,
  Map<String, RtlRegister> out,
) {
  final declared = <String, List<SrcSpan>>{};
  for (final memory in module.memories.values) {
    if (memory.hideName) continue;
    declared[memory.name] = _userSpans(memory.attributes['src']);
  }
  final blocks = <String, List<SrcSpan>>{};
  final assignments = <String, List<SrcSpan>>{};
  void addAll(Map<String, List<SrcSpan>> into, String id, List<SrcSpan> spans) {
    final list = into[id] ??= <SrcSpan>[];
    for (final span in spans) {
      if (!list.contains(span)) list.add(span);
    }
  }

  for (final cell in module.cells.values) {
    final dataPorts = _memoryDataPorts[cell.type];
    if (dataPorts == null) continue;
    final id = _memoryId(cell);
    if (id == null) continue;
    final own = _userSpans(cell.attributes['src']);
    final isMem = cell.type == r'$mem' || cell.type == r'$mem_v2';
    // A `$mem` carries the memory's own attributes; a write port only the
    // statement that wrote it.
    if (isMem) declared.putIfAbsent(id, () => own);
    if (isMem || dataPorts.isNotEmpty) addAll(blocks, id, own);
    if (dataPorts.isNotEmpty) {
      addAll(assignments, id, _assigningSpans(cell, driverOf, dataPorts));
    }
  }
  for (final id in declared.keys) {
    final name = '$prefix$id';
    out.putIfAbsent(
      name,
      () => RtlRegister(
        name: name,
        declaration: declared[id]!,
        assignments: assignments[id] ?? const <SrcSpan>[],
        blocks: blocks[id] ?? const <SrcSpan>[],
      ),
    );
  }
}

/// The memory cell types, and for each the data ports whose cone is what the
/// memory is assigned (none for a read port).
const Map<String, List<String>> _memoryDataPorts = {
  r'$mem': ['WR_DATA'],
  r'$mem_v2': ['WR_DATA'],
  r'$memwr': ['DATA'],
  r'$memwr_v2': ['DATA'],
  r'$memrd': <String>[],
  r'$memrd_v2': <String>[],
  r'$meminit': <String>[],
  r'$meminit_v2': <String>[],
};

/// The memory a memory cell names: its `MEMID` parameter, without the
/// leading `\` of a public name; null for a missing or auto-generated one.
String? _memoryId(Cell cell) {
  final raw = cell.parameters['MEMID'];
  if (raw == null || raw.isEmpty || raw.startsWith(r'$')) return null;
  return raw.startsWith(r'\') ? raw.substring(1) : raw;
}

String _registerNameOf(Net net) =>
    registerNameOfNet(net.name, bitCount: net.bits.length);

/// The register a storage cell's output net [name] of [bitCount] bits names:
/// the net's own name, or, for a one-bit net a synthesis tool split out of a
/// vector and named after one of its bits (`sum_q[23]`, as LibreLane's
/// synthesis writes them), the vector's name with the trailing bit selects
/// removed, so every bit of a register is one register. A host that keys its
/// own registers by name uses this to agree with [RtlRegisterSet].
String registerNameOfNet(String name, {required int bitCount}) {
  if (bitCount != 1) return name;
  var current = name;
  while (true) {
    final shorter = current.replaceFirst(_trailingBitSelect, '');
    if (shorter == current || shorter.isEmpty) return current;
    current = shorter;
  }
}

final RegExp _trailingBitSelect = RegExp(r'\[\d+\]$');

List<SrcSpan> _userSpans(String? src) => [
  for (final span in SrcSpan.parseAll(src))
    if (!isToolLibraryPath(span.file)) span,
];

/// Whether [port] of [cell] is an output: from the direction Yosys wrote,
/// or, when it wrote none, from the output names Yosys's own cells use.
bool _drives(Cell cell, String port) {
  final direction = cell.portDirections[port];
  if (direction != null) return direction == PortDirection.output;
  return const {'Y', 'Q', 'O', 'Z', 'CO', 'X'}.contains(port);
}

/// The spans of the cells that compute [storage]'s next value: a
/// breadth-first walk back from its data inputs through combinational
/// cells, stopping at other storage cells, design inputs and constants.
List<SrcSpan> _assigningSpans(
  Cell storage,
  Map<int, Cell> driverOf,
  List<String> dataPorts,
) {
  final frontier = <int>[
    for (final port in dataPorts)
      for (final bit in storage.connections[port] ?? const <BitRef>[])
        if (bit is NetBit) bit.netId,
  ];
  final seenBits = <int>{...frontier};
  // By identity: a cell's own equality compares every connection.
  final seenCells = Set<Cell>.identity();
  final spans = <SrcSpan>[];
  for (
    var depth = 0;
    depth < _assignmentDepth && frontier.isNotEmpty;
    depth++
  ) {
    final next = <int>[];
    for (final bit in frontier) {
      final cell = driverOf[bit];
      if (cell == null || identical(cell, storage) || isStorageCell(cell)) {
        continue;
      }
      if (!seenCells.add(cell)) continue;
      if (seenCells.length > _assignmentCells) return spans;
      for (final span in _userSpans(cell.attributes['src'])) {
        if (!spans.contains(span)) spans.add(span);
      }
      for (final MapEntry(key: port, value: bits) in cell.connections.entries) {
        if (_drives(cell, port)) continue;
        for (final b in bits) {
          if (b is NetBit && seenBits.add(b.netId)) next.add(b.netId);
        }
      }
    }
    frontier
      ..clear()
      ..addAll(next);
  }
  return spans;
}
