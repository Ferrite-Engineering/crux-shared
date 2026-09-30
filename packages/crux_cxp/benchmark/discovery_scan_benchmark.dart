// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How long one `CxpDiscovery` scan holds the calling isolate.
///
///     dart run benchmark/discovery_scan_benchmark.dart [--scans N]
///
/// Or compiled ahead of time, which is how the products run:
///
///     dart compile exe benchmark/discovery_scan_benchmark.dart -o /tmp/b
///     /tmp/b --scans 50
///
/// The manifest directory holds what a user running the whole suite has:
/// four live peers, three stale peers whose processes are still running (a
/// sleeping laptop's leftovers, pruned from view and kept on disk), a
/// half-written scratch file and one undecodable manifest. Every peer's pid
/// names a real running process, so every scan probes seven pids exactly as
/// it would in the products.
///
/// Two numbers per scan:
///
/// - **busy**: the time the scan's own callbacks ran on this isolate, summed.
///   Measured by a zone that times every callback the scan registers, so it
///   counts the work after each `await` as well as the work before the
///   first one.
/// - **stall**: the longest time the event loop could not run anything else
///   while one of the scan's callbacks was running — what a frame waiting to
///   be drawn waits. Measured by a zero-delay timer that re-arms itself for
///   the whole run: the longest gap between two of its firings that overlaps
///   a callback of the scan. Gaps while the scan waits on I/O are not the
///   scan's, and are not counted.
///
/// Both are wall-clock times, so a loaded machine inflates them. Compare
/// revisions by running their binaries back to back, not against a number
/// measured another day.
///
/// It uses only the public API, so the same file measures any revision.
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final scans = _intArg(args, '--scans') ?? 40;
  const interval = Duration(milliseconds: 250);
  const warmUp = 3;

  final dir = await Directory.systemTemp.createTemp('cxp_scan_bench_');
  final sleepers = <Process>[
    for (var i = 0; i < 7; i++) await Process.start('sleep', ['600']),
  ];
  try {
    await _populate(dir.path, sleepers.map((s) => s.pid).toList());

    final clock = Stopwatch()..start();
    final meter = _CallbackMeter(clock);
    final probe = _StallProbe(clock)..start();

    final discovery = CxpDiscovery(
      manifestDirectory: dir.path,
      selfPeerId: 'wavecrux-$pid-1',
      scanInterval: interval,
    );
    await runZoned(discovery.start, zoneSpecification: meter.specification);
    await Future<void>.delayed(interval * (scans + warmUp) + interval ~/ 2);
    await discovery.stop();
    probe.stop();

    final peers = discovery.peers.length;
    final perScan = meter
        .scans(separation: interval ~/ 2)
        .skip(warmUp)
        .map(
          (s) => (
            busy: s.segments.fold(0, (sum, c) => sum + c.end - c.start),
            stall: s.segments
                .map((c) => probe.longestGapWithin(c.start, c.end))
                .fold(0, (a, b) => a > b ? a : b),
          ),
        )
        .toList();
    if (perScan.isEmpty) {
      stderr.writeln('no scans recorded');
      exitCode = 1;
      return;
    }
    final busy = perScan.map((s) => s.busy).toList()..sort();
    final stall = perScan.map((s) => s.stall).toList()..sort();
    stdout
      ..writeln(
        '${Platform.operatingSystem} ${Platform.version.split(' ').first}, '
        '${perScan.length} scans after $warmUp warm-up, $peers live peers '
        'reported',
      )
      ..writeln('busy  (us): ${_summary(busy)}')
      ..writeln('stall (us): ${_summary(stall)}');
  } finally {
    for (final sleeper in sleepers) {
      sleeper.kill();
    }
    await dir.delete(recursive: true);
  }
}

