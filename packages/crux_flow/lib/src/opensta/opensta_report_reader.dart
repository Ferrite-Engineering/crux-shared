// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:meta/meta.dart';

/// Which check an OpenSTA path listing reports.
enum OpenStaPathDelay {
  /// Setup checks (`report_checks -path_delay max`, LibreLane's `max.rpt`).
  max('max'),

  /// Hold checks (`report_checks -path_delay min`, LibreLane's `min.rpt`).
  min('min');

  const OpenStaPathDelay(this.wireName);

  /// The stable token: OpenSTA's own `Path Type:` word.
  final String wireName;
}

/// What [OpenStaReportReader] read from one listing.
@immutable
class OpenStaReport {
  /// Creates a report.
  const OpenStaReport({
    required this.paths,
    required this.pathCount,
    required this.skipped,
    this.corner,
    this.pathDelay,
  });

  /// The corner the listing's banner names (`nom_tt_025C_1v80`), when it
  /// has one.
  final String? corner;

  /// Setup or hold, from the listing's `Path Type:` lines; null when it
  /// lists no path.
  final OpenStaPathDelay? pathDelay;

  /// The worst paths kept, by slack, worst first, ranked from 1. Ties keep
  /// the listing's order.
  final List<TimingPath> paths;

  /// How many paths the listing holds, kept or not.
  final int pathCount;

  /// Paths that could not be read and were left out: a block without a
  /// slack line, or one whose rows do not add up to a path.
  final int skipped;
}

/// Reads an OpenSTA `report_checks -format full_clock_expanded` text listing,
/// the per-corner `max.rpt` and `min.rpt` LibreLane's post-PnR STA step
/// writes.
///
/// Three properties of these listings, measured on LibreLane 3.0.15 to
/// 3.0.17 runs, shape the reader:
///
/// - **Order.** The listing is sorted by slack only to the six decimals it
///   prints, so the reader sorts by the printed slack itself and ranks from
///   that, keeping the listing's order between equal slacks.
/// - **Coverage.** One path per endpoint, cut at 1,000 endpoints per path
///   group: a design with more endpoints than that does not list them all,
///   so a register missing from the listing is not known to meet timing.
/// - **Size.** A corner of a 1,600 flip-flop design reaches 8 MB, so the
///   file is read as a stream of lines and only the worst [maxPaths] paths
///   are kept with their segments.
///
/// Segments run from the startpoint to the data input of the endpoint:
/// `clk-to-q` through the launching flip-flop, `routing` from a cell output
/// to the next cell input (named by the net row between them), `logic`
/// through a cell, and a closing `setup` or `hold` segment with the
/// library's setup or hold time when the endpoint is a flip-flop. Clock
/// tree rows before the startpoint are not segments. Delays are in
/// nanoseconds as printed, with integer picoseconds beside them.
@immutable
class OpenStaReportReader {
  /// Creates a reader bounded by [limits], keeping [maxPaths] paths.
  const OpenStaReportReader({
    this.limits = FlowInputLimits.defaults,
    this.maxPaths = 100,
  });

  /// The input bounds: [FlowInputLimits.maxBytes] for the file and
  /// [FlowInputLimits.maxLineLength] per line (a longer line is skipped).
  final FlowInputLimits limits;

  /// The most paths kept.
  final int maxPaths;

  /// Parses a whole listing held in memory.
  OpenStaReport parse(String text) {
    if (text.length > limits.maxBytes) {
      throw FlowReadException(
        FlowReadFailure.tooLarge,
        'input is ${text.length} characters, over the cap of '
        '${limits.maxBytes}',
      );
    }
    final collector = _Collector(maxPaths, limits.maxLineLength);
    const LineSplitter().convert(text).forEach(collector.add);
    return collector.finish();
  }

  /// Reads the listing at [path] as a stream of lines.
  ///
  /// Throws [FileSystemException] when the file is absent, unreadable or not
  /// a regular file (a named pipe, a link to a device), and
  /// [FlowReadException] when it is over the byte cap or not UTF-8.
  Future<OpenStaReport> readFile(String path) async {
    requireRegularFlowFile(path);
    final file = File(path);
    final length = await file.length();
    if (length > limits.maxBytes) {
      throw FlowReadException(
        FlowReadFailure.tooLarge,
        'the listing is $length bytes, over the cap of ${limits.maxBytes}',
      );
    }
    final collector = _Collector(maxPaths, limits.maxLineLength);
    try {
      // No further than the cap, should the listing grow after its length
      // was taken.
      await file
          .openRead(0, limits.maxBytes)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach(collector.add);
    } on FormatException catch (e) {
      throw FlowReadException(
        FlowReadFailure.malformed,
        'the listing is not UTF-8: ${e.message}',
      );
    }
    return collector.finish();
  }
}

