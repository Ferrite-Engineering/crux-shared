// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

Map<String, Object?> _metrics(String version) =>
    jsonDecode(
          File(
            'test/fixtures/librelane/$version/sky130A_met/run/final/'
            'metrics.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

/// The step ids a run's `flow.log` says it ran, read with a plain regex.
Set<String> _ranIds(String version) => {
  for (final m
      in RegExp(
        "^Running '([^']+)'",
        multiLine: true,
      ).allMatches(
        File(
          'test/fixtures/librelane/$version/sky130A_met/run/flow.log',
        ).readAsStringSync(),
      ))
    m.group(1)!,
};

void main() {
  group('the 3.0 check set, held to both verified releases', () {
    // KLayout density and antenna checkers exist in 3.0 but are not steps
    // of the Classic flow, so their metrics are never written there.
    const notInClassic = {
      'klayout__density_error__count',
      'klayout__antenna_error__count',
    };

    for (final version in ['3.0.15', '3.0.16']) {
      test('$version: every checked metric is in the final metrics', () {
        final metrics = _metrics(version);
        for (final check in kLibreLane30Checks) {
          expect(
            metrics.containsKey(check.metric),
            !notInClassic.contains(check.metric),
            reason: check.metric,
          );
        }
      });

      test('$version: every checker of the set ran in the Classic flow', () {
        final ran = _ranIds(version);
        for (final check in kLibreLane30Checks) {
          final checker = check.checker;
          if (checker == null) continue;
          if (checker == 'Checker.KLayoutDensity' ||
              checker == 'Checker.KLayoutAntenna') {
            expect(ran, isNot(contains(checker)));
          } else {
            expect(ran, contains(checker), reason: checker);
          }
        }
      });
    }

    test('every metric in the upstream table is lower-is-better', () {
      for (final check in kLibreLane30Checks) {
        final definition = librelaneMetricsV1[check.metric];
        if (definition == null) continue;
        expect(definition.higherIsBetter, isFalse, reason: check.metric);
      }
    });
  });

  group('evaluateLibreLaneChecks', () {
    const setup = 'timing__setup_vio__count';

    LibreLaneFinding? finding(
      Map<String, Object?> metrics,
      Map<String, Object?> config,
      String metric,
    ) {
      final out = evaluateLibreLaneChecks(metrics, config);
      for (final f in out.findings) {
        if (f.check.metric == metric) return f;
      }
      return null;
    }

    test('per corner: the setup wildcards decide enforcement', () {
      final metrics = {
        '${setup}__corner:nom_tt': 0,
        '${setup}__corner:nom_ss': 3,
        setup: 3,
      };
      final tt = finding(metrics, const {
        'TIMING_VIOLATION_CORNERS': ['*tt*'],
      }, setup)!;
      expect(tt.corners, ['nom_ss']);
      expect(tt.value, 3);
      expect((tt.enforced, tt.violates), (false, false));
      final ss = finding(metrics, const {
        'SETUP_VIOLATION_CORNERS': ['*ss*'],
        'TIMING_VIOLATION_CORNERS': ['*tt*'],
      }, setup)!;
      expect((ss.enforced, ss.violates), (true, true));
      // An empty own list falls back to the base list, as LibreLane does.
      final fallback = finding(metrics, const {
        'SETUP_VIOLATION_CORNERS': <String>[],
        'TIMING_VIOLATION_CORNERS': ['*'],
      }, setup)!;
      expect(fallback.enforced, isTrue);
      // A deny wildcard removes a corner.
      final denied = finding(metrics, const {
        'TIMING_VIOLATION_CORNERS': ['*', '!*ss*'],
      }, setup)!;
      expect(denied.enforced, isFalse);
    });

    test('the empty wildcard checks no corner', () {
      final f = finding(
        const {'design__max_cap_violation__count__corner:nom_tt': 1},
        const {
          'MAX_CAP_VIOLATION_CORNERS': [''],
          'TIMING_VIOLATION_CORNERS': ['*tt*'],
        },
        'design__max_cap_violation__count',
      )!;
      expect(f.enforced, isFalse);
    });

    test('ERROR_ON_* off keeps the finding, unenforced', () {
      final f = finding(
        const {'route__drc_errors': 4},
        const {'ERROR_ON_TR_DRC': false},
        'route__drc_errors',
      )!;
      expect((f.enforced, f.violates), (false, false));
      final on = finding(
        const {'route__drc_errors': 4},
        const {},
        'route__drc_errors',
      )!;
      expect(on.enforced, isTrue);
    });

    test('antenna counts violate with no checker', () {
      final f = finding(
        const {'antenna__violating__nets': 1},
        const {},
        'antenna__violating__nets',
      )!;
      expect((f.enforced, f.violates), (false, true));
    });

    test('a threshold variable: unset skips, set compares', () {
      const metric = 'route__wirelength__max';
      final unset = evaluateLibreLaneChecks(const {metric: 900}, const {});
      expect(unset.absent, contains(metric));
      expect(unset.findings, isEmpty);
      expect(
        finding(
          const {metric: 900},
          const {'WIRE_LENGTH_THRESHOLD': 1000},
          metric,
        ),
        isNull,
      );
      expect(
        finding(
          const {metric: 1100},
          const {'WIRE_LENGTH_THRESHOLD': 1000},
          metric,
        )?.enforced,
        isTrue,
      );
    });

    test('absent, non-numeric and non-finite values are not zero', () {
      final out = evaluateLibreLaneChecks(const {
        'magic__drc_error__count': 'n/a',
        'klayout__drc_error__count': double.infinity,
      }, const {});
      expect(out.absent, contains('magic__drc_error__count'));
      expect(out.absent, contains('klayout__drc_error__count'));
      expect(out.absent, contains('design__lvs_error__count'));
      expect(out.evaluated, isEmpty);
      expect(out.findings, isEmpty);
    });
  });
}
