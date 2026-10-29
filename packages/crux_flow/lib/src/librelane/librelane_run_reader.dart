// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/src/flow_containment.dart';
import 'package:crux_flow/src/flow_kind.dart';
import 'package:crux_flow/src/flow_reader_support.dart';
import 'package:crux_flow/src/flow_run.dart';
import 'package:crux_flow/src/flow_step.dart';
import 'package:crux_flow/src/flow_verdict.dart';
import 'package:crux_flow/src/librelane/librelane_checks.dart';
import 'package:crux_flow/src/librelane/librelane_metrics_reader.dart';
import 'package:crux_flow/src/librelane/librelane_steps.dart';
import 'package:crux_flow/src/librelane/librelane_version.dart';
import 'package:crux_flow/src/metrics/metric_definition.dart';
import 'package:crux_flow/src/metrics/metric_filter.dart';
import 'package:crux_flow/src/opensta/opensta_report_reader.dart';
import 'package:crux_flow/src/read_limits.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// An inclusive range of LibreLane releases a reader was verified against.
@immutable
class LibreLaneVersionRange {
  /// The releases from [first] to [last], both included.
  const LibreLaneVersionRange(this.first, this.last);

  /// The oldest verified release.
  final LibreLaneVersion first;

  /// The newest verified release.
  final LibreLaneVersion last;

  /// Whether [version] is a release (nothing after `major.minor.patch`)
  /// inside the range.
  bool contains(LibreLaneVersion version) =>
      version.isRelease &&
      version.compareTo(first) >= 0 &&
      version.compareTo(last) <= 0;

  @override
  String toString() => '$first to $last';
}

/// Everything a LibreLane reader learned from one run directory.
@immutable
class LibreLaneReading {
  /// Creates a reading.
  const LibreLaneReading({
    required this.run,
    this.version,
    this.unsupported,
    this.problem,
    this.stoppedStep,
    this.skippedSteps = const <String>[],
    this.errorRecords = const <String>[],
    this.checks,
    this.metrics,
    this.pdk,
    this.stdCellLibrary,
    this.designName,
    this.clockPort,
    this.clockPeriodNs,
    this.timingCorner,
    this.timingProblem,
    this.timingPathCount = 0,
  });

  /// The run: reference (with `verified`), verdict, steps, final metrics,
  /// worst setup paths and artifacts.
  final FlowRun run;

  /// The release `resolved.json` names, when it names one.
  final LibreLaneVersion? version;

  /// Why the reader is not verified for this run, when it is not.
  final FlowReaderUnsupported? unsupported;

  /// What could not be read, when something could not.
  final String? problem;

  /// The id of the step a stopped run stopped at.
  final String? stoppedStep;

  /// Display names of steps a flow variable turned off.
  final List<String> skippedSteps;

  /// The first lines of the run's `error.log`, bounded.
  final List<String> errorRecords;

  /// The run's metrics judged against the reader's checks, when it has
  /// final metrics.
  final LibreLaneCheckOutcome? checks;

  /// The final metrics as read, when the run has them.
  final LibreLaneMetrics? metrics;

  /// `PDK` from `resolved.json` (`sky130A`).
  final String? pdk;

  /// `STD_CELL_LIBRARY` from `resolved.json`.
  final String? stdCellLibrary;

  /// `DESIGN_NAME` from `resolved.json`.
  final String? designName;

  /// `CLOCK_PORT` from `resolved.json`, when it names one port.
  final String? clockPort;

  /// `CLOCK_PERIOD` from `resolved.json`, in nanoseconds.
  final double? clockPeriodNs;

  /// The STA corner [FlowRun.timing] was read from.
  final String? timingCorner;

  /// Why no timing paths were read, when the run has an STA step and none
  /// were.
  final String? timingProblem;

  /// How many setup paths the corner's listing holds, kept or not.
  final int timingPathCount;

