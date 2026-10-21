// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/mapping/netlist_src_index.dart';
import 'package:crux_flow/src/mapping/rtl_registers.dart';
import 'package:crux_flow/src/rtl_mapping.dart';
import 'package:crux_flow/src/src_span.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:crux_flow/src/value_equality.dart';
import 'package:meta/meta.dart';

/// Where each part of a timing path lands in the source design.
@immutable
class TimingPathMapping {
  /// Creates a path mapping.
  const TimingPathMapping({
    required this.startpoint,
    required this.endpoint,
    required this.segments,
  });

  /// The mapping of the cell the path starts at.
  final RtlMapping startpoint;

  /// The mapping of the cell the path ends at.
  final RtlMapping endpoint;

  /// One mapping per segment of the path, in path order.
  final List<RtlMapping> segments;

  /// The index of the mapped segment nearest to segment [index], searching
  /// both ways and preferring the earlier on a tie; null when no segment
  /// maps. An unmapped segment is shown beside its nearest mapped
  /// neighbour.
  int? nearestMapped(int index) {
    for (var d = 0; d < segments.length; d++) {
      for (final i in [index - d, index + d]) {
        if (i < 0 || i >= segments.length) continue;
        if (segments[i].fidelity != MappingFidelity.unmapped) return i;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimingPathMapping &&
      other.startpoint == startpoint &&
      other.endpoint == endpoint &&
      listEquals(other.segments, segments);

  @override
  int get hashCode =>
      Object.hash(startpoint, endpoint, Object.hashAll(segments));
}

/// Maps the cells and nets a place-and-route or timing tool names back to
/// the source design, at the four fidelity levels of [MappingFidelity].
///
/// In order of preference:
///
/// 1. **register**: a flip-flop whose name descends from a source register
///    (`ra_SB_DFF_Q_2_DFFLC` is `ra`), a net that is a register's own output
///    (`src_a[7]`), or a span that is exactly one register's declaration.
/// 2. **statement**: a span on one line of a design file. When that line
///    computes exactly one register's next value, the register is named too.
/// 3. **span**: only spans of several lines (an `always` or `process`
///    block).
/// 4. **unmapped**: nothing but tool-library spans (techmap files), or no
///    span at all.
///
/// Registers come from the source elaboration ([registers]), so a register
/// named here is one a schematic of the same sources can highlight. Spans
/// come from what the tool reported and, when an [index] of the
/// synthesized design is given, from the cell and net attributes there.
/// Line-exact is never claimed: a span is where Yosys says a cell came
/// from, which is evidence, not proof.
@immutable
class RtlRegisterResolver {
  /// Creates a resolver over [registers] and, optionally, the synthesized
  /// design's [index].
  const RtlRegisterResolver(this.registers, {this.index});

  /// The source design's registers.
  final RtlRegisterSet registers;

  /// The synthesized design the tool read, when available.
  final NetlistSrcIndex? index;

  /// Maps one item: a [cell], a [net], or both, with any [sources] the tool
  /// reported for it (Yosys span strings, `|`-joined lists accepted).
  ///
  /// [storage] says whether [cell] is a flip-flop or latch; when null the
  /// [index] decides, and without one the cell is not treated as storage.
  RtlMapping resolve({
    String? cell,
    String? net,
    Iterable<String> sources = const <String>[],
    bool? storage,
  }) {
    final spans = <SrcSpan>[
      for (final s in sources) ...SrcSpan.parseAll(s),
      if (cell != null) ...?index?.spansOfCell(cell),
      if (net != null) ...?index?.spansOfNet(net),
    ];
    final user = <SrcSpan>[];
    for (final span in spans) {
      if (registers.sourceFileOf(span.file) != null && !user.contains(span)) {
        user.add(span);
      }
    }
    final isStorage =
        storage ?? (cell != null && (index?.isStorage(cell) ?? false));

    // 1. register, by name.
    if (isStorage && cell != null) {
      final stem = registers.registerForCellName(cell);
      if (stem != null) return _register(stem, user);
    }
    if (net != null) {
      final own = registers[_baseName(net)];
      if (own != null) return _register(own, user);
    }
    // 1. register, by span.
    final declared = _unique([
      for (final s in user) ...registers.declaredAt(s),
    ]);
    if (declared != null) return _register(declared, user);
    if (isStorage) {
      final inBlock = _unique([
        for (final s in user) ...registers.assignedInBlock(s),
      ]);
      if (inBlock != null) return _register(inBlock, user);
    }

    // 2. statement.
    final lines = [
      for (final s in user)
        if (_singleLine(s)) s,
    ];
    if (lines.isNotEmpty) {
      final assigned = _unique([
        for (final s in lines) ...registers.assignedAt(s),
      ]);
      return RtlMapping(
        fidelity: MappingFidelity.statement,
        register: assigned?.name,
        spans: [
          ...lines,
          for (final s in user)
            if (!_singleLine(s)) s,
        ],
      );
    }

    // 3. span.
    if (user.isNotEmpty) {
      return RtlMapping(fidelity: MappingFidelity.span, spans: user);
    }

    // 4. unmapped.
    return RtlMapping.unmapped;
  }

  /// Maps every part of [path].
  ///
  /// The start is storage when the path opens with a clock-to-output
  /// segment and is mapped with the net it drives; the end is storage when
  /// the path closes with a setup or hold check and is mapped with the
  /// sources of the net that reaches it (never that net's name, which
  /// names the data input, not the register). A routing segment maps by its
  /// net and sources, a cell segment by its cell.
  TimingPathMapping resolvePath(TimingPath path) {
    final segments = path.segments;
    final startStorage =
        segments.isNotEmpty &&
        segments.any(
          (s) =>
              s.type == TimingSegmentType.clkToQ &&
              s.fromCell == path.startpoint,
        );
    final endStorage = segments.any(
      (s) =>
          (s.type == TimingSegmentType.setup ||
              s.type == TimingSegmentType.hold) &&
          s.toCell == path.endpoint,
    );
    TimingSegment? firstRoutingFrom(String cell) {
      for (final s in segments) {
        if (s.type == TimingSegmentType.routing && s.fromCell == cell) return s;
      }
      return null;
    }

    TimingSegment? lastRoutingInto(String cell) {
      for (final s in segments.reversed) {
        if (s.type == TimingSegmentType.routing && s.toCell == cell) return s;
      }
      return null;
    }

    final out = firstRoutingFrom(path.startpoint);
    final startpoint = resolve(
      cell: path.startpoint,
      net: startStorage ? out?.net : null,
      sources: out?.sources ?? const <String>[],
      storage: startStorage,
    );
    final into = lastRoutingInto(path.endpoint);
    final endpoint = resolve(
      cell: path.endpoint,
      sources: into?.sources ?? const <String>[],
      storage: endStorage,
    );
    return TimingPathMapping(
      startpoint: startpoint,
      endpoint: endpoint,
      segments: [
        for (final s in segments)
          switch (s.type) {
            TimingSegmentType.routing => resolve(
              net: s.net,
              sources: s.sources,
            ),
            TimingSegmentType.clkToQ when s.fromCell == path.startpoint =>
              startpoint,
            TimingSegmentType.setup ||
            TimingSegmentType.hold when s.toCell == path.endpoint => endpoint,
            _ => resolve(cell: s.toCell, sources: s.sources),
          },
      ],
    );
  }

  RtlMapping _register(RtlRegister register, List<SrcSpan> user) => RtlMapping(
    fidelity: MappingFidelity.register,
    register: register.name,
    spans: [
      ...register.declaration,
      for (final s in user)
        if (!register.declaration.contains(s)) s,
    ],
  );

  static bool _singleLine(SrcSpan s) =>
      s.endLine == null || s.endLine == s.startLine;

  /// [name] without a trailing bit or slice select (`src_a[7]` is
  /// `src_a`).
  static String _baseName(String name) {
    if (!name.endsWith(']')) return name;
    final open = name.lastIndexOf('[');
    return open > 0 ? name.substring(0, open) : name;
  }

  /// The one register in [candidates], or null when there are none or
  /// several distinct ones.
  static RtlRegister? _unique(List<RtlRegister> candidates) {
    RtlRegister? only;
    for (final c in candidates) {
      if (only == null) {
        only = c;
      } else if (only.name != c.name) {
        return null;
      }
    }
    return only;
  }
}
