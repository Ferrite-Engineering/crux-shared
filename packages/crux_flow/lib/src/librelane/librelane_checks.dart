// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_flow/src/metrics/metric_filter.dart';
import 'package:crux_flow/src/metrics/metric_key.dart';
import 'package:meta/meta.dart';

/// What a LibreLane check is about, for grouping findings.
enum LibreLaneCheckCategory {
  /// Setup or hold slack, or a timing design rule (slew, capacitance).
  timing('timing'),

  /// Design rules: routing, Magic or KLayout DRC, density.
  drc('drc'),

  /// Layout against the circuit it was built from (LVS).
  lvs('lvs'),

  /// Antenna ratios.
  antenna('antenna'),

  /// Any other physical check: XOR, overlaps, disconnected pins, the power
  /// grid, wire length.
  physical('physical'),

  /// Lint and synthesis checks.
  synthesis('synthesis');

  const LibreLaneCheckCategory(this.wireName);

  /// The stable token written to JSON and SARIF.
  final String wireName;
}

/// One metric a completed LibreLane run is judged on, and how LibreLane's
/// own checker for it decides.
///
/// A count past its threshold (zero unless [thresholdVariable] names a
/// configuration value) is a finding. Where LibreLane has a checker step
/// ([checker]), the finding records whether that checker would raise an
/// error for it ([LibreLaneFinding.enforced]): its `ERROR_ON_*` variable
/// ([errorOnVariable]) is on and, for a per-corner check, the violating
/// corner matches the wildcards of [cornerVariable] (falling back to
/// [baseCornerVariable], as LibreLane's own checker does).
@immutable
class LibreLaneCheck {
  /// Creates a check.
  const LibreLaneCheck({
    required this.metric,
    required this.category,
    this.checker,
    this.errorOnVariable,
    this.errorOnDefault = true,
    this.cornerVariable,
    this.baseCornerVariable,
    this.thresholdVariable,
  });

  /// The METRICS2.1 base name (`magic__drc_error__count`).
  final String metric;

  /// What the check is about.
  final LibreLaneCheckCategory category;

  /// LibreLane's checker step id (`Checker.MagicDRC`); null for a metric no
  /// checker fails on (antenna violations are reported, not checked).
  final String? checker;

  /// The configuration variable that makes the checker raise an error.
  final String? errorOnVariable;

  /// [errorOnVariable]'s default when the configuration does not set it.
  final bool errorOnDefault;

  /// For a per-corner check: the variable listing the corner wildcards it
  /// checks (`SETUP_VIOLATION_CORNERS`).
  final String? cornerVariable;

  /// The variable [cornerVariable] falls back to when unset or empty
  /// (`TIMING_VIOLATION_CORNERS`).
  final String? baseCornerVariable;

  /// The variable holding the threshold, when it is not zero
  /// (`WIRE_LENGTH_THRESHOLD`). A null threshold skips the check, as
  /// LibreLane's checker does.
  final String? thresholdVariable;

  /// Whether the metric is judged per corner.
  bool get perCorner => cornerVariable != null;
}