  /// The verdict.
  FlowVerdict get verdict => run.verdict;

  /// Whether a reader verified for this release read it.
  bool get verified => run.ref.verified;
}

/// Reads one LibreLane release line's run directories.
///
/// One subclass per verified minor line. A release that changes what a
/// fixture of an existing line reads as gets a new subclass; an existing
/// reader's behaviour is never edited to follow it, so a run read once
/// reads the same way again.
abstract class LibreLaneRunReader {
  /// Creates a reader bounded by [limits].
  const LibreLaneRunReader({this.limits = FlowInputLimits.defaults});

  /// The input bounds for every file read.
  final FlowInputLimits limits;

  /// The minor line, `major.minor`.
  String get line;

  /// The releases this reader was verified against.
  LibreLaneVersionRange get verified;

  /// The checks a completed run of this line is judged on.
  List<LibreLaneCheck> get checks;

  /// The metric table this line's metrics aggregate with.
  MetricDefinitionTable get metricTable;

  /// Reads the run at [runRoot] (already contained). [version] is the
  /// release the registry detected; the reading is verified only when this
  /// reader's range contains it.
  ///
  /// [live] says the flow process still runs, so the newest step without
  /// output state is running rather than failed. [timingPaths] caps the
  /// setup paths read into [FlowRun.timing]; zero reads none.
  Future<LibreLaneReading> read(
    String runRoot, {
    String? tag,
    LibreLaneVersion? version,
    bool live = false,
    int timingPaths = 100,
  });
}

/// The reader for the LibreLane 3.0 line, verified against 3.0.15, 3.0.16
/// and 3.0.17 (sky130A on all three, gf180mcuD and IHP sg13g2 on 3.0.16 and
/// 3.0.17).
///
/// What it reads, all of it inside the run root:
///
/// - `resolved.json`: the release (`meta.librelane_version`, falling back
///   to `meta.openlane_version`), the PDK and cell library, the design and
///   clock, and every checker's configuration variable.
/// - The step directories (see [LibreLaneStepReader]), `flow.log` (step ids
///   and steps turned off) and `error.log` (the first lines, kept as
///   records).
/// - `final/metrics.json`, or `final/metrics.csv` (see
///   [LibreLaneMetricsReader]).
/// - The post-PnR STA step's setup listing for one corner (see
///   [OpenStaReportReader]).
///
/// The verdict comes from these records, never from the exit status:
///
/// - **stopped**: no final metrics; the step that stopped it is the newest
///   without output state.
/// - **violated**: final metrics, and a step without output state is
///   followed by later steps (a checker's deferred error), or a check of
///   [kLibreLane30Checks] fails in a way LibreLane enforces or no checker
///   looks at (antenna violations).
/// - **met**: final metrics, at least one check evaluated, none failing so.
/// - **unrecognised**: final metrics that carry none of the checked metrics,
///   or a metrics file that could not be read.
/// - **notRun**: no run directory.
class LibreLane30RunReader extends LibreLaneRunReader {
  /// Creates the reader.
  const LibreLane30RunReader({super.limits});

  @override
  String get line => '3.0';

  @override
  LibreLaneVersionRange get verified => kLibreLane30Verified;

  @override
  List<LibreLaneCheck> get checks => kLibreLane30Checks;

  @override
  MetricDefinitionTable get metricTable => librelaneMetricsV1;

