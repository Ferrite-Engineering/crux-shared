// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:crux_flow/src/sarif/flow_sarif_writer.dart';
import 'package:crux_io/crux_io.dart';
import 'package:test/test.dart';

const _nextpnr = 'test/fixtures/nextpnr';

final Map<String, Object?> _expected =
    jsonDecode(File('$_nextpnr/mapping.expected.json').readAsStringSync())
        as Map<String, Object?>;

final _resolver = RtlRegisterResolver(
  RtlRegisterSet.parse(
    File('test/fixtures/elaboration/path_adder.json').readAsStringSync(),
  ),
);

NextpnrReport _report(String name) => const NextpnrReportReader().parse(
  File('$_nextpnr/$name/report.json').readAsStringSync(),
);

List<Map<String, Object?>> _results(Map<String, Object?> log) {
  final runs = log['runs']! as List<Object?>;
  final run = runs.single! as Map<String, Object?>;
  return (run['results']! as List<Object?>).cast<Map<String, Object?>>();
}

Map<String, Object?> _region(Map<String, Object?> result) {
  final location = (result['locations']! as List<Object?>).single!;
  final physical =
      (location as Map<String, Object?>)['physicalLocation']!
          as Map<String, Object?>;
  return physical['region']! as Map<String, Object?>;
}

String _uri(Map<String, Object?> result) {
  final location = (result['locations']! as List<Object?>).single!;
  final physical =
      (location as Map<String, Object?>)['physicalLocation']!
          as Map<String, Object?>;
  final artifact = physical['artifactLocation']! as Map<String, Object?>;
  expect(artifact['uriBaseId'], kFlowSarifSourceRoot);
  return artifact['uri']! as String;
}

/// [report] with every clock's achieved frequency moved by [delta] MHz: the
/// same design rerun, with different numbers.
NextpnrReport _rerun(NextpnrReport report, double delta) => NextpnrReport(
  clocks: [
    for (final c in report.clocks)
      NextpnrClockFrequency(
        clock: c.clock,
        achievedMhz: c.achievedMhz + delta,
        constraintMhz: c.constraintMhz,
      ),
  ],
  criticalPaths: report.criticalPaths,
  utilization: report.utilization,
);

