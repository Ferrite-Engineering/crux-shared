// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_flow/src/librelane/librelane_checks.dart';
import 'package:crux_flow/src/librelane/librelane_run_reader.dart';
import 'package:crux_flow/src/mapping/rtl_register_resolver.dart';
import 'package:crux_flow/src/nextpnr/nextpnr_results.dart';
import 'package:crux_flow/src/rtl_mapping.dart';
import 'package:crux_flow/src/timing_path.dart';
import 'package:crux_io/crux_io.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The SARIF rule a timing path that misses its clock's constraint is
/// reported under.
const String kFlowTimingPathRule = 'flow/timing-path';

/// The SARIF rule a clock that misses its constraint is reported under when
/// the report names no path for it.
const String kFlowClockConstraintRule = 'flow/clock-constraint';

/// The `partialFingerprints` key of every result: the `crux-fnv1a64/1`
/// signature of the rule, the endpoint register and the clock.
const String kFlowSarifFingerprintKey = 'cruxFlowEndpoint/v1';

/// The `uriBaseId` every location is relative to: the design's source root.
const String kFlowSarifSourceRoot = 'SRCROOT';

/// Writes a flow run's timing findings as SARIF 2.1.0, the format the lint
/// product (and any other SARIF consumer) reads with no flow-specific code.
///
/// One result per clock that misses its constraint, anchored at the source
/// of that clock's worst path's endpoint. Results are findings for a person
/// to read, at level `warning`: a completed run that misses timing has
/// produced an answer, not an error.
///
/// **Stable across reruns.** A consumer's baseline matches a result on its
/// rule, file and message, so the message names registers and clocks and
/// never a number: delays, frequencies and the path's rank go in the
/// result's `properties`. `partialFingerprints` carries the
/// `crux-fnv1a64/1` signature of the rule, the endpoint register and the
/// clock for consumers that match on it.
///
/// **No machine paths.** Every location is a URI relative to
/// [kFlowSarifSourceRoot]: a span file inside [sourceRoot] is made relative
/// to it, a relative span file is kept as recorded, and any other (an
/// absolute path elsewhere, one that climbs with `..`) gives the result no
/// location rather than one naming another machine's directories.
///
/// English only, by design: the text is a record a tool reads and a person
/// may forward, and an unreviewed translation of a claim is the risk.
@immutable
class FlowSarifWriter {
  /// Creates a writer.
  const FlowSarifWriter({
    this.toolName = 'EDACrux Flow',
    this.toolVersion,
    this.sourceRoot,
  });

  /// The `tool.driver.name` written.
  final String toolName;

  /// The `tool.driver.version` written, when known.
  final String? toolVersion;

  /// The design's root directory; span files inside it are written
  /// relative to it.
  final String? sourceRoot;

  /// The SARIF log for nextpnr's [report], with registers and source
  /// locations from [resolver] when one is given.
  Map<String, Object?> nextpnr(
    NextpnrReport report, {
    RtlRegisterResolver? resolver,
  }) {
    final results = <Map<String, Object?>>[];
    for (final clock in report.clocks) {
      if (clock.meetsConstraint) continue;
      final paths = [
        for (final path in report.criticalPaths)
          if ((path.clockTo ?? path.clockFrom) == clock.clock) path,
      ]..sort((a, b) => a.rank.compareTo(b.rank));
      if (paths.isEmpty) {
        results.add(_clockResult(clock));
        continue;
      }
      results.add(_pathResult(paths.first, clock, resolver));
    }
    return _log(results);
  }