  @override
  Future<LibreLaneReading> read(
    String runRoot, {
    String? tag,
    LibreLaneVersion? version,
    bool live = false,
    int timingPaths = 100,
  }) async {
    final runTag = tag ?? p.basename(runRoot);
    FlowRunRef ref({required bool isVerified}) => FlowRunRef(
      kind: FlowKind.librelane,
      root: runRoot,
      tag: runTag,
      readerVersion: line,
      verified: isVerified,
    );
    if (FileSystemEntity.typeSync(runRoot) != FileSystemEntityType.directory) {
      return LibreLaneReading(
        run: FlowRun(
          ref: ref(isVerified: false),
          verdict: FlowVerdict.notRun,
        ),
        unsupported: FlowReaderUnsupported.layoutUnknown,
        problem: 'the run directory does not exist',
      );
    }
    final containment = FlowContainment(<String>[runRoot]);
    FlowReaderUnsupported? unsupported;
    String? problem;

    // resolved.json
    var config = const <String, Object?>{};
    try {
      final resolved = await readLibreLaneResolved(runRoot, limits);
      if (resolved == null) {
        unsupported = FlowReaderUnsupported.layoutUnknown;
      } else {
        config = resolved;
      }
    } on FlowContainmentException catch (e) {
      unsupported = FlowReaderUnsupported.layoutUnknown;
      problem = 'resolved.json: ${e.reason}';
    } on FlowReadException catch (e) {
      unsupported = FlowReaderUnsupported.schemaUnknown;
      problem = 'resolved.json: ${e.message}';
    }
    if (version == null || !verified.contains(version)) {
      unsupported ??= FlowReaderUnsupported.versionUnknown;
    }

    // flow.log, error.log, steps.
    var log = const LibreLaneFlowLog();
    final errors = <String>[];
    try {
      final text = readOptionalFlowText(
        containment.require(p.join(runRoot, 'flow.log')),
        limits,
      );
      if (text != null) {
        log = LibreLaneFlowLog.parse(text, maxLineLength: limits.maxLineLength);
      }
      final errorText = readOptionalFlowText(
        containment.require(p.join(runRoot, 'error.log')),
        limits,
      );
      if (errorText != null) {
        for (final l in const LineSplitter().convert(errorText)) {
          if (l.trim().isEmpty) continue;
          errors.add(l.length > 400 ? '${l.substring(0, 400)}...' : l);
          if (errors.length >= 20) break;
        }
      }
    } on FlowContainmentException catch (e) {
      problem ??= 'run logs: ${e.reason}';
    } on FlowReadException catch (e) {
      problem ??= 'run logs: ${e.message}';
    }
    final steps = LibreLaneStepReader(
      limits: limits,
    ).read(runRoot, log: log, live: live);

    // final metrics.
    LibreLaneMetrics? metrics;
    var metricsUnreadable = false;
    try {
      metrics = LibreLaneMetricsReader(
        limits: limits,
        table: metricTable,
      ).read(runRoot);
    } on FlowContainmentException catch (e) {
      metricsUnreadable = true;
      problem ??= 'final metrics: ${e.reason}';
    } on FlowReadException catch (e) {
      metricsUnreadable = true;
      unsupported = FlowReaderUnsupported.schemaUnknown;
      problem ??= 'final metrics: ${e.message}';
    }

    // Verdict.
    FlowVerdict verdict;
    String? stoppedStep;
    LibreLaneCheckOutcome? outcome;
    if (metricsUnreadable) {
      verdict = FlowVerdict.unrecognised;
    } else if (metrics == null) {
      if (steps.isEmpty) {
        verdict = FlowVerdict.notRun;
        unsupported ??= FlowReaderUnsupported.layoutUnknown;
        problem ??= 'the run has no step directories and no final metrics';
      } else {
        verdict = FlowVerdict.stopped;
        final at = steps.lastIndexWhere(
          (s) => s.status != FlowStepStatus.completed,
        );
        stoppedStep = (at >= 0 ? steps[at] : steps.last).id;
        problem ??= 'the run has no final metrics';
      }
    } else {
      outcome = evaluateLibreLaneChecks(metrics.values, config, checks: checks);
      final deferred = steps.any((s) => s.status == FlowStepStatus.failed);
      if (deferred || outcome.findings.any((f) => f.violates)) {
        verdict = FlowVerdict.violated;
      } else if (outcome.evaluated.isEmpty) {
        verdict = FlowVerdict.unrecognised;
        problem ??= 'the final metrics carry none of the checked metrics';
      } else {
        verdict = FlowVerdict.met;
      }
    }
    // Timing.
    final sta = _lastStep(steps, 'openroad-stapostpnr');
    String? corner;
    String? timingProblem;
    var timing = const <TimingPath>[];
    var pathCount = 0;
    if (sta != null && timingPaths > 0) {
      try {
        corner = chooseLibreLaneTimingCorner(
          _corners(p.join(runRoot, sta.dir)),
          config,
        );
        if (corner != null) {
          final listing = containment.require(
            p.join(runRoot, sta.dir, corner, 'max.rpt'),
          );
          if (FileSystemEntity.typeSync(listing) == FileSystemEntityType.file) {
            final report = await OpenStaReportReader(
              limits: limits,
              maxPaths: timingPaths,
            ).readFile(listing);
            timing = report.paths;
            pathCount = report.pathCount;
          } else {
            timingProblem = 'the corner has no setup listing';
          }
        } else {
          timingProblem = 'the STA step lists no corner';
        }
      } on FlowContainmentException catch (e) {
        timingProblem = e.reason;
      } on FlowReadException catch (e) {
        timingProblem = e.message;
      } on FileSystemException catch (e) {
        timingProblem = e.message;
      }
    }

    final design = _string(config['DESIGN_NAME']);
    final period = config['CLOCK_PERIOD'];
    // Verified only for a release in range whose records all read as their
    // schema says.
    final isVerified = unsupported == null;
    return LibreLaneReading(
      run: FlowRun(
        ref: ref(isVerified: isVerified),
        verdict: verdict,
        steps: steps,
        metrics: metrics?.values ?? const <String, Object?>{},
        timing: timing,
        artifacts: Map.unmodifiable(
          _artifacts(runRoot, steps, design, metrics, sta, corner),
        ),
        toolVersions: <String, String>{'librelane': ?version?.raw},
      ),
      version: version,
      unsupported: unsupported,
      problem: problem,
      stoppedStep: stoppedStep,
      skippedSteps: log.skipped,
      errorRecords: List.unmodifiable(errors),
      checks: outcome,
      metrics: metrics,
      pdk: _string(config['PDK']),
      stdCellLibrary: _string(config['STD_CELL_LIBRARY']),
      designName: design,
      clockPort: _string(config['CLOCK_PORT']),
      clockPeriodNs: period is num && period.isFinite && period > 0
          ? period.toDouble()
          : null,
      timingCorner: corner,
      timingProblem: timingProblem,
      timingPathCount: pathCount,
    );
  }