/// The checks of the LibreLane 3.0 line, from `librelane/steps/checker.py`
/// at 3.0.15 and 3.0.16 (identical in both): every `MetricChecker` and
/// `TimingViolations` subclass with its metric, error variable, corner
/// variable and threshold, plus the two antenna counts
/// `Misc.ReportManufacturability` reports and no checker fails on.
///
/// Lint warnings (`design__lint_warning__count`, error off by default) are
/// not a finding. `Checker.NetlistAssignStatements` and
/// `Checker.LintTimingConstructs` stop the flow when they fail, so a
/// completed run has passed them.
const List<LibreLaneCheck> kLibreLane30Checks = <LibreLaneCheck>[
  LibreLaneCheck(
    metric: 'timing__setup_vio__count',
    category: LibreLaneCheckCategory.timing,
    checker: 'Checker.SetupViolations',
    cornerVariable: 'SETUP_VIOLATION_CORNERS',
    baseCornerVariable: 'TIMING_VIOLATION_CORNERS',
  ),
  LibreLaneCheck(
    metric: 'timing__hold_vio__count',
    category: LibreLaneCheckCategory.timing,
    checker: 'Checker.HoldViolations',
    cornerVariable: 'HOLD_VIOLATION_CORNERS',
    baseCornerVariable: 'TIMING_VIOLATION_CORNERS',
  ),
  LibreLaneCheck(
    metric: 'design__max_slew_violation__count',
    category: LibreLaneCheckCategory.timing,
    checker: 'Checker.MaxSlewViolations',
    cornerVariable: 'MAX_SLEW_VIOLATION_CORNERS',
    baseCornerVariable: 'TIMING_VIOLATION_CORNERS',
  ),
  LibreLaneCheck(
    metric: 'design__max_cap_violation__count',
    category: LibreLaneCheckCategory.timing,
    checker: 'Checker.MaxCapViolations',
    cornerVariable: 'MAX_CAP_VIOLATION_CORNERS',
    baseCornerVariable: 'TIMING_VIOLATION_CORNERS',
  ),
  LibreLaneCheck(
    metric: 'route__drc_errors',
    category: LibreLaneCheckCategory.drc,
    checker: 'Checker.TrDRC',
    errorOnVariable: 'ERROR_ON_TR_DRC',
  ),
  LibreLaneCheck(
    metric: 'magic__drc_error__count',
    category: LibreLaneCheckCategory.drc,
    checker: 'Checker.MagicDRC',
    errorOnVariable: 'ERROR_ON_MAGIC_DRC',
  ),
  LibreLaneCheck(
    metric: 'klayout__drc_error__count',
    category: LibreLaneCheckCategory.drc,
    checker: 'Checker.KLayoutDRC',
    errorOnVariable: 'ERROR_ON_KLAYOUT_DRC',
  ),
  LibreLaneCheck(
    metric: 'klayout__density_error__count',
    category: LibreLaneCheckCategory.drc,
    checker: 'Checker.KLayoutDensity',
    errorOnVariable: 'ERROR_ON_KLAYOUT_DENSITY',
  ),
  LibreLaneCheck(
    metric: 'design__lvs_error__count',
    category: LibreLaneCheckCategory.lvs,
    checker: 'Checker.LVS',
    errorOnVariable: 'ERROR_ON_LVS_ERROR',
  ),
  LibreLaneCheck(
    metric: 'route__antenna_violation__count',
    category: LibreLaneCheckCategory.antenna,
  ),
  LibreLaneCheck(
    metric: 'antenna__violating__nets',
    category: LibreLaneCheckCategory.antenna,
  ),
  LibreLaneCheck(
    metric: 'klayout__antenna_error__count',
    category: LibreLaneCheckCategory.antenna,
    checker: 'Checker.KLayoutAntenna',
    errorOnVariable: 'ERROR_ON_KLAYOUT_ANTENNA',
  ),
  LibreLaneCheck(
    metric: 'design__xor_difference__count',
    category: LibreLaneCheckCategory.physical,
    checker: 'Checker.XOR',
    errorOnVariable: 'ERROR_ON_XOR_ERROR',
  ),
  LibreLaneCheck(
    metric: 'magic__illegal_overlap__count',
    category: LibreLaneCheckCategory.physical,
    checker: 'Checker.IllegalOverlap',
    errorOnVariable: 'ERROR_ON_ILLEGAL_OVERLAPS',
  ),
  LibreLaneCheck(
    metric: 'design__critical_disconnected_pin__count',
    category: LibreLaneCheckCategory.physical,
    checker: 'Checker.DisconnectedPins',
    errorOnVariable: 'ERROR_ON_DISCONNECTED_PINS',
  ),
  LibreLaneCheck(
    metric: 'design__power_grid_violation__count',
    category: LibreLaneCheckCategory.physical,
    checker: 'Checker.PowerGridViolations',
    errorOnVariable: 'ERROR_ON_PDN_VIOLATIONS',
  ),
  LibreLaneCheck(
    metric: 'route__wirelength__max',
    category: LibreLaneCheckCategory.physical,
    checker: 'Checker.WireLength',
    errorOnVariable: 'ERROR_ON_LONG_WIRE',
    thresholdVariable: 'WIRE_LENGTH_THRESHOLD',
  ),
  LibreLaneCheck(
    metric: 'design__instance_unmapped__count',
    category: LibreLaneCheckCategory.synthesis,
    checker: 'Checker.YosysUnmappedCells',
    errorOnVariable: 'ERROR_ON_UNMAPPED_CELLS',
  ),
  LibreLaneCheck(
    metric: 'synthesis__check_error__count',
    category: LibreLaneCheckCategory.synthesis,
    checker: 'Checker.YosysSynthChecks',
    errorOnVariable: 'ERROR_ON_SYNTH_CHECKS',
  ),
  LibreLaneCheck(
    metric: 'design__lint_error__count',
    category: LibreLaneCheckCategory.synthesis,
    checker: 'Checker.LintErrors',
    errorOnVariable: 'ERROR_ON_LINTER_ERRORS',
  ),
];

/// One check a completed run fails.
@immutable
class LibreLaneFinding {
  /// Creates a finding.
  const LibreLaneFinding({
    required this.check,
    required this.value,
    this.corners = const <String>[],
    this.enforced = false,
  });

  /// The check.
  final LibreLaneCheck check;

  /// The metric's value: for a per-corner check, the largest over the
  /// corners in [corners]; otherwise the run's final value.
  final num value;

  /// For a per-corner check, the corners past the threshold, sorted.
  final List<String> corners;

  /// Whether LibreLane's own checker raises an error for this finding: its
  /// `ERROR_ON_*` variable is on and, per corner, a violating corner is one
  /// the configuration asks it to check.
  final bool enforced;