/// Four live peers, three stale ones, a scratch file and one bad manifest.
Future<void> _populate(String dir, List<int> pids) async {
  final now = DateTime.now().toUtc();
  final anHourAgo = now.subtract(const Duration(hours: 1));
  const products = ['wavecrux', 'netcrux', 'lintcrux', 'simcrux'];
  Future<void> manifest(String product, int pid, int port, DateTime at) {
    final peerId = '$product-$pid-${at.millisecondsSinceEpoch}';
    return File(p.join(dir, '$peerId.json')).writeAsString(
      '{"identity": {"peer_id": "$peerId", "product_name": "$product", '
      '"product_version": "1.0.0", "capabilities": []}, '
      '"host": "127.0.0.1", "port": $port, '
      '"started_at": ${at.millisecondsSinceEpoch}, "token": "t"}',
    );
  }

  for (var i = 0; i < 4; i++) {
    await manifest(products[i], pids[i], 47100 + i, now);
  }
  for (var i = 0; i < 3; i++) {
    await manifest(products[i], pids[4 + i], 47200 + i, anHourAgo);
  }
  await File(
    p.join(dir, 'netcrux-1-1.json.1785006661556-0.tmp'),
  ).writeAsString('{"partial": ');
  await File(p.join(dir, 'garbage.json')).writeAsString('{not json');
}

/// Times every callback run in its zone, outermost only.
final class _CallbackMeter {
  _CallbackMeter(this._clock);

  final Stopwatch _clock;
  final List<({int start, int end})> _segments = [];
  var _depth = 0;

  R _time<R>(R Function() body) {
    if (_depth > 0) return body();
    _depth++;
    final start = _clock.elapsedMicroseconds;
    try {
      return body();
    } finally {
      _depth--;
      _segments.add((start: start, end: _clock.elapsedMicroseconds));
    }
  }

  ZoneSpecification get specification => ZoneSpecification(
    run: <R>(self, parent, zone, f) => _time(() => parent.run(zone, f)),
    runUnary: <R, T>(self, parent, zone, f, arg) =>
        _time(() => parent.runUnary(zone, f, arg)),
    runBinary: <R, T1, T2>(self, parent, zone, f, a, b) =>
        _time(() => parent.runBinary(zone, f, a, b)),
  );

  /// Segments grouped into scans: a gap longer than [separation] between
  /// one segment's end and the next one's start begins a new scan.
  List<({List<({int start, int end})> segments})> scans({
    required Duration separation,
  }) {
    final result = <({List<({int start, int end})> segments})>[];
    var current = <({int start, int end})>[];
    for (final s in _segments) {
      if (current.isNotEmpty &&
          s.start - current.last.end > separation.inMicroseconds) {
        result.add((segments: current));
        current = [];
      }
      current.add(s);
    }
    if (current.isNotEmpty) result.add((segments: current));
    return result;
  }
}

/// A zero-delay timer chain recording when each firing happened.
final class _StallProbe {
  _StallProbe(this._clock);

  final Stopwatch _clock;
  final List<int> _firings = [];
  var _running = false;

  void start() {
    _running = true;
    Zone.root.run(() => Timer.run(_fire));
  }

  void stop() => _running = false;

  void _fire() {
    _firings.add(_clock.elapsedMicroseconds);
    if (_running) Timer.run(_fire);
  }

  /// The longest gap between consecutive firings that overlaps
  /// [start]..[end].
  int longestGapWithin(int start, int end) {
    // The first firing at or after [start]; the gap ending there is the
    // first that overlaps the window.
    var lo = 0;
    var hi = _firings.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_firings[mid] < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    var longest = 0;
    for (var i = lo < 1 ? 1 : lo; i < _firings.length; i++) {
      final before = _firings[i - 1];
      if (before > end) break;
      final gap = _firings[i] - before;
      if (gap > longest) longest = gap;
    }
    return longest;
  }
}

String _summary(List<int> sorted) {
  int at(double q) => sorted[((sorted.length - 1) * q).round()];
  return 'median ${at(0.5)}, p95 ${at(0.95)}, max ${sorted.last}';
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? int.tryParse(args[i + 1]) : null;
}
