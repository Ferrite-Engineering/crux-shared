// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The same behaviour across real processes, which is what the lock is for:
// one process cannot test that another holds a lock, and the operating system
// releasing it when a process is killed is the stale-instance recovery.

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String kernel;
  late String dart;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('csi');
    dart = _dartExecutable();
    kernel = p.join(tmp.path, 'instance.dill');
    final compiled = await Process.run(dart, [
      'compile',
      'kernel',
      p.join('test', 'support', 'instance_main.dart'),
      '-o',
      kernel,
    ]);
    if (compiled.exitCode != 0) {
      fail('could not compile the helper:\n${compiled.stderr}');
    }
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final transports = [
    if (!Platform.isWindows) 'unix',
    'tcp',
  ];

  for (final transport in transports) {
    group(transport, () {
      late String dir;
      var run = 0;

      setUp(() => dir = p.join(tmp.path, '${transport[0]}${run++}'));

      Future<_Instance> launch({
        int expected = 0,
        int holdMs = 30000,
        String? link,
      }) async => _Instance(
        await Process.start(dart, [
          kernel,
          dir,
          transport,
          '$expected',
          '$holdMs',
          ?link,
        ]),
      );

      test('a second process delivers its link and exits', () async {
        final first = await launch(expected: 1);
        expect(await first.nextLine(), 'claim primary');

        final second = await launch(link: 'example://open?a=1');

        expect(await second.nextLine(), 'claim delivered');
        expect(await second.exitCode, 0);
        expect(await first.nextLine(), 'link example://open?a=1');
        expect(await first.nextLine(), 'closed');
        expect(await first.exitCode, 0);
      });

      test('with no running instance a launch becomes it', () async {
        final only = await launch(link: 'example://open?a=2');

        expect(await only.nextLine(), 'claim primary');
        expect(await only.nextLine(), 'closed');
        expect(await only.exitCode, 0);
      });

      test('a killed instance is replaced by the next launch', () async {
        final first = await launch(expected: 99);
        expect(await first.nextLine(), 'claim primary');
        first.process.kill(ProcessSignal.sigkill);
        await first.exitCode;

        final next = await launch(expected: 1);
        expect(await next.nextLine(), 'claim primary');
        final third = await launch(link: 'example://open?a=3');
        expect(await third.nextLine(), 'claim delivered');
        expect(await next.nextLine(), 'link example://open?a=3');
        expect(await next.exitCode, 0);
      });

      test('concurrent launches elect one instance', () async {
        const count = 5;
        final launches = await Future.wait([
          for (var i = 0; i < count; i++)
            launch(expected: count - 1, link: 'example://open?n=$i'),
        ]);
        final outcomes = await Future.wait(
          launches.map((l) => l.nextLine()),
        );

        expect(outcomes.where((o) => o == 'claim primary'), hasLength(1));
        expect(
          outcomes.where((o) => o == 'claim delivered'),
          hasLength(count - 1),
        );
        final primary = launches[outcomes.indexOf('claim primary')];
        final links = <String>{};
        for (var i = 0; i < count - 1; i++) {
          links.add(await primary.nextLine());
        }
        expect(links, hasLength(count - 1));
        expect(links.every((l) => l.startsWith('link example://')), isTrue);
        for (final l in launches) {
          expect(await l.exitCode, 0);
        }
      });
    });
  }
}

class _Instance {
  _Instance(this.process)
    : _lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ) {
    unawaited(process.stderr.drain<void>());
  }

  final Process process;
  final StreamIterator<String> _lines;

  Future<String> nextLine() async {
    final more = await _lines.moveNext().timeout(const Duration(seconds: 30));
    if (!more) return '<exited>';
    return _lines.current;
  }

  Future<int> get exitCode =>
      process.exitCode.timeout(const Duration(seconds: 30));
}

/// The `dart` executable. Under `dart test` that is the running executable;
/// under `flutter test` it is the engine's test shell, and the SDK bundled
/// with Flutter is found beside it.
String _dartExecutable() {
  final running = Platform.resolvedExecutable;
  final name = p.basenameWithoutExtension(running);
  if (name == 'dart') return running;
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  var dir = p.dirname(running);
  while (true) {
    final candidate = p.join(dir, 'dart-sdk', 'bin', exe);
    if (File(candidate).existsSync()) return candidate;
    final parent = p.dirname(dir);
    if (parent == dir) return exe;
    dir = parent;
  }
}
