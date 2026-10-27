// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A run directory can hold entries that are not regular files: a link to a
/// device that never ends (`/dev/zero` reports a length of zero), or a named
/// pipe that blocks the first read. No reader may hang or fill memory on one.
@TestOn('mac-os || linux')
@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:crux_flow/crux_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory _temp() {
  final t = Directory.systemTemp.createTempSync('crux_flow_special_');
  addTearDown(() => t.deleteSync(recursive: true));
  return Directory(t.resolveSymbolicLinksSync());
}

/// A named pipe at [path]; nothing ever writes to it.
void _fifo(String path) {
  final made = Process.runSync('mkfifo', <String>[path]);
  if (made.exitCode != 0) fail('mkfifo failed: ${made.stderr}');
}

void main() {
  test(
    'a step runtime.txt linked to /dev/zero is no runtime, read at once',
    () {
      final root = _temp().path;
      final step = Directory(p.join(root, '01-yosys-synthesis'))..createSync();
      File(p.join(step.path, 'state_out.json')).writeAsStringSync('{}');
      Link(p.join(step.path, 'runtime.txt')).createSync('/dev/zero');

      final steps = const LibreLaneStepReader().read(root);

      expect(steps.single.runtime, isNull);
    },
  );

  test('a step runtime.txt that is a named pipe is no runtime', () {
    final root = _temp().path;
    final step = Directory(p.join(root, '01-yosys-synthesis'))..createSync();
    File(p.join(step.path, 'state_out.json')).writeAsStringSync('{}');
    _fifo(p.join(step.path, 'runtime.txt'));

    final steps = const LibreLaneStepReader().read(root);

    expect(steps.single.runtime, isNull);
  });

  test('a metrics file that is a device or a pipe is refused unread', () async {
    final root = _temp().path;
    final pipe = p.join(root, 'metrics.json');
    _fifo(pipe);

    await expectLater(
      MetricsDocument.readFile('/dev/zero'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      MetricsDocument.readFile(pipe),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'an OpenSTA listing that is a device or a pipe is refused unread',
    () async {
      final root = _temp().path;
      final pipe = p.join(root, 'max.rpt');
      _fifo(pipe);

      await expectLater(
        const OpenStaReportReader().readFile('/dev/zero'),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        const OpenStaReportReader().readFile(pipe),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'a run whose logs are pipes reads as a run with unreadable logs',
    () async {
      final root = _temp().path;
      File(p.join(root, 'resolved.json')).writeAsStringSync('{}');
      Directory(p.join(root, 'final')).createSync();
      _fifo(p.join(root, 'flow.log'));
      _fifo(p.join(root, 'error.log'));
      _fifo(p.join(root, 'final', 'metrics.json'));

      final reading = await LibreLaneReaders.standard().read(root);

      expect(reading.run.ref.root, root);
    },
  );
}