  /// The SARIF log for a LibreLane run [reading]: one result per failing
  /// check, and, when [worstSetupPath] is given and misses its constraint,
  /// one anchored at its endpoint's source through [worstSetupMapping].
  ///
  /// A check LibreLane enforces, or that no checker looks at (antenna
  /// violations), is a `warning`; one the run's configuration tells
  /// LibreLane only to warn about is a `note`. Physical checks (design
  /// rules, LVS, antenna) have no source location: they are findings about
  /// the layout, not about a line of the design. The corners, the count and
  /// whether LibreLane enforces the check go in `properties`, never in the
  /// message.
  Map<String, Object?> librelane(
    LibreLaneReading reading, {
    TimingPath? worstSetupPath,
    TimingPathMapping? worstSetupMapping,
  }) {
    final results = <Map<String, Object?>>[];
    final findings = reading.checks?.findings ?? const <LibreLaneFinding>[];
    final path = worstSetupPath;
    final pathMisses =
        path != null && path.slackPs != null && path.slackPs! < 0;
    for (final finding in findings) {
      final metric = finding.check.metric;
      final level = finding.violates ? 'warning' : 'note';
      final properties = <String, Object?>{
        'metric': metric,
        'category': finding.check.category.wireName,
        'value': finding.value,
        if (finding.corners.isNotEmpty) 'corners': finding.corners,
        'enforcedByLibreLane': finding.enforced,
        'checker': ?finding.check.checker,
      };
      if (metric == 'timing__setup_vio__count' && pathMisses) {
        final clock = path.clockTo ?? path.clockFrom ?? reading.clockPort ?? '';
        results.add(
          _pathFinding(
            path,
            clock,
            worstSetupMapping,
            level: level,
            extra: properties,
          ),
        );
        continue;
      }
      final rule = _librelaneRule(finding.check.category);
      results.add({
        'ruleId': rule,
        'level': level,
        'message': {
          'text':
              'LibreLane reports ${_librelaneWhat[metric] ?? metric} in this '
              'run.',
        },
        'partialFingerprints': {
          kFlowSarifFingerprintKey: CruxSignature.compute([
            rule,
            metric,
            '',
          ], ''),
        },
        'properties': properties,
      });
    }
    return _log(results, rules: [..._rules, ..._librelaneRules]);
  }

  Map<String, Object?> _pathFinding(
    TimingPath path,
    String clock,
    TimingPathMapping? mapping, {
    required String level,
    required Map<String, Object?> extra,
  }) {
    final start = mapping?.startpoint ?? RtlMapping.unmapped;
    final end = mapping?.endpoint ?? RtlMapping.unmapped;
    final startName = start.register ?? path.startpoint;
    final endName = end.register ?? path.endpoint;
    final location = _location(end);
    final related = _location(start);
    return {
      'ruleId': kFlowTimingPathRule,
      'level': level,
      'message': {
        'text':
            'The worst path from $startName to $endName misses the '
            'constraint of clock $clock.',
      },
      if (location != null) 'locations': [location],
      if (related != null)
        'relatedLocations': [
          {
            'id': 1,
            ...related,
            'message': {'text': 'Path start: $startName'},
          },
        ],
      'partialFingerprints': {
        kFlowSarifFingerprintKey: CruxSignature.compute([
          kFlowTimingPathRule,
          endName,
          clock,
        ], ''),
      },
      'properties': {
        ...extra,
        'clock': clock,
        'rank': path.rank,
        'delayPs': path.delayPs,
        'slackPs': ?path.slackPs,
        'startpoint': path.startpoint,
        'endpoint': path.endpoint,
        'startFidelity': start.fidelity.wireName,
        'endFidelity': end.fidelity.wireName,
      },
    };
  }

  static String _librelaneRule(LibreLaneCheckCategory category) =>
      switch (category) {
        LibreLaneCheckCategory.timing => kFlowTimingCheckRule,
        LibreLaneCheckCategory.drc => kFlowDrcRule,
        LibreLaneCheckCategory.lvs => kFlowLvsRule,
        LibreLaneCheckCategory.antenna => kFlowAntennaRule,
        LibreLaneCheckCategory.physical => kFlowPhysicalRule,
        LibreLaneCheckCategory.synthesis => kFlowSynthesisRule,
      };