void main() {
  const writer = FlowSarifWriter(toolVersion: '1.2.0');
  final cases = (_expected['cases']! as Map<String, Object?>)
      .cast<String, Map<String, Object?>>();
  final end = _expected['end_register']! as String;
  final declarations = (_expected['declaration_lines']! as Map<String, Object?>)
      .cast<String, int>();
  final line = _expected['path_statement_line']! as int;

  group('the violated FPGA fixtures', () {
    for (final MapEntry(key: met, value: facts) in cases.entries) {
      final name = met.replaceFirst('_met', '_violated');
      test(name, () {
        final report = _report(name);
        final log = writer.nextpnr(report, resolver: _resolver);
        final results = _results(log);
        final failing = report.clocks.where((c) => !c.meetsConstraint);
        expect(results, hasLength(failing.length));
        expect(results, isNotEmpty);

        final result = results.first;
        expect(result['ruleId'], kFlowTimingPathRule);
        expect(result['level'], 'warning');
        final message = (result['message']! as Map)['text']! as String;
        expect(message, contains(' to $end misses the constraint of clock '));
        expect(message, isNot(contains(RegExp('[0-9]+[.][0-9]'))));
        expect(_uri(result), 'path_adder.v');
        expect(
          _region(result)['startLine'],
          (facts['cell_names_carry_register']! as bool)
              ? declarations[end]
              : line,
        );
        final properties = result['properties']! as Map<String, Object?>;
        expect(properties['achievedMhz'], isA<double>());
        expect(properties['constraintMhz'], 1000.0);
        expect(properties['endFidelity'], isNot('unmapped'));
        expect(result['relatedLocations'], isNotNull);
      });
    }
  });

  test('a run that meets timing has no results', () {
    for (final name in cases.keys) {
      expect(
        _results(writer.nextpnr(_report(name), resolver: _resolver)),
        isEmpty,
        reason: name,
      );
    }
  });

  test('a rerun with different numbers keeps rule, file, message and '
      'fingerprint', () {
    final report = _report('path_ice40_violated');
    final a = _results(writer.nextpnr(report, resolver: _resolver)).single;
    final b = _results(
      writer.nextpnr(_rerun(report, 3.25), resolver: _resolver),
    ).single;
    for (final key in ['ruleId', 'message', 'partialFingerprints']) {
      expect(b[key], a[key], reason: key);
    }
    expect(_uri(b), _uri(a));
    expect(
      (b['properties']! as Map)['achievedMhz'],
      isNot((a['properties']! as Map)['achievedMhz']),
    );
  });

  test('the fingerprint is the signature of rule, endpoint and clock', () {
    final report = _report('path_ecp5_violated');
    final result = _results(writer.nextpnr(report, resolver: _resolver)).first;
    final clock = (result['properties']! as Map)['clock']! as String;
    expect(
      (result['partialFingerprints']! as Map)[kFlowSarifFingerprintKey],
      CruxSignature.compute([kFlowTimingPathRule, end, clock], ''),
    );
  });

  test('without a resolver: tool names and no locations', () {
    final result = _results(
      writer.nextpnr(_report('path_gowin_violated')),
    ).single;
    expect(result.containsKey('locations'), isFalse);
    final message = (result['message']! as Map)['text']! as String;
    expect(message, contains('sum_q_DFF_Q'));
  });

  test('a failing clock with no path is reported by clock', () {
    final log = writer.nextpnr(
      const NextpnrReport(
        clocks: [
          NextpnrClockFrequency(
            clock: 'clk',
            achievedMhz: 10,
            constraintMhz: 20,
          ),
        ],
        criticalPaths: [],
        utilization: {},
      ),
    );
    final result = _results(log).single;
    expect(result['ruleId'], kFlowClockConstraintRule);
    expect(
      (result['message']! as Map)['text'],
      'Clock clk misses its constraint.',
    );
  });

  test('the log is SARIF 2.1.0 with both rules and the source root', () {
    final log = writer.nextpnr(_report('path_ice40_violated'));
    expect(log['version'], '2.1.0');
    final run = (log['runs']! as List).single! as Map<String, Object?>;
    final driver =
        (run['tool']! as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    expect(driver['name'], 'EDACrux Flow');
    expect(driver['version'], '1.2.0');
    expect(
      (driver['rules']! as List).map((r) => (r! as Map)['id']),
      [kFlowTimingPathRule, kFlowClockConstraintRule],
    );
    expect(
      (run['originalUriBaseIds']! as Map).keys,
      [kFlowSarifSourceRoot],
    );
    // Every rule id names its tool, so a consumer does not prefix its own.
    for (final r in _results(log)) {
      expect(r['ruleId'], contains('/'));
    }
  });

  test('no output names a machine path', () {
    for (final name in [
      for (final met in cases.keys) met.replaceFirst('_met', '_violated'),
    ]) {
      final text = FlowSarifWriter.encode(
        writer.nextpnr(_report(name), resolver: _resolver),
      );
      expect(text, isNot(contains('/Users/')));
      expect(text, isNot(contains('/home/')));
      expect(text, isNot(contains('file:')));
      expect(text, isNot(contains('<yosys-share>')));
      expect(text, endsWith('}\n'));
    }
  });

  group('relativeUri', () {
    const rooted = FlowSarifWriter(sourceRoot: '/work/soc');

    test('a relative span file is kept, in forward slashes', () {
      expect(rooted.relativeUri('rtl/top.v'), 'rtl/top.v');
      expect(rooted.relativeUri(r'rtl\top.v'), 'rtl/top.v');
      expect(rooted.relativeUri('./rtl/top.v'), 'rtl/top.v');
    });

    test('an absolute file inside the root becomes relative', () {
      expect(rooted.relativeUri('/work/soc/rtl/top.v'), 'rtl/top.v');
      expect(
        const FlowSarifWriter(
          sourceRoot: r'C:\work\soc',
        ).relativeUri(r'C:\work\soc\rtl\top.v'),
        'rtl/top.v',
      );
    });

    test('anything else has no URI', () {
      expect(rooted.relativeUri('/elsewhere/top.v'), isNull);
      expect(const FlowSarifWriter().relativeUri('/work/soc/top.v'), isNull);
      expect(rooted.relativeUri('../top.v'), isNull);
      expect(rooted.relativeUri('rtl/../../top.v'), isNull);
      expect(rooted.relativeUri(''), isNull);
      expect(rooted.relativeUri('.'), isNull);
      expect(rooted.relativeUri('a\x00b'), isNull);
    });

    test('a character a URI cannot hold is escaped', () {
      expect(rooted.relativeUri('rtl/my top#1.v'), 'rtl/my%20top%231.v');
    });
  });
}
