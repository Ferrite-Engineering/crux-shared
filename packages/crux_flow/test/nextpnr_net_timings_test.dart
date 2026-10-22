// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

void main() {
  test('reads every net of a real report, skipping none that names one', () {
    final text = File(
      'test/fixtures/nextpnr/path_ice40_met/report.json',
    ).readAsStringSync();
    // Independent count: the section as plain JSON.
    final raw =
        (jsonDecode(text) as Map<String, Object?>)['detailed_net_timings']!
            as List<Object?>;
    final nets = const NextpnrReportReader().parseNetTimings(text);
    expect(nets, hasLength(raw.length));
    for (final (i, net) in nets.indexed) {
      final entry = raw[i]! as Map<String, Object?>;
      expect(net.net, entry['net']);
      expect(net.driver, entry['driver']);
      final delays = [
        for (final e in entry['endpoints']! as List<Object?>)
          ((e! as Map<String, Object?>)['delay']! as List<Object?>)[1]! as num,
      ];
      expect(net.endpoints, hasLength(delays.length));
      if (delays.isNotEmpty) {
        expect(net.maxDelayNs, delays.reduce((a, b) => a > b ? a : b));
      }
    }
  });

  test('odd entries are skipped, odd shapes refused', () {
    const reader = NextpnrReportReader();
    final nets = reader.parseNetTimings(
      '{"detailed_net_timings": [1, {"driver": "x"}, {"net": "n", '
      '"endpoints": [{"delay": [0.1]}, {"delay": [0.1, 1e999]}, '
      '{"cell": "c", "delay": [0.1, 0.4]}]}]}',
    );
    expect(nets.single.net, 'n');
    expect(nets.single.endpoints.single.cell, 'c');
    expect(nets.single.maxDelayNs, 0.4);
    expect(reader.parseNetTimings('{}'), isEmpty);
    expect(
      () => reader.parseNetTimings('{"detailed_net_timings": 3}'),
      throwsA(isA<FlowReadException>()),
    );
    expect(
      () => reader.parseNetTimings('[]'),
      throwsA(isA<FlowReadException>()),
    );
    expect(
      () => reader.parseNetTimings('${'[' * 100}${']' * 100}'),
      throwsA(
        isA<FlowReadException>().having(
          (e) => e.failure,
          'failure',
          FlowReadFailure.tooDeep,
        ),
      ),
    );
  });

  test('checkJsonDepth and decodeFlowJson are exported for callers', () {
    expect(
      () => checkJsonDepth('[[[]]]', 2),
      throwsA(isA<FlowReadException>()),
    );
    checkJsonDepth('"[[[[" ', 2);
    expect(decodeFlowJson('{"a": 1}', FlowInputLimits.defaults), {'a': 1});
  });
}
