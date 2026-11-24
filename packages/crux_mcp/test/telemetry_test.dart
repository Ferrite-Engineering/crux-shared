// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_mcp/crux_mcp.dart';
import 'package:test/test.dart';

void main() {
  List<Map<String, Object?>> record({
    required bool consent,
    Map<String, String> environment = const <String, String>{},
    String outcome = 'completed',
    Duration elapsed = Duration.zero,
  }) {
    final events = <Map<String, Object?>>[];
    McpTelemetry(
      consented: () => consent,
      sink: (event, properties) {
        expect(event, 'mcp.tool_call');
        events.add(properties);
      },
      environment: environment,
    ).toolCalled(tool: 'info', outcome: outcome, elapsed: elapsed);
    return events;
  }

  test('sent under consent, with exactly three properties', () {
    expect(record(consent: true), <Map<String, Object?>>[
      <String, Object?>{
        'tool': 'info',
        'outcome': 'completed',
        'duration': 'lt_1s',
      },
    ]);
  });

  test('never without consent', () {
    expect(record(consent: false), isEmpty);
  });

  test('never when CI is set, whatever its value', () {
    for (final value in <String>['true', '1', '', 'false']) {
      expect(
        record(consent: true, environment: <String, String>{'CI': value}),
        isEmpty,
        reason: 'CI=$value',
      );
    }
  });

  test('an outcome outside the vocabulary is not sent', () {
    expect(record(consent: true, outcome: '/home/x'), isEmpty);
  });

  test('a sink that throws never breaks the call', () {
    McpTelemetry(
      consented: () => true,
      sink: (_, _) => throw StateError('down'),
      environment: const <String, String>{},
    ).toolCalled(tool: 'info', outcome: 'completed', elapsed: Duration.zero);
  });

  test('duration buckets, at each edge', () {
    const s = Duration(seconds: 1);
    expect(mcpDurationBucket(Duration.zero), 'lt_1s');
    expect(mcpDurationBucket(s - const Duration(microseconds: 1)), 'lt_1s');
    expect(mcpDurationBucket(s), '1s_10s');
    expect(mcpDurationBucket(s * 10), '10s_1m');
    expect(mcpDurationBucket(s * 60), '1m_10m');
    expect(mcpDurationBucket(s * 600), 'ge_10m');
    expect(kMcpDurationBuckets, hasLength(5));
  });

  test('the outcome vocabulary is the six outcomes and two more', () {
    expect(
      kMcpToolCallOutcomes,
      <String>{
        ...McpOutcome.values.map((o) => o.wireName),
        'unreadable',
        'crashed',
      },
    );
  });
}
