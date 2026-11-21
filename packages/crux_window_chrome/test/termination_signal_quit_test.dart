// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_window_chrome/src/exit_on_termination_signal.dart';
import 'package:crux_window_chrome/src/termination_signal_quit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminationSignalQuit', () {
    late List<int> exits;
    late int requests;

    TerminationSignalQuit quitWith(
      Future<bool> Function() answer, {
      Duration deadline = const Duration(milliseconds: 50),
    }) {
      exits = <int>[];
      requests = 0;
      return TerminationSignalQuit(
        requestExit: () {
          requests++;
          return answer();
        },
        exitProcess: exits.add,
        deadline: deadline,
      );
    }

    test('asks once and leaves the exit to the engine when the app '
        'agrees', () async {
      final quit = quitWith(() async => true, deadline: const Duration(days: 1))
        ..onSignal(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(quit.quitting, isTrue);
      expect(requests, 1);
      expect(exits, isEmpty);
    });

    test('ends the process at the deadline if the engine never does', () async {
      quitWith(() async => true).onSignal(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(exits, [0]);
    });

    test('ends the process at once when a listener declines', () async {
      quitWith(
        () async => false,
        deadline: const Duration(days: 1),
      ).onSignal(ProcessSignal.sighup);
      await pumpEventQueue();
      expect(requests, 1);
      expect(exits, [0]);
    });

    test('a failed request is left to the deadline', () async {
      final quit = quitWith(() async => throw StateError('in progress'))
        ..onSignal(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(exits, isEmpty, reason: 'a quit in flight gets its time');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(exits, [0]);
      expect(quit.quitting, isTrue);
    });

    test('a hung request ends at the deadline, and a second signal starts '
        'nothing', () async {
      final quit = quitWith(() => Completer<bool>().future)
        ..onSignal(ProcessSignal.sigterm)
        ..onSignal(ProcessSignal.sigterm)
        ..onSignal(ProcessSignal.sighup);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(requests, 1);
      expect(exits, [0]);
      quit.onSignal(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(requests, 1);
      expect(exits, [0], reason: 'the process is ended once');
    });

    test('watches SIGTERM and SIGHUP', () {
      expect(kTerminationSignals, [
        ProcessSignal.sigterm,
        ProcessSignal.sighup,
      ]);
    });
  });

  group('routeTerminationSignalsThroughExitRequest', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(debugResetTerminationSignalQuit);

    test('watches only where the signals exist', () async {
      expect(
        routeTerminationSignalsThroughExitRequest(),
        Platform.isLinux || Platform.isMacOS,
      );
      await debugResetTerminationSignalQuit();
    });

    test('installs once', () {
      final first = installTerminationSignalQuit(
        requestExit: () async => true,
        signals: const <ProcessSignal>[],
      );
      final second = installTerminationSignalQuit(
        requestExit: () async => false,
        signals: const <ProcessSignal>[],
      );
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('sends the cancelable exit request a window close sends', () async {
      // The test binding answers a cancelable exit with "cancel" and throws
      // on a required one, so a clean "not agreed" proves the request was
      // ServicesBinding.exitApplication(AppExitType.cancelable): every exit
      // listener is asked, none is skipped.
      expect(await requestEngineExitForTerminationSignal(), isFalse);
    });

    test('a decline from the app ends the process at once', () async {
      final exits = <int>[];
      installTerminationSignalQuit(
        requestExit: requestEngineExitForTerminationSignal,
        exitProcess: exits.add,
        deadline: const Duration(days: 1),
        signals: const <ProcessSignal>[],
      )!.onSignal(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(exits, [0]);
    });
  });

  group('a real signal to a child process', () {
    final dart = _dartExecutable();
    final packages = _packageConfig();
    final skip = Platform.isWindows
        ? 'Windows has no SIGTERM or SIGHUP to watch'
        : dart == null || packages == null
        ? 'no Dart executable or package config found beside this test'
        : false;

    Future<(int, List<String>)> run(
      String mode,
      File marker,
      List<ProcessSignal> signals,
    ) async {
      final process = await Process.start(dart!, [
        '--packages=$packages',
        'test/support/termination_signal_child.dart',
        marker.path,
        mode,
      ]);
      final lines = <String>[];
      final ready = Completer<void>();
      final requested = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            lines.add(line);
            if (line == 'ready' && !ready.isCompleted) ready.complete();
            if (line == 'request' && !requested.isCompleted) {
              requested.complete();
            }
          });
      final stderrDone = process.stderr.drain<void>();
      await ready.future.timeout(const Duration(seconds: 60));
      process.kill(signals.first);
      await requested.future.timeout(const Duration(seconds: 10));
      signals.skip(1).forEach(process.kill);
      final code = await process.exitCode.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -999;
        },
      );
      await stderrDone;
      return (code, lines);
    }

    test(
      'SIGTERM runs the exit request, which removes the marker, then exits 0',
      () async {
        final dir = Directory.systemTemp.createTempSync('crux_sigterm_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final marker = File('${dir.path}/session.running');
        final (code, lines) = await run('decline', marker, [
          ProcessSignal.sigterm,
        ]);
        expect(code, 0, reason: 'not killed by the default action');
        expect(lines.where((l) => l == 'request'), hasLength(1));
        expect(marker.existsSync(), isFalse);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'SIGHUP takes the same path',
      () async {
        final dir = Directory.systemTemp.createTempSync('crux_sighup_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final marker = File('${dir.path}/session.running');
        final (code, lines) = await run('decline', marker, [
          ProcessSignal.sighup,
        ]);
        expect(code, 0);
        expect(lines.where((l) => l == 'request'), hasLength(1));
        expect(marker.existsSync(), isFalse);
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a hung quit ends at the deadline; repeated signals ask only once',
      () async {
        final dir = Directory.systemTemp.createTempSync('crux_sighang_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final marker = File('${dir.path}/session.running');
        final (code, lines) = await run('hang', marker, [
          ProcessSignal.sigterm,
          ProcessSignal.sigterm,
          ProcessSignal.sighup,
        ]);
        expect(code, 0, reason: 'ended by the deadline, not the signals');
        expect(lines.where((l) => l == 'request'), hasLength(1));
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}

/// The `dart` executable of the SDK running this test: beside the
/// `flutter_tester` that runs it, under `bin/cache/dart-sdk`.
String? _dartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (root != null) '$root/bin/cache/dart-sdk/bin/$name',
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    candidates.add('${dir.path}/dart-sdk/bin/$name');
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// The workspace's package config, found from the package directory up.
String? _packageConfig() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) return config.path;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}
