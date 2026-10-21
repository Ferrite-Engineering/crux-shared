// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

/// Mutations of real inputs: truncation, byte flips, spliced junk, repeated
/// brackets, huge numbers, and the JSON tokens a reader must not trust.
List<String> _mutants(String seed, Random random, int count) {
  final junk = [
    '[',
    '{',
    ']',
    '}',
    '"',
    r'\',
    ':',
    ',',
    '1e999',
    '-1e999',
    'null',
    'true',
    '"x"',
    '-0',
    '1e-400',
    '9' * 400,
    '\u0000',
    '\uFFFF',
    "'",
    '|',
    '\n',
  ];
  return [
    for (var i = 0; i < count; i++)
      switch (random.nextInt(6)) {
        0 => seed.substring(0, random.nextInt(seed.length + 1)),
        1 => _flip(seed, random),
        2 => _splice(seed, junk[random.nextInt(junk.length)], random),
        3 => _splice(seed, '[' * (50 + random.nextInt(200)), random),
        4 => _splice(
          _splice(seed, junk[random.nextInt(junk.length)], random),
          junk[random.nextInt(junk.length)],
          random,
        ),
        _ => String.fromCharCodes(
          List.generate(random.nextInt(64), (_) => random.nextInt(0x7F)),
        ),
      },
  ];
}

String _flip(String s, Random random) {
  if (s.isEmpty) return s;
  final units = s.codeUnits.toList();
  for (var i = 0; i < 1 + random.nextInt(8); i++) {
    units[random.nextInt(units.length)] = random.nextInt(0x80);
  }
  return String.fromCharCodes(units);
}

String _splice(String s, String insert, Random random) {
  final at = random.nextInt(s.length + 1);
  return '${s.substring(0, at)}$insert${s.substring(at)}';
}

/// Runs [body], allowing only [FlowReadException] out.
void _onlyReadErrors(String input, void Function() body) {
  try {
    body();
  } on FlowReadException {
    // The documented failure.
  } on Object catch (e) {
    fail('${e.runtimeType} escaped on input of ${input.length} chars: $e');
  }
}

void main() {
  final random = Random(20261021);
  final report = File(
    'test/fixtures/nextpnr/path_gatemate_met/report.json',
  ).readAsStringSync();
  final log = File(
    'test/fixtures/nextpnr/rescreen_ice40/pnr.log',
  ).readAsStringSync();
  const metrics =
      '{"timing__setup__ws__corner:nom_tt": -0.12, "route__drc_errors": 0, '
      '"power__total": 0.0013, "flow__status": "done"}';

  test('NextpnrReportReader throws only FlowReadException', () {
    for (final input in _mutants(report, random, 400)) {
      _onlyReadErrors(input, () => const NextpnrReportReader().parse(input));
    }
  });

  test('NextpnrLogReader never throws on a bounded log', () {
    for (final input in _mutants(log, random, 400)) {
      final parsed = const NextpnrLogReader().parse(input);
      expect(FlowVerdict.values, contains(parsed.verdict));
    }
  });

  test('MetricsDocument throws only FlowReadException', () {
    for (final input in _mutants(metrics, random, 400)) {
      _onlyReadErrors(input, () {
        final doc = MetricsDocument.parse(input);
        // Whatever survives can be aggregated and compared.
        aggregateMetrics(doc.values);
        MetricDiff.fromMetrics(doc.values, doc.values).renderMarkdown(
          MetricDiffVerbosity.all,
        );
      });
    }
  });

  test('MetricKey and SrcSpan parse anything without throwing', () {
    const seeds = [
      'timing__setup__ws__corner:nom_tt_025C_1v80',
      r'C:\rtl\top.v:12.3-14.5|path_adder.v:16.14-16.27',
    ];
    for (final seed in seeds) {
      for (final input in _mutants(seed, random, 400)) {
        final key = MetricKey.tryParse(input);
        if (key != null) expect(MetricKey.tryParse(key.format()), isNotNull);
        for (final span in SrcSpan.parseAll(input)) {
          expect(span.startLine, greaterThanOrEqualTo(1));
          expect(SrcSpan.tryParse(span.format()), span);
        }
      }
    }
  });

  test('the model fromJson factories throw only FlowReadException', () {
    final run = jsonEncode({
      'ref': {
        'kind': 'nextpnr',
        'root': '/w',
        'tag': 't',
        'reader_version': '0.11',
        'verified': true,
      },
      'verdict': 'met',
      'timing': [
        {
          'rank': 1,
          'startpoint': 'a',
          'endpoint': 'b',
          'delay_ps': 1,
          'delay_ns': 0.001,
          'origin': 'nextpnr_report',
          'segments': [
            {
              'raw_type': 'logic',
              'from_cell': 'a',
              'to_cell': 'b',
              'delay_ps': 1,
              'delay_ns': 0.001,
            },
          ],
        },
      ],
      'metrics': {'a': 1},
    });
    for (final input in _mutants(run, random, 400)) {
      _onlyReadErrors(input, () {
        final Object? json;
        try {
          json = jsonDecode(input);
        } on FormatException {
          return;
        }
        if (json is Map<String, Object?>) FlowRun.fromJson(json);
      });
    }
  });
}
