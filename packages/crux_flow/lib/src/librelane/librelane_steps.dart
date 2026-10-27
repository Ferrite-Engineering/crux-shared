// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/src/flow_containment.dart';
import 'package:crux_flow/src/flow_step.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The names a LibreLane step directory has: `NN-<tool>-<step>`. Any other
/// entry of a run root (`final`, `tmp`, a stray file) is not a step.
final RegExp kLibreLaneStepDirectory = RegExp(r'^(\d+)-([A-Za-z0-9_.-]+)$');

/// The most entries of a run root considered, so a directory holding a
/// million files is never walked whole.
const int kLibreLaneMaxRootEntries = 4096;

/// What `flow.log` records about a run's steps.
@immutable
class LibreLaneFlowLog {
  /// Creates a summary.
  const LibreLaneFlowLog({
    this.stepIds = const <String, String>{},
    this.skipped = const <String>[],
  });

  /// Reads the summary from [text], the whole log.
  ///
  /// Lines longer than [maxLineLength] are skipped. Paths in `Running`
  /// lines are relative to wherever LibreLane was started, so only their
  /// last segment is used.
  factory LibreLaneFlowLog.parse(String text, {int maxLineLength = 65536}) {
    final ids = <String, String>{};
    final skipped = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.length > maxLineLength) continue;
      final running = _running.firstMatch(line);
      if (running != null) {
        final segments = running
            .group(2)!
            .split(RegExp(r'[/\\]'))
            .where((s) => s.isNotEmpty)
            .toList();
        if (segments.isEmpty) continue;
        final dir = segments.last;
        if (!kLibreLaneStepDirectory.hasMatch(dir)) continue;
        // `42-openroad-repairantennas/1-openroad-diodeinsertion`: a sub-step.
        if (segments.length > 1 &&
            kLibreLaneStepDirectory.hasMatch(segments[segments.length - 2])) {
          continue;
        }
        ids[dir] = running.group(1)!;
        continue;
      }
      final skip = _skipping.firstMatch(line);
      if (skip != null) skipped.add(skip.group(1)!);
    }
    return LibreLaneFlowLog(
      stepIds: Map.unmodifiable(ids),
      skipped: List.unmodifiable(skipped),
    );
  }

  /// Step directory name (`55-openroad-stapostpnr`) to the step id LibreLane
  /// ran in it (`OpenROAD.STAPostPNR`), from its
  /// `Running '<id>' at '<dir>'` lines. A composite step's sub-steps, which
  /// run in directories inside its own, are left out.
  final Map<String, String> stepIds;

  /// The display names of steps a flow variable turned off
  /// (`Skipping step '<name>'`): they get no directory and no id.
  final List<String> skipped;

  static final RegExp _running = RegExp(
    "^Running '([^']{1,256})' at '([^']{1,4096})'",
  );
  static final RegExp _skipping = RegExp("^Skipping step '([^']{1,256})'");
}

/// Reads the steps of a LibreLane run root.
///
/// A step's state comes from what it left behind, never from its directory
/// alone:
///
/// - `state_out.json` present: [FlowStepStatus.completed]. A step that
///   decided at run time to do nothing still completes this way.
/// - `state_out.json` absent: [FlowStepStatus.failed], whether the step
///   stopped the flow (it is then the last directory and the run has no
///   `final/`) or was a checker whose error LibreLane deferred to the end of
///   the flow (later steps ran). While the flow process still runs
///   (`live`), the newest directory without it is
///   [FlowStepStatus.running] instead.
///
/// Steps a flow variable turned off have no directory; they are listed by
/// [LibreLaneFlowLog.skipped], by display name. LibreLane 3.0 does not
/// record the flow's step list in the run (`resolved.json` `meta.flow` is
/// null), so steps not yet reached are not listed.
@immutable
class LibreLaneStepReader {
  /// Creates a reader bounded by [limits].
  const LibreLaneStepReader({this.limits = FlowInputLimits.defaults});

  /// The input bounds.
  final FlowInputLimits limits;

