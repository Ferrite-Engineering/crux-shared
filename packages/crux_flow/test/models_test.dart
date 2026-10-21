// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

/// Through real JSON text, as a stored run is read back.
Map<String, Object?> _viaText(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

const _segment = TimingSegment(
  type: TimingSegmentType.routing,
  rawType: 'routing',
  fromCell: 'src_a_SB_DFF_Q_23_DFFLC',
  fromPort: 'O',
  toCell: 'sum_q_SB_DFF_Q_DFFLC',
  toPort: 'I0',
  net: 'src_a[7]',
  delayPs: 1922,
  delayNs: 1.9220000505447388,
  sources: ['path_adder.v:10.14-10.19'],
);

const _skew = TimingSegment(
  type: TimingSegmentType.other,
  rawType: 'clk-skew',
  fromCell: r'$auto$ff.cc:337:slice$139',
  toCell: r'$auto$ff.cc:337:slice$204',
  delayPs: 481,
  delayNs: 0.48100000619888306,
);

const _path = TimingPath(
  rank: 1,
  clockFrom: 'clk',
  fromEdge: ClockEdge.rising,
  clockTo: 'clk',
  toEdge: ClockEdge.falling,
  startpoint: 'src_a_SB_DFF_Q_23_DFFLC',
  endpoint: 'sum_q_SB_DFF_Q_DFFLC',
  slackPs: -120,
  delayPs: 2403,
  delayNs: 2.403000050783157,
  segments: [_skew, _segment],
  origin: TimingPathOrigin.nextpnrReport,
);

const _step = FlowStep(
  ordinal: 55,
  id: 'OpenROAD.STAPostPNR',
  tool: 'openroad',
  dir: '55-openroad-stapostpnr',
  status: FlowStepStatus.completed,
  runtime: Duration(milliseconds: 12345),
  logPath: '55-openroad-stapostpnr/openroad-stapostpnr.log',
  metricsOut: '55-openroad-stapostpnr/or_metrics_out.json',
);

final _run = FlowRun(
  ref: const FlowRunRef(
    kind: FlowKind.librelane,
    root: '/work/runs/RUN_1',
    tag: 'RUN_1',
    readerVersion: '3.0',
    verified: true,
  ),
  verdict: FlowVerdict.violated,
  steps: const [
    _step,
    FlowStep(
      ordinal: 56,
      id: 'Magic.DRC',
      tool: 'magic',
      dir: '56-magic-drc',
      status: FlowStepStatus.notStarted,
    ),
  ],
  metrics: const {
    'timing__setup__ws': -0.12,
    'route__drc_errors': 0,
    'design__lvs_error__count': null,
    'flow__status': 'done',
    'flow__ok': true,
  },
  timing: const [_path],
  artifacts: const {'gds': 'final/gds/top.gds'},
  toolVersions: const {'librelane': '3.0.16'},
  startedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  finishedAt: DateTime.utc(2026, 1, 2, 4, 5, 6),
);

void main() {
  group('enums keep their wire names', () {
    test('FlowVerdict', () {
      expect(
        FlowVerdict.values.map((v) => v.wireName),
        ['met', 'violated', 'stopped', 'not_run', 'unrecognised'],
      );
      for (final v in FlowVerdict.values) {
        expect(FlowVerdict.fromWireName(v.wireName), v);
        expect(v.isMet, v == FlowVerdict.met);
      }
      expect(
        () => FlowVerdict.fromWireName('passed'),
        throwsA(isA<FlowReadException>()),
      );
    });

    test('every token is telemetry-safe', () {
      final tokens = [
        ...FlowVerdict.values.map((v) => v.wireName),
        ...FlowKind.values.map((v) => v.wireName),
        ...FlowStepStatus.values.map((v) => v.wireName),
        ...MappingFidelity.values.map((v) => v.wireName),
        ...TimingPathOrigin.values.map((v) => v.wireName),
        ...ClockEdge.values.map((v) => v.wireName),
      ];
      for (final t in tokens) {
        expect(t, matches(RegExp(r'^[a-z0-9_]{1,64}$')));
      }
    });

    test('FlowKind, FlowStepStatus, MappingFidelity, origin and edge', () {
      for (final v in FlowKind.values) {
        expect(FlowKind.fromWireName(v.wireName), v);
      }
      for (final v in FlowStepStatus.values) {
        expect(FlowStepStatus.fromWireName(v.wireName), v);
      }
      for (final v in MappingFidelity.values) {
        expect(MappingFidelity.fromWireName(v.wireName), v);
      }
      for (final v in TimingPathOrigin.values) {
        expect(TimingPathOrigin.fromWireName(v.wireName), v);
      }
      for (final v in ClockEdge.values) {
        expect(ClockEdge.fromWireName(v.wireName), v);
      }
      for (final parse in <void Function()>[
        () => FlowKind.fromWireName('vivado'),
        () => FlowStepStatus.fromWireName('done'),
        () => MappingFidelity.fromWireName('exact'),
        () => TimingPathOrigin.fromWireName('sta'),
        () => ClockEdge.fromWireName('both'),
      ]) {
        expect(parse, throwsA(isA<FlowReadException>()));
      }
    });

    test('there is no exact mapping fidelity', () {
      expect(
        MappingFidelity.values.map((v) => v.name),
        ['register', 'statement', 'span', 'unmapped'],
      );
    });

    test('segment types read the tool words, unknown ones as other', () {
      expect(
        TimingSegmentType.fromToolWord('clk-to-q'),
        TimingSegmentType.clkToQ,
      );
      expect(
        TimingSegmentType.fromToolWord('routing'),
        TimingSegmentType.routing,
      );
      expect(TimingSegmentType.fromToolWord('logic'), TimingSegmentType.logic);
      expect(TimingSegmentType.fromToolWord('setup'), TimingSegmentType.setup);
      expect(TimingSegmentType.fromToolWord('hold'), TimingSegmentType.hold);
      expect(
        TimingSegmentType.fromToolWord('clk-skew'),
        TimingSegmentType.other,
      );
      expect(TimingSegmentType.fromToolWord('source'), TimingSegmentType.other);
      expect(TimingSegmentType.fromToolWord('other'), TimingSegmentType.other);
    });
  });

  group('JSON round trip and value equality', () {
    test('FlowRun', () {
      final back = FlowRun.fromJson(_viaText(_run.toJson()));
      expect(back, _run);
      expect(back.hashCode, _run.hashCode);
      expect(back.metrics.keys, _run.metrics.keys);
      expect('$back', contains('RUN_1'));
    });

    test('a minimal FlowRun', () {
      const run = FlowRun(
        ref: FlowRunRef(
          kind: FlowKind.nextpnr,
          root: '/w',
          tag: 't',
          readerVersion: '0.11',
          verified: false,
        ),
        verdict: FlowVerdict.notRun,
      );
      expect(run.toJson().keys, ['ref', 'verdict']);
      expect(FlowRun.fromJson(_viaText(run.toJson())), run);
    });

    test('times compare by instant, not by zone', () {
      final local = FlowRun(
        ref: _run.ref,
        verdict: _run.verdict,
        startedAt: DateTime.utc(2026).toLocal(),
      );
      final utc = FlowRun(
        ref: _run.ref,
        verdict: _run.verdict,
        startedAt: DateTime.utc(2026),
      );
      expect(local, utc);
      expect(local, isNot(FlowRun(ref: _run.ref, verdict: _run.verdict)));
    });

    test('FlowStep, TimingPath, TimingSegment, FlowRunRef', () {
      expect(FlowStep.fromJson(_viaText(_step.toJson())), _step);
      expect(TimingPath.fromJson(_viaText(_path.toJson())), _path);
      expect(TimingSegment.fromJson(_viaText(_skew.toJson())), _skew);
      expect(TimingSegment.fromJson(_viaText(_segment.toJson())), _segment);
      expect(FlowRunRef.fromJson(_viaText(_run.ref.toJson())), _run.ref);
      expect(
        TimingPath.fromJson(_viaText(_path.toJson())).hashCode,
        _path.hashCode,
      );
      expect(FlowStep.fromJson(_step.toJson()).hashCode, _step.hashCode);
      expect('$_step $_path $_segment ${_run.ref}', isNotEmpty);
    });

    test('RtlMapping and SrcSpan', () {
      const mapping = RtlMapping(
        fidelity: MappingFidelity.register,
        register: 'sum_q',
        spans: [
          SrcSpan(
            file: 'path_adder.v',
            startLine: 12,
            startCol: 3,
            endLine: 12,
            endCol: 20,
          ),
          SrcSpan(file: 'path_adder.v', startLine: 16),
        ],
      );
      final back = RtlMapping.fromJson(_viaText(mapping.toJson()));
      expect(back, mapping);
      expect(back.hashCode, mapping.hashCode);
      expect(
        RtlMapping.fromJson(_viaText(RtlMapping.unmapped.toJson())),
        RtlMapping.unmapped,
      );
      expect('$mapping', contains('sum_q'));
    });

    test('a changed field breaks equality', () {
      expect(
        _path,
        isNot(
          TimingPath(
            rank: 2,
            startpoint: _path.startpoint,
            endpoint: _path.endpoint,
            delayPs: _path.delayPs,
            delayNs: _path.delayNs,
            segments: _path.segments,
            origin: _path.origin,
          ),
        ),
      );
      expect(
        FlowRun(ref: _run.ref, verdict: FlowVerdict.met),
        isNot(FlowRun(ref: _run.ref, verdict: FlowVerdict.violated)),
      );
    });
  });

  group('fromJson refuses wrong shapes with FlowReadException', () {
    final bad = <String, void Function()>{
      'run without ref': () => FlowRun.fromJson(const {'verdict': 'met'}),
      'unknown verdict': () => FlowRun.fromJson({
        'ref': _run.ref.toJson(),
        'verdict': 'green',
      }),
      'nested metric': () => FlowRun.fromJson({
        'ref': _run.ref.toJson(),
        'verdict': 'met',
        'metrics': const {
          'a': [1],
        },
      }),
      'infinite metric': () => FlowRun.fromJson({
        'ref': _run.ref.toJson(),
        'verdict': 'met',
        'metrics': const {'a': double.infinity},
      }),
      'bad time': () => FlowRun.fromJson({
        'ref': _run.ref.toJson(),
        'verdict': 'met',
        'started_at': 'yesterday',
      }),
      'step ordinal as string': () => FlowStep.fromJson({
        ..._step.toJson(),
        'ordinal': '55',
      }),
      'segment delay as string': () => TimingSegment.fromJson({
        ..._segment.toJson(),
        'delay_ns': 'fast',
      }),
      'segment in a list of numbers': () => TimingPath.fromJson({
        ..._path.toJson(),
        'segments': const [1],
      }),
      'span line missing': () => SrcSpan.fromJson(const {'file': 'a.v'}),
      'artifacts not strings': () => FlowRun.fromJson({
        'ref': _run.ref.toJson(),
        'verdict': 'met',
        'artifacts': const {'gds': 3},
      }),
      'ref verified as string': () => FlowRunRef.fromJson({
        ..._run.ref.toJson(),
        'verified': 'yes',
      }),
    };
    for (final MapEntry(:key, :value) in bad.entries) {
      test(key, () {
        expect(value, throwsA(isA<FlowReadException>()));
        expect(value, throwsA(isA<FormatException>()));
      });
    }

    test('a nested error names its path', () {
      expect(
        () => FlowRun.fromJson({
          'ref': _run.ref.toJson(),
          'verdict': 'met',
          'steps': const [
            {'ordinal': 'x'},
          ],
        }),
        throwsA(
          isA<FlowReadException>().having(
            (e) => e.message,
            'message',
            contains('steps[0]'),
          ),
        ),
      );
    });

    test('a long offending value is not echoed whole', () {
      final huge = 'x' * 100000;
      try {
        FlowVerdict.fromWireName(huge);
        fail('accepted');
      } on FlowReadException catch (e) {
        expect(e.message.length, lessThan(200));
        expect(e.failure, FlowReadFailure.malformed);
        expect('$e', contains('malformed'));
      }
    });
  });
}