  /// Whether the finding makes a completed run `violated`: LibreLane's
  /// checker enforces it, or no checker looks at the metric at all (antenna
  /// violations). A finding the configuration tells LibreLane to warn about
  /// only (a corner outside `*_VIOLATION_CORNERS`, an `ERROR_ON_*` turned
  /// off) is kept and shown, and leaves the verdict alone.
  bool get violates => enforced || check.checker == null;

  @override
  String toString() => 'LibreLaneFinding(${check.metric} $value $corners)';
}

/// What [evaluateLibreLaneChecks] found.
@immutable
class LibreLaneCheckOutcome {
  /// Creates an outcome.
  const LibreLaneCheckOutcome({
    required this.findings,
    required this.evaluated,
    required this.absent,
  });

  /// The checks the run fails, in table order.
  final List<LibreLaneFinding> findings;

  /// The metrics the run carries and that were judged.
  final List<String> evaluated;

  /// The metrics the run does not carry: not run (gf180mcuD has no KLayout
  /// DRC deck), never read as zero.
  final List<String> absent;
}

/// Judges [metrics] (a run's `final/metrics.json`) against [checks] under
/// the run's resolved configuration [config] (`resolved.json`).
///
/// A per-corner check reads `<metric>__corner:<c>` for every corner the run
/// timed: a corner past the threshold is a finding whether or not the
/// configured corner wildcards select it, and the finding is
/// [LibreLaneFinding.enforced] only when they do. A run with no per-corner
/// values for it is judged on the plain metric. A metric that is absent or
/// not a number is listed in [LibreLaneCheckOutcome.absent].
LibreLaneCheckOutcome evaluateLibreLaneChecks(
  Map<String, Object?> metrics,
  Map<String, Object?> config, {
  List<LibreLaneCheck> checks = kLibreLane30Checks,
}) {
  final findings = <LibreLaneFinding>[];
  final evaluated = <String>[];
  final absent = <String>[];
  for (final check in checks) {
    num threshold = 0;
    if (check.thresholdVariable != null) {
      final t = config[check.thresholdVariable];
      if (t is! num) {
        // LibreLane skips a check whose threshold is unset.
        absent.add(check.metric);
        continue;
      }
      threshold = t;
    }
    final errorOn = _errorOn(check, config);
    if (check.perCorner) {
      final perCorner = _perCorner(metrics, check.metric);
      if (perCorner.isNotEmpty) {
        evaluated.add(check.metric);
        final wildcards = _cornerWildcards(check, config);
        final over = <String>[
          for (final MapEntry(:key, :value) in perCorner.entries)
            if (value > threshold) key,
        ]..sort();
        if (over.isEmpty) continue;
        final selected = MetricFilter(wildcards);
        var worst = perCorner[over.first]!;
        for (final c in over) {
          if (perCorner[c]! > worst) worst = perCorner[c]!;
        }
        findings.add(
          LibreLaneFinding(
            check: check,
            value: worst,
            corners: List.unmodifiable(over),
            enforced: errorOn && over.any(selected.matches),
          ),
        );
        continue;
      }
    }
    final value = metrics[check.metric];
    if (value is! num || !value.isFinite) {
      absent.add(check.metric);
      continue;
    }
    evaluated.add(check.metric);
    if (value > threshold) {
      findings.add(
        LibreLaneFinding(check: check, value: value, enforced: errorOn),
      );
    }
  }
  return LibreLaneCheckOutcome(
    findings: List.unmodifiable(findings),
    evaluated: List.unmodifiable(evaluated),
    absent: List.unmodifiable(absent),
  );
}

/// Whether [check]'s checker exists and would raise an error.
bool _errorOn(LibreLaneCheck check, Map<String, Object?> config) {
  if (check.checker == null) return false;
  final name = check.errorOnVariable;
  if (name == null) return true;
  final value = config[name];
  return value is bool ? value : check.errorOnDefault;
}

/// The corner wildcards a per-corner check selects, as LibreLane's
/// `TimingViolations.get_corner_wildcards`: the check's own variable, or
/// the base one when that is unset or empty, without the empty wildcard
/// that means "no corner".
List<String> _cornerWildcards(
  LibreLaneCheck check,
  Map<String, Object?> config,
) {
  List<String> read(String? name) {
    final value = name == null ? null : config[name];
    if (value is! List<Object?>) return const <String>[];
    return [
      for (final w in value)
        if (w is String) w,
    ];
  }

  var wildcards = read(check.cornerVariable);
  if (wildcards.isEmpty) wildcards = read(check.baseCornerVariable);
  return [
    for (final w in wildcards)
      if (w.isNotEmpty) w,
  ];
}

/// `<metric>__corner:<c>` values by corner, finite numbers only.
Map<String, num> _perCorner(Map<String, Object?> metrics, String metric) {
  final out = <String, num>{};
  for (final MapEntry(:key, :value) in metrics.entries) {
    if (!key.startsWith('${metric}__corner:')) continue;
    if (value is! num || !value.isFinite) continue;
    final parsed = MetricKey.tryParse(key);
    final corner = parsed?.modifier('corner');
    if (parsed == null || parsed.base != metric || corner == null) continue;
    out[corner] = value;
  }
  return out;
}