  static FlowStep? _lastStep(List<FlowStep> steps, String slug) {
    for (final s in steps.reversed) {
      final name = s.dir;
      final dash = name.indexOf('-');
      if (dash > 0 && name.substring(dash + 1) == slug) return s;
    }
    return null;
  }

  static List<String> _corners(String staDir) {
    try {
      final out = <String>[];
      var seen = 0;
      for (final e in Directory(staDir).listSync(followLinks: false)) {
        if (++seen > kLibreLaneMaxRootEntries) break;
        if (e is Directory) out.add(p.basename(e.path));
      }
      return out..sort();
    } on FileSystemException {
      return const <String>[];
    }
  }

  static Map<String, String> _artifacts(
    String runRoot,
    List<FlowStep> steps,
    String? design,
    LibreLaneMetrics? metrics,
    FlowStep? sta,
    String? corner,
  ) {
    bool exists(String relative) =>
        FileSystemEntity.typeSync(p.join(runRoot, relative)) !=
        FileSystemEntityType.notFound;
    final out = <String, String>{};
    void put(String kind, String relative) {
      if (exists(relative)) out[kind] = relative;
    }

    put('resolved', 'resolved.json');
    put('flow_log', 'flow.log');
    put('error_log', 'error.log');
    if (metrics != null) out['metrics'] = metrics.source;
    final synth = _lastStep(steps, 'yosys-synthesis');
    if (synth != null && design != null && _safeSegment(design)) {
      put('synthesis_netlist', p.join(synth.dir, '$design.nl.v.json'));
    }
    if (sta != null) {
      out['sta'] = sta.dir;
      if (corner != null) {
        put('sta_max', p.join(sta.dir, corner, 'max.rpt'));
        put('sta_min', p.join(sta.dir, corner, 'min.rpt'));
      }
    }
    if (design != null && _safeSegment(design)) {
      put('gds', p.join('final', 'gds', '$design.gds'));
      put('odb', p.join('final', 'odb', '$design.odb'));
      put('def', p.join('final', 'def', '$design.def'));
      put('final_nl', p.join('final', 'nl', '$design.nl.v'));
      put('final_pnl', p.join('final', 'pnl', '$design.pnl.v'));
    }
    final klayoutDrc = _lastStep(steps, 'klayout-drc');
    if (klayoutDrc != null) {
      put(
        'klayout_drc_markers',
        p.join(klayoutDrc.dir, 'reports', 'drc.klayout.lyrdb'),
      );
    }
    final magicDrc = _lastStep(steps, 'magic-drc');
    if (magicDrc != null) {
      put(
        'magic_drc_markers',
        p.join(magicDrc.dir, 'reports', 'drc.magic.lyrdb'),
      );
    }
    for (final s in steps.reversed) {
      if (s.status == FlowStepStatus.completed) {
        put('last_state', p.join(s.dir, 'state_out.json'));
        break;
      }
    }
    return out;
  }
}

