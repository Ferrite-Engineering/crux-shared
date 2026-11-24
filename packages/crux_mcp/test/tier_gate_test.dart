// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:test/test.dart';

void main() {
  const gate = McpTierGate(environmentVariable: 'WAVECRUX_LICENSE_FILE');
  const program = McpProgram(name: 'wavecrux', version: '2.0.0');

  test('an admitted tier says nothing', () {
    expect(gate.requireTier('Pro', what: 'advise', admitted: true), isNull);
    expect(
      gate.refuse(
        program: program,
        command: 'advise',
        tier: 'Pro',
        admitted: true,
      ),
      isNull,
    );
  });

  test('a closed gate is a licence_error naming the tier and the fix', () {
    final doc = gate.refuse(
      program: program,
      command: 'advise',
      tier: 'Pro',
      admitted: false,
    )!;
    expect(doc.outcome, McpOutcome.licenceError);
    expect(doc.body, isNull);
    final parsed = jsonDecode(doc.render()) as Map<String, Object?>;
    expect(parsed['outcome'], 'licence_error');
    final d =
        (parsed['diagnostics']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(d['severity'], 'error');
    expect(d['code'], 'licence.tier_required');
    expect(d['message'], contains('Pro licence'));
    expect(d['message'], contains('advise'));
    final fix = d['fix']! as String;
    expect(fix, contains('--license-file'));
    expect(fix, contains('WAVECRUX_LICENSE_FILE'));
    expect(fix, contains('.crux-policy.json'));
    expect(
      fix.indexOf('--license-file') < fix.indexOf('WAVECRUX_LICENSE_FILE') &&
          fix.indexOf('WAVECRUX_LICENSE_FILE') <
              fix.indexOf('.crux-policy.json'),
      isTrue,
      reason: 'the fix names the sources in the order they are read',
    );
    expect(McpExitCodes.suite.exitCodeFor(doc.outcome), 77);
  });

  test('a withheld part is a warning; the answer stands', () {
    final d = gate.withhold('The CDC check', tier: 'Pro');
    expect(d.severity, McpSeverity.warning);
    expect(d.code, 'licence.withheld');
    expect(d.message, startsWith('The CDC check needs a Pro licence'));
    expect(d.fix, gate.fix);
    final doc = McpDocument(
      tool: program,
      command: 'lint',
      outcome: McpOutcome.completed,
      body: const <String, Object?>{},
      diagnostics: <McpDiagnostic>[d],
    );
    expect(doc.contractProblems(), isEmpty);
  });

  test('no em dash in anything a user reads', () {
    final texts = <String>[
      gate.fix,
      gate.requireTier('Pro', what: 'x', admitted: false)!.message,
      gate.withhold('x', tier: 'Pro').message,
    ];
    for (final t in texts) {
      expect(t, isNot(contains('—')));
    }
  });
}