  /// What each checked metric counts, as a message names it.
  static const Map<String, String> _librelaneWhat = {
    'timing__setup_vio__count': 'setup timing violations',
    'timing__hold_vio__count': 'hold timing violations',
    'design__max_slew_violation__count': 'maximum slew violations',
    'design__max_cap_violation__count': 'maximum capacitance violations',
    'route__drc_errors': 'routing design rule violations',
    'magic__drc_error__count': 'Magic design rule violations',
    'klayout__drc_error__count': 'KLayout design rule violations',
    'klayout__density_error__count': 'KLayout density violations',
    'design__lvs_error__count': 'LVS mismatches between layout and circuit',
    'route__antenna_violation__count': 'routing antenna violations',
    'antenna__violating__nets': 'nets over their antenna ratio',
    'klayout__antenna_error__count': 'KLayout antenna violations',
    'design__xor_difference__count':
        'differences between the Magic and KLayout layouts',
    'magic__illegal_overlap__count': 'illegal overlaps',
    'design__critical_disconnected_pin__count': 'disconnected pins',
    'design__power_grid_violation__count': 'power grid violations',
    'route__wirelength__max': 'a wire over the length threshold',
    'design__instance_unmapped__count': 'unmapped cells after synthesis',
    'synthesis__check_error__count': 'synthesis check errors',
    'design__lint_error__count': 'lint errors',
  };

  /// [log] as indented JSON with a trailing newline.
  static String encode(Map<String, Object?> log) =>
      '${const JsonEncoder.withIndent('  ').convert(log)}\n';

  Map<String, Object?> _pathResult(
    TimingPath path,
    NextpnrClockFrequency clock,
    RtlRegisterResolver? resolver,
  ) {
    final mapping = resolver?.resolvePath(path);
    final start = mapping?.startpoint ?? RtlMapping.unmapped;
    final end = mapping?.endpoint ?? RtlMapping.unmapped;
    final startName = start.register ?? path.startpoint;
    final endName = end.register ?? path.endpoint;
    final location = _location(end);
    final related = _location(start);
    return {
      'ruleId': kFlowTimingPathRule,
      'level': 'warning',
      'message': {
        'text':
            'The worst path from $startName to $endName misses the '
            'constraint of clock ${clock.clock}.',
      },
      if (location != null) 'locations': [location],
      if (related != null)
        'relatedLocations': [
          {
            'id': 1,
            ...related,
            'message': {'text': 'Path start: $startName'},
          },
        ],
      'partialFingerprints': {
        kFlowSarifFingerprintKey: CruxSignature.compute([
          kFlowTimingPathRule,
          endName,
          clock.clock,
        ], ''),
      },
      'properties': {
        'clock': clock.clock,
        'achievedMhz': clock.achievedMhz,
        'constraintMhz': clock.constraintMhz,
        'rank': path.rank,
        'delayPs': path.delayPs,
        'startpoint': path.startpoint,
        'endpoint': path.endpoint,
        'startFidelity': start.fidelity.wireName,
        'endFidelity': end.fidelity.wireName,
      },
    };
  }

  Map<String, Object?> _clockResult(NextpnrClockFrequency clock) => {
    'ruleId': kFlowClockConstraintRule,
    'level': 'warning',
    'message': {'text': 'Clock ${clock.clock} misses its constraint.'},
    'partialFingerprints': {
      kFlowSarifFingerprintKey: CruxSignature.compute([
        kFlowClockConstraintRule,
        '',
        clock.clock,
      ], ''),
    },
    'properties': {
      'clock': clock.clock,
      'achievedMhz': clock.achievedMhz,
      'constraintMhz': clock.constraintMhz,
    },
  };

  /// The physical location of [mapping]'s first span with a writable URI.
  Map<String, Object?>? _location(RtlMapping mapping) {
    for (final span in mapping.spans) {
      final uri = relativeUri(span.file);
      if (uri == null) continue;
      return {
        'physicalLocation': {
          'artifactLocation': {'uri': uri, 'uriBaseId': kFlowSarifSourceRoot},
          'region': {
            'startLine': span.startLine,
            if (span.startCol != null) 'startColumn': span.startCol,
            if (span.endLine != null) 'endLine': span.endLine,
            if (span.endCol != null) 'endColumn': span.endCol,
          },
        },
      };
    }
    return null;
  }