  /// The steps under [runRoot], in ordinal order, with ids from [log].
  ///
  /// [runRoot] must already be contained; a step directory that resolves
  /// outside it (a symbolic link) is ignored. [FlowStep.dir],
  /// [FlowStep.logPath] and [FlowStep.metricsOut] are relative to
  /// [runRoot].
  List<FlowStep> read(
    String runRoot, {
    LibreLaneFlowLog log = const LibreLaneFlowLog(),
    bool live = false,
  }) {
    final containment = FlowContainment(<String>[runRoot]);
    final found = <(int, String, String)>[];
    try {
      var seen = 0;
      for (final entity in Directory(runRoot).listSync(followLinks: false)) {
        if (++seen > kLibreLaneMaxRootEntries) break;
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        final match = kLibreLaneStepDirectory.firstMatch(name);
        if (match == null) continue;
        final ordinal = int.tryParse(match.group(1)!);
        if (ordinal == null) continue;
        if (!containment.allows(entity.path)) continue;
        found.add((ordinal, name, match.group(2)!));
      }
    } on FileSystemException {
      return const <FlowStep>[];
    }
    found.sort((a, b) {
      final byOrdinal = a.$1.compareTo(b.$1);
      return byOrdinal != 0 ? byOrdinal : a.$2.compareTo(b.$2);
    });
    final steps = <FlowStep>[];
    for (final (ordinal, name, slug) in found) {
      final dir = p.join(runRoot, name);
      final id = log.stepIds[name] ?? slug;
      final dot = id.indexOf('.');
      final dash = slug.indexOf('-');
      final completed =
          FileSystemEntity.typeSync(p.join(dir, 'state_out.json')) ==
          FileSystemEntityType.file;
      steps.add(
        FlowStep(
          ordinal: ordinal,
          id: id,
          tool: dot > 0
              ? id.substring(0, dot)
              : (dash < 0 ? slug : slug.substring(0, dash)),
          dir: name,
          status: completed ? FlowStepStatus.completed : FlowStepStatus.failed,
          runtime: completed ? _runtime(p.join(dir, 'runtime.txt')) : null,
          logPath: _firstLog(dir, name),
          metricsOut:
              FileSystemEntity.typeSync(p.join(dir, 'or_metrics_out.json')) ==
                  FileSystemEntityType.file
              ? p.join(name, 'or_metrics_out.json')
              : null,
        ),
      );
    }
    if (live) {
      final newest = steps.lastIndexWhere(
        (s) => s.status != FlowStepStatus.completed,
      );
      if (newest >= 0 && newest == steps.length - 1) {
        final s = steps[newest];
        steps[newest] = FlowStep(
          ordinal: s.ordinal,
          id: s.id,
          tool: s.tool,
          dir: s.dir,
          status: FlowStepStatus.running,
          logPath: s.logPath,
          metricsOut: s.metricsOut,
        );
      }
    }
    return List.unmodifiable(steps);
  }

  /// `HH:MM:SS.mmm`, as LibreLane writes `runtime.txt`; null when absent or
  /// not that shape.
  Duration? _runtime(String path) {
    try {
      // A link to a device or a named pipe is refused here, unread.
      final bytes = readFlowBytesSync(path, 64);
      if (bytes.length > 64) return null;
      final text = utf8.decode(bytes, allowMalformed: true);
      final m = _runtimeShape.firstMatch(text.trim());
      if (m == null) return null;
      final ms = (m.group(4) ?? '').padRight(3, '0').substring(0, 3);
      return Duration(
        hours: int.parse(m.group(1)!),
        minutes: int.parse(m.group(2)!),
        seconds: int.parse(m.group(3)!),
        milliseconds: int.parse(ms),
      );
    } on FileSystemException {
      return null;
    }
  }

  static final RegExp _runtimeShape = RegExp(
    r'^(\d{1,6}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?$',
  );

  /// The step's largest `*.log` (the tool's own; a step keeps small helper
  /// logs beside it), the first in name order on a tie, relative to the run
  /// root.
  String? _firstLog(String dir, String name) {
    try {
      final logs = <(int, String)>[];
      var seen = 0;
      for (final e in Directory(dir).listSync(followLinks: false)) {
        if (++seen > kLibreLaneMaxRootEntries) break;
        if (e is File && e.path.endsWith('.log')) {
          logs.add((e.lengthSync(), p.basename(e.path)));
        }
      }
      if (logs.isEmpty) return null;
      logs.sort((a, b) {
        final bySize = b.$1.compareTo(a.$1);
        return bySize != 0 ? bySize : a.$2.compareTo(b.$2);
      });
      return p.join(name, logs.first.$2);
    } on FileSystemException {
      return null;
    }
  }
}

/// Reads [path] as text within [limits], or null when it is absent.
///
/// Throws [FlowReadException] when it is over the byte cap or not UTF-8.
String? readOptionalFlowText(String path, FlowInputLimits limits) {
  final file = File(path);
  if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
    return null;
  }
  try {
    final length = file.lengthSync();
    if (length > limits.maxBytes) {
      throw FlowReadException(
        FlowReadFailure.tooLarge,
        '${p.basename(path)} is $length bytes, over the cap of '
        '${limits.maxBytes}',
      );
    }
    return decodeFlowText(readFlowBytesSync(path, limits.maxBytes), limits);
  } on FileSystemException {
    return null;
  }
}