final RegExp _corner = RegExp(r'^=+ (\S+) Corner =+\s*$');
final RegExp _pinRow = RegExp(r'^([\^v]) (\S+) \(([^)]+)\)$');
final RegExp _netRow = RegExp(r'^(\S+) \(net\)$');
final RegExp _clockEdge = RegExp(r'^clock (\S+) \((rise|fall) edge\)$');
final RegExp _pointKind = RegExp(r'^(\S+) \((.*)\)$');
final RegExp _clockedBy = RegExp(
  r'(rising|falling) edge-triggered .* clocked by (\S+)$',
);
final RegExp _portClockedBy = RegExp(r'clocked by (\S+)$');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _rule = RegExp(r'^-+$');

/// One path block being read.
class _Block {
  String? start;
  String? startKind;
  String? end;
  String? endKind;
  String? type;
  bool inTable = false;
  bool pastArrival = false;
  double? arrival;
  double? slack;
  double? launchEdge;
  double? libraryCheck;
  final List<({List<double> cols, String desc})> rows = [];
}

/// Accumulates paths line by line and keeps the worst few.
class _Collector {
  _Collector(this.maxPaths, this.maxLineLength);

  final int maxPaths;
  final int maxLineLength;
  String? corner;
  OpenStaPathDelay? pathDelay;
  int count = 0;
  int skipped = 0;
  int _order = 0;
  _Block? _block;
  final List<({double slack, int order, TimingPath path})> _kept = [];

  void add(String line) {
    if (line.length > maxLineLength) return;
    if (corner == null) {
      final m = _corner.firstMatch(line);
      if (m != null) corner = m.group(1);
    }
    if (line.startsWith('Startpoint: ')) {
      _close();
      _block = _Block()..start = line.substring('Startpoint: '.length);
      return;
    }
    final block = _block;
    if (block == null) return;
    if (line.startsWith('Endpoint: ')) {
      block.end = line.substring('Endpoint: '.length);
    } else if (line.startsWith('Path Type: ')) {
      block.type = line.substring('Path Type: '.length).trim();
    } else if (line.startsWith('Fanout') || line.startsWith('  Delay')) {
      block.inTable = true;
    } else if (block.inTable) {
      _row(block, line);
    }
  }