  /// The URI, relative to [kFlowSarifSourceRoot], that [file] (a span file
  /// as Yosys recorded it) is written as, or null when it has none.
  @visibleForTesting
  String? relativeUri(String file) {
    if (file.isEmpty || file.contains('\x00')) return null;
    final windows = RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(file);
    final absolute = windows || file.startsWith('/');
    final String relative;
    if (absolute) {
      final root = sourceRoot;
      if (root == null || root.isEmpty) return null;
      final made = CruxSignature.projectRelativePath(file, root);
      if (made == file) return null;
      relative = made;
    } else {
      relative = file.replaceAll(r'\', '/');
    }
    final normalized = p.posix.normalize(relative);
    if (normalized == '.' ||
        normalized.startsWith('/') ||
        p.posix.split(normalized).contains('..')) {
      return null;
    }
    return Uri(path: normalized).toString();
  }

  Map<String, Object?> _log(
    List<Map<String, Object?>> results, {
    List<Map<String, Object?>> rules = _rules,
  }) => {
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': toolName,
            if (toolVersion != null) 'version': toolVersion,
            'rules': rules,
          },
        },
        'originalUriBaseIds': {
          kFlowSarifSourceRoot: {
            'description': {'text': "The design's source root."},
          },
        },
        'results': results,
      },
    ],
  };

  static const List<Map<String, Object?>> _rules = [
    {
      'id': kFlowTimingPathRule,
      'name': 'TimingPathMissesConstraint',
      'shortDescription': {
        'text': 'A timing path misses its clock constraint.',
      },
      'fullDescription': {
        'text':
            "The clock's worst path takes longer than the clock period the "
            'run was constrained to. The location is the source of the '
            "path's endpoint as far as the synthesized design records it; "
            'the start of the path is a related location.',
      },
      'defaultConfiguration': {'level': 'warning'},
      'help': {
        'text':
            'Shorten the logic between the two registers, pipeline it, or '
            'relax the clock constraint. The result is a finding from this '
            "run's report, read by the tool that placed and routed it.",
      },
    },
    {
      'id': kFlowClockConstraintRule,
      'name': 'ClockMissesConstraint',
      'shortDescription': {'text': 'A clock misses its constraint.'},
      'fullDescription': {
        'text':
            'The clock reaches a lower frequency than it was constrained to, '
            'and the report names no path for it.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
  ];

  static const List<Map<String, Object?>> _librelaneRules = [
    {
      'id': kFlowTimingCheckRule,
      'name': 'TimingCheckFails',
      'shortDescription': {
        'text': 'A timing check of the implementation run fails.',
      },
      'fullDescription': {
        'text':
            'Setup, hold, slew or capacitance violations at one or more '
            'corners the run timed. The corners and whether the flow '
            'enforces the check are in the properties.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
    {
      'id': kFlowDrcRule,
      'name': 'DesignRuleViolations',
      'shortDescription': {
        'text': 'The layout breaks design rules of the PDK.',
      },
      'fullDescription': {
        'text':
            "A design rule check of the run's layout reports violations. "
            "The markers are in the run's DRC reports; open the layout in "
            'KLayout to see them.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
    {
      'id': kFlowLvsRule,
      'name': 'LvsMismatch',
      'shortDescription': {
        'text': 'The layout does not match the circuit it was built from.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
    {
      'id': kFlowAntennaRule,
      'name': 'AntennaViolations',
      'shortDescription': {'text': 'Nets exceed their antenna ratio.'},
      'defaultConfiguration': {'level': 'warning'},
    },
    {
      'id': kFlowPhysicalRule,
      'name': 'PhysicalCheckFails',
      'shortDescription': {
        'text': 'A physical check of the implementation run fails.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
    {
      'id': kFlowSynthesisRule,
      'name': 'SynthesisCheckFails',
      'shortDescription': {
        'text': 'A lint or synthesis check of the run fails.',
      },
      'defaultConfiguration': {'level': 'warning'},
    },
  ];
}

/// The SARIF rule for a failing LibreLane timing check without a path.
const String kFlowTimingCheckRule = 'flow/timing-check';

/// The SARIF rule for design rule violations.
const String kFlowDrcRule = 'flow/drc';

/// The SARIF rule for LVS mismatches.
const String kFlowLvsRule = 'flow/lvs';

/// The SARIF rule for antenna violations.
const String kFlowAntennaRule = 'flow/antenna';

/// The SARIF rule for the other physical checks.
const String kFlowPhysicalRule = 'flow/physical';

/// The SARIF rule for lint and synthesis checks.
const String kFlowSynthesisRule = 'flow/synthesis';