/// The releases [LibreLane30RunReader] was verified against.
const LibreLaneVersionRange kLibreLane30Verified = LibreLaneVersionRange(
  LibreLaneVersion(3, 0, 15),
  LibreLaneVersion(3, 0, 17),
);

/// The LibreLane readers, one per verified minor line, and how a run is
/// matched to one.
@immutable
class LibreLaneReaders {
  /// The registry over [readers], oldest line first.
  const LibreLaneReaders(this.readers);

  /// Every reader this package has, bounded by [limits].
  factory LibreLaneReaders.standard({
    FlowInputLimits limits = FlowInputLimits.defaults,
  }) => LibreLaneReaders(<LibreLaneRunReader>[
    LibreLane30RunReader(limits: limits),
  ]);

  /// The readers, oldest line first.
  final List<LibreLaneRunReader> readers;

  /// The reader for [version] and whether it is verified for it.
  ///
  /// The reader of [version]'s own line when there is one; otherwise the
  /// nearest older line's, or the oldest reader for a release older than
  /// every line. An unknown version selects the newest reader. Only a
  /// release inside the selected reader's verified range is verified.
  (LibreLaneRunReader, bool) select(LibreLaneVersion? version) {
    if (readers.isEmpty) {
      throw StateError('no LibreLane reader is registered');
    }
    final ordered = [...readers]
      ..sort((a, b) => _lineOf(a).compareTo(_lineOf(b)));
    if (version == null) return (ordered.last, false);
    var chosen = ordered.first;
    for (final r in ordered) {
      final line = _lineOf(r);
      if (line.major < version.major ||
          (line.major == version.major && line.minor <= version.minor)) {
        chosen = r;
      }
    }
    return (chosen, chosen.verified.contains(version));
  }

  static LibreLaneVersion _lineOf(LibreLaneRunReader r) =>
      LibreLaneVersion.tryParse(r.line)!;

