// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:test/test.dart';

/// Whether a real `yosys` can be spawned on this machine.
bool _yosysOnPath() {
  try {
    return Process.runSync('yosys', const ['-V']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Elaborates `rtl/<design>.v` the way the fixtures were made and returns
/// the register set of the result.
Future<RtlRegisterSet> _elaborate(String design, Directory temp) async {
  final out = '${temp.path}/$design.json';
  final script =
      'read_verilog "$design.v"; hierarchy -check -top $design; proc; '
      'write_json "$out"';
  final result = await Process.run(
    'yosys',
    ['-q', '-p', script],
    workingDirectory: 'test/fixtures/nextpnr/rtl',
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return await RtlRegisterSet.read(out);
}

Map<String, List<int>> _shape(RtlRegisterSet set) => {
  for (final r in set.registers)
    r.name: [
      for (final s in [...r.declaration, ...r.assignments, ...r.blocks])
        s.startLine,
    ],
};

void main() {
  final skip = _yosysOnPath() ? false : 'yosys is not on PATH';
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('crux_flow_live_'));
  tearDown(() => temp.deleteSync(recursive: true));

  for (final design in ['path_adder', 'top']) {
    test(
      'a live elaboration of $design.v reads as the committed one does',
      () async {
        final live = await _elaborate(design, temp);
        final committed = await RtlRegisterSet.read(
          'test/fixtures/elaboration/$design.json',
        );
        expect(_shape(live), _shape(committed));
        expect(live.sourceFiles, committed.sourceFiles);
      },
      skip: skip,
    );
  }
}