  void _row(_Block block, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || _rule.hasMatch(trimmed)) return;
    // A row is numbers, then a description that starts with a non-number.
    final tokens = trimmed.split(_whitespace);
    final cols = <double>[];
    var i = 0;
    for (; i < tokens.length; i++) {
      final v = double.tryParse(tokens[i]);
      if (v == null || !v.isFinite) break;
      cols.add(v);
    }
    if (i == tokens.length) return;
    final desc = tokens.sublist(i).join(' ');
    if (desc == 'data arrival time') {
      if (!block.pastArrival && cols.isNotEmpty) block.arrival = cols.last;
      block.pastArrival = true;
      return;
    }
    if (desc.startsWith('slack (')) {
      if (cols.isNotEmpty) block.slack = cols.last;
      _close();
      return;
    }
    if (block.pastArrival) {
      if ((desc == 'library setup time' || desc == 'library hold time') &&
          cols.length >= 2) {
        block.libraryCheck = cols[cols.length - 2];
      }
      return;
    }
    if (block.launchEdge == null && _clockEdge.hasMatch(desc)) {
      block.launchEdge = cols.isEmpty ? 0 : cols.last;
    }
    block.rows.add((cols: cols, desc: desc));
  }

  void _close() {
    final block = _block;
    _block = null;
    if (block == null) return;
    final path = _build(block);
    count++;
    if (path == null) {
      skipped++;
      return;
    }
    final slack = block.slack!;
    final order = _order++;
    // Insert in slack order, after equal slacks, and drop past maxPaths.
    var lo = 0;
    var hi = _kept.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_kept[mid].slack <= slack) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo >= maxPaths) return;
    _kept.insert(lo, (slack: slack, order: order, path: path));
    if (_kept.length > maxPaths) _kept.removeLast();
  }

  TimingPath? _build(_Block block) {
    final startLine = block.start;
    final endLine = block.end;
    final arrival = block.arrival;
    final slack = block.slack;
    if (startLine == null ||
        endLine == null ||
        arrival == null ||
        slack == null) {
      return null;
    }
    final startMatch = _pointKind.firstMatch(startLine);
    final endMatch = _pointKind.firstMatch(endLine);
    if (startMatch == null || endMatch == null) return null;
    final start = startMatch.group(1)!;
    final end = endMatch.group(1)!;
    final startKind = startMatch.group(2)!;
    final endKind = endMatch.group(2)!;
    final delay = switch (block.type) {
      'max' => OpenStaPathDelay.max,
      'min' => OpenStaPathDelay.min,
      _ => null,
    };
    pathDelay ??= delay;

    // Pin rows from the startpoint on.
    final pins = <({String inst, String? port, double delay, String? net})>[];
    String? pendingNet;
    var started = false;
    for (final row in block.rows) {
      final net = _netRow.firstMatch(row.desc);
      if (net != null) {
        pendingNet = net.group(1);
        continue;
      }
      final pin = _pinRow.firstMatch(row.desc);
      if (pin == null) continue;
      final name = pin.group(2)!;
      if (!started) {
        if (name != start && !name.startsWith('$start/')) {
          pendingNet = null;
          continue;
        }
        started = true;
      }
      if (row.cols.length < 2) return null;
      final slash = name.lastIndexOf('/');
      pins.add((
        inst: slash < 0 ? name : name.substring(0, slash),
        port: slash < 0 ? null : name.substring(slash + 1),
        delay: row.cols[row.cols.length - 2],
        net: pendingNet,
      ));
      pendingNet = null;
    }
    if (pins.isEmpty) return null;

    final segments = <TimingSegment>[];
    final startIsRegister = startKind.contains('flip-flop');
    for (var k = 1; k < pins.length; k++) {
      final from = pins[k - 1];
      final to = pins[k];
      final String rawType;
      if (from.inst == to.inst) {
        rawType = k == 1 && startIsRegister && from.inst == start
            ? 'clk-to-q'
            : 'logic';
      } else {
        rawType = 'routing';
      }
      segments.add(
        TimingSegment(
          type: TimingSegmentType.fromToolWord(rawType),
          rawType: rawType,
          fromCell: from.inst,
          fromPort: from.port,
          toCell: to.inst,
          toPort: to.port,
          net: rawType == 'routing' ? to.net : null,
          delayPs: nanosecondsToPicoseconds(to.delay),
          delayNs: to.delay,
        ),
      );
    }
    final check = block.libraryCheck;
    if (check != null && endKind.contains('flip-flop')) {
      final isSetup = delay != OpenStaPathDelay.min;
      // The listing adds the check to the required time: a setup time is
      // printed negative, a hold time as it is.
      final ns = isSetup ? -check : check;
      segments.add(
        TimingSegment(
          type: isSetup ? TimingSegmentType.setup : TimingSegmentType.hold,
          rawType: isSetup ? 'setup' : 'hold',
          fromCell: end,
          toCell: end,
          delayPs: nanosecondsToPicoseconds(ns),
          delayNs: ns,
        ),
      );
    }
    final delayNs = arrival - (block.launchEdge ?? 0);
    final (fromEdge, clockFrom) = _clockOf(startKind);
    final (toEdge, clockTo) = _clockOf(endKind);
    return TimingPath(
      rank: 0,
      clockFrom: clockFrom,
      fromEdge: fromEdge,
      clockTo: clockTo,
      toEdge: toEdge,
      startpoint: start,
      endpoint: end,
      slackPs: nanosecondsToPicoseconds(slack),
      delayPs: nanosecondsToPicoseconds(delayNs),
      delayNs: delayNs,
      segments: List.unmodifiable(segments),
      origin: TimingPathOrigin.openSta,
    );
  }

  static (ClockEdge?, String?) _clockOf(String kind) {
    final flop = _clockedBy.firstMatch(kind);
    if (flop != null) {
      return (
        flop.group(1) == 'rising' ? ClockEdge.rising : ClockEdge.falling,
        flop.group(2),
      );
    }
    final port = _portClockedBy.firstMatch(kind);
    return (null, port?.group(1));
  }

  OpenStaReport finish() {
    _close();
    return OpenStaReport(
      corner: corner,
      pathDelay: pathDelay,
      paths: List.unmodifiable([
        for (final (i, k) in _kept.indexed)
          TimingPath(
            rank: i + 1,
            clockFrom: k.path.clockFrom,
            fromEdge: k.path.fromEdge,
            clockTo: k.path.clockTo,
            toEdge: k.path.toEdge,
            startpoint: k.path.startpoint,
            endpoint: k.path.endpoint,
            slackPs: k.path.slackPs,
            delayPs: k.path.delayPs,
            delayNs: k.path.delayNs,
            segments: k.path.segments,
            origin: k.path.origin,
          ),
      ]),
      pathCount: count,
      skipped: skipped,
    );
  }
}