  /// Detects the release of the run at [runRoot] and reads it with the
  /// reader [select] picks.
  Future<LibreLaneReading> read(
    String runRoot, {
    String? tag,
    bool live = false,
    int timingPaths = 100,
  }) async {
    final limits = readers.isEmpty
        ? FlowInputLimits.defaults
        : readers.first.limits;
    LibreLaneVersion? version;
    try {
      version = detectLibreLaneVersion(
        await readLibreLaneResolved(runRoot, limits),
      );
    } on FlowContainmentException {
      version = null;
    } on FlowReadException {
      version = null;
    }
    final (reader, _) = select(version);
    return await reader.read(
      runRoot,
      tag: tag,
      version: version,
      live: live,
      timingPaths: timingPaths,
    );
  }

  /// Whether [dir] is laid out as a LibreLane run root: it holds
  /// `resolved.json`, a `final/` directory or a step directory.
  static bool looksLikeRun(String dir) {
    if (FileSystemEntity.typeSync(p.join(dir, 'resolved.json')) ==
        FileSystemEntityType.file) {
      return true;
    }
    if (FileSystemEntity.typeSync(p.join(dir, 'final')) ==
        FileSystemEntityType.directory) {
      return true;
    }
    try {
      var seen = 0;
      for (final e in Directory(dir).listSync(followLinks: false)) {
        if (++seen > kLibreLaneMaxRootEntries) break;
        if (e is Directory &&
            kLibreLaneStepDirectory.hasMatch(p.basename(e.path))) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }
}

/// The run's `resolved.json` as an object, or null when it has none.
///
/// Throws [FlowContainmentException] when it resolves outside [runRoot] and
/// [FlowReadException] when it is over a limit or not a JSON object.
Future<Map<String, Object?>?> readLibreLaneResolved(
  String runRoot,
  FlowInputLimits limits,
) async {
  final path = FlowContainment(<String>[
    runRoot,
  ]).require(p.join(runRoot, 'resolved.json'));
  final text = readOptionalFlowText(path, limits);
  if (text == null) return null;
  return requireObject(decodeFlowJson(text, limits), 'resolved.json');
}

/// The release [resolved] (a run's `resolved.json`) names in
/// `meta.librelane_version`, or in `meta.openlane_version` for a run of the
/// line before the rename; null when it names none.
LibreLaneVersion? detectLibreLaneVersion(Map<String, Object?>? resolved) {
  final meta = resolved?['meta'];
  if (meta is! Map<String, Object?>) return null;
  for (final key in const ['librelane_version', 'openlane_version']) {
    final v = meta[key];
    if (v is String) {
      final parsed = LibreLaneVersion.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// The corner of [corners] (the post-PnR STA step's corner directories)
/// whose setup listing a run's worst paths are read from: the first
/// nominal corner (`nom_*`) the setup checker selects
/// (`SETUP_VIOLATION_CORNERS`, else `TIMING_VIOLATION_CORNERS`), else the
/// first nominal corner, else the first corner; null when there is none.
String? chooseLibreLaneTimingCorner(
  List<String> corners,
  Map<String, Object?> config,
) {
  if (corners.isEmpty) return null;
  final sorted = [...corners]..sort();
  List<String> wildcards(String name) {
    final v = config[name];
    if (v is! List<Object?>) return const <String>[];
    return [
      for (final w in v)
        if (w is String && w.isNotEmpty) w,
    ];
  }

  var selected = wildcards('SETUP_VIOLATION_CORNERS');
  if (selected.isEmpty) selected = wildcards('TIMING_VIOLATION_CORNERS');
  final nominal = sorted.where((c) => c.startsWith('nom_')).toList();
  if (selected.isNotEmpty) {
    final filter = MetricFilter(selected);
    for (final c in nominal) {
      if (filter.matches(c)) return c;
    }
  }
  if (nominal.isNotEmpty) return nominal.first;
  return sorted.first;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty && value.length <= 256 ? value : null;

bool _safeSegment(String name) =>
    name.isNotEmpty &&
    !name.contains('/') &&
    !name.contains(r'\') &&
    name != '.' &&
    name != '..' &&
    !name.contains('\x00');
