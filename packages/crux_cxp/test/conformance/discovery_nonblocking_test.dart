// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The slow disk below models the asynchronous dart:io API that discovery
// uses on purpose; the avoid_slow_async_io lint would have it call the
// synchronous one.
// ignore_for_file: avoid_slow_async_io

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp/src/process_liveness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

/// Discovery scans every couple of seconds for the life of every product,
/// on the isolate that started it — the UI isolate. A scan that holds that
/// isolate is a frame that is not drawn, on every install, whatever the user
/// is doing. These tests pin that a scan holds it only between one file
/// operation and the next, that scans never pile up, and that a pid probe is
/// a system call rather than a process launch.
///
/// The slow disk below is `dart:io`'s own override seam: every file and
/// directory operation under the manifest directory takes [_slowDiskDelay].
/// Its asynchronous calls wait that out on a timer; its synchronous calls
/// hold the isolate for it, as a real slow disk would. A synchronous call
/// anywhere in a scan therefore shows up as an event-loop stall at least
/// that long.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_nonblocking_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  File writeManifest(
    String peerId, {
    required int port,
    DateTime? startedAt,
    String product = 'netcrux',
  }) => File(p.join(tempDir.path, '$peerId.json'))
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'identity': <String, Object?>{
          'peer_id': peerId,
          'product_name': product,
          'product_version': '0.0.0',
          'capabilities': <String>[],
        },
        'host': '127.0.0.1',
        'port': port,
        'started_at': (startedAt ?? DateTime.now())
            .toUtc()
            .millisecondsSinceEpoch,
      }),
    );

  Future<int> deadPid() async {
    final proc = await Process.start('sh', <String>['-c', 'exit 0']);
    await proc.exitCode;
    return proc.pid;
  }

  group('a scan on a slow disk', () {
    test(
      'holds the event loop for less than one file operation takes, and '
      'still reaches every answer',
      () async {
        final livePeer = 'netcrux-$pid-1';
        writeManifest(livePeer, port: 65301);
        final stale = writeManifest(
          'lintcrux-$pid-2',
          port: 65302,
          product: 'lintcrux',
          startedAt: DateTime.now().subtract(const Duration(hours: 1)),
        );
        final dead = Platform.isWindows
            ? null
            : writeManifest(
                'simcrux-${await deadPid()}-3',
                port: 65303,
                product: 'simcrux',
              );
        final ancientGarbage = File(p.join(tempDir.path, 'ancient.json'))
          ..writeAsStringSync('{not json')
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 2)),
          );
        final freshGarbage = File(p.join(tempDir.path, 'fresh.json'))
          ..writeAsStringSync('{not json');
        final orphan = File(p.join(tempDir.path, 'x.json.1-0.tmp'))
          ..writeAsStringSync('{"partial": ')
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(hours: 1)),
          );

        final disk = _SlowDisk(tempDir.path);
        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          // One scan — the one start() awaits — is what is measured.
          scanInterval: const Duration(hours: 1),
        );
        addTearDown(discovery.stop);
        final probe = _LoopProbe()..start();
        addTearDown(probe.stop);

        await disk.run(discovery.start);
        probe.stop();

        expect(
          disk.unmodelled,
          isEmpty,
          reason: 'the scan used a file operation the slow disk does not model',
        );
        expect(
          disk.fileOperations,
          greaterThan(0),
          reason: 'the listing must hand the scan files on the slow disk',
        );
        expect(discovery.peers.map((m) => m.identity.peerId), [livePeer]);
        expect(stale.existsSync(), isTrue);
        if (dead != null) expect(dead.existsSync(), isFalse);
        expect(ancientGarbage.existsSync(), isFalse);
        expect(freshGarbage.existsSync(), isTrue);
        expect(orphan.existsSync(), isFalse);
        expect(
          probe.longest,
          lessThan(_slowDiskDelay ~/ 2),
          reason:
              'the event loop was held for ${probe.longest}; a synchronous '
              'file operation on this disk holds it for $_slowDiskDelay',
        );
      },
    );

    test('skips a tick that falls due while it is running, rather than '
        'starting another', () async {
      writeManifest('netcrux-$pid-1', port: 65311);
      final disk = _SlowDisk(tempDir.path);
      final discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        selfPeerId: 'wavecrux-observer',
        // Dozens of ticks fall due during each scan on this disk.
        scanInterval: const Duration(milliseconds: 10),
      );
      addTearDown(discovery.stop);
      await disk.run(discovery.start);

      await pollUntil(
        () => disk.listings >= 3,
        reason: 'the timer must keep scanning',
        timeout: const Duration(seconds: 10),
      );
      expect(
        disk.mostListingsAtOnce,
        1,
        reason: 'no scan may begin while another is running',
      );
    });

    test('in flight when stop() is called, emits, reaps and reports nothing '
        'after it; start() then scans afresh', () async {
      final first = 'netcrux-$pid-1';
      writeManifest(first, port: 65321);
      final disk = _SlowDisk(tempDir.path);
      final discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        selfPeerId: 'wavecrux-observer',
        scanInterval: const Duration(milliseconds: 300),
      );
      addTearDown(discovery.stop);
      final events = <CxpDiscoveryEvent>[];
      discovery.events.listen(events.add);
      await disk.run(discovery.start);
      expect(discovery.peers.map((m) => m.identity.peerId), [first]);

      // What the next scan would act on, were it allowed to finish.
      final second = 'lintcrux-$pid-2';
      writeManifest(second, port: 65322, product: 'lintcrux');
      final dead = Platform.isWindows
          ? null
          : writeManifest(
              'simcrux-${await deadPid()}-3',
              port: 65323,
              product: 'simcrux',
            );

      await pollUntil(
        () => disk.listingsInFlight > 0,
        reason: 'a periodic scan must begin',
        interval: const Duration(milliseconds: 2),
      );
      await discovery.stop();
      // Longer than the abandoned scan would take to finish every step.
      await Future<void>.delayed(_slowDiskDelay * 10);

      expect(
        discovery.peers.map((m) => m.identity.peerId),
        [first],
        reason: 'a stopped discovery must not update its view',
      );
      expect(events.map((e) => e.added), [true]);
      if (dead != null) {
        expect(
          dead.existsSync(),
          isTrue,
          reason: 'a stopped discovery must not delete anything',
        );
      }

      await disk.run(discovery.start);
      expect(
        discovery.peers.map((m) => m.identity.peerId).toSet(),
        {first, second},
      );
      if (dead != null) expect(dead.existsSync(), isFalse);
    });
  });

  test(
    'a FIFO named like a manifest is passed over, not opened, and discovery '
    'goes on around it',
    () async {
      final fifo = p.join(tempDir.path, 'aaa-pipe.json');
      final made = await Process.run('mkfifo', <String>[fifo]);
      if (made.exitCode != 0) {
        markTestSkipped('mkfifo unavailable: ${made.stderr}');
        return;
      }
      final first = 'netcrux-$pid-1';
      writeManifest(first, port: 65331);
      final discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        selfPeerId: 'wavecrux-observer',
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);

      // Opening a FIFO for reading waits for a writer. Read synchronously, it
      // froze the isolate for good; read asynchronously, it would leave this
      // scan — and, since ticks never overlap, every scan — waiting forever.
      await discovery.start().timeout(const Duration(seconds: 5));
      expect(discovery.peers.map((m) => m.identity.peerId), [first]);

      final second = 'lintcrux-$pid-2';
      writeManifest(second, port: 65332, product: 'lintcrux');
      await pollUntil(
        () => discovery.peers.any((m) => m.identity.peerId == second),
        reason: 'later scans must complete with the FIFO still present',
      );
      expect(FileSystemEntity.typeSync(fifo), FileSystemEntityType.pipe);
    },
    skip: Platform.isWindows ? 'no FIFOs on Windows' : false,
  );

  group(
    'the pid probe',
    () {
      /// What discovery answered before, when it ran the `kill -0` command
      /// and read its exit status and message.
      PidLiveness? killCommandAnswer(int candidate) {
        final ProcessResult result;
        try {
          result = Process.runSync('kill', <String>['-0', '$candidate']);
        } on ProcessException {
          return null;
        }
        if (result.exitCode == 0) return PidLiveness.alive;
        final message = '${result.stderr}'.toLowerCase();
        if (message.contains('no such process')) return PidLiveness.dead;
        return PidLiveness.indeterminate;
      }

      test('answers as the kill -0 command did: alive, dead, and another '
          "user's process", () async {
        final gone = await deadPid();
        // This process; one that has exited; pid 1, which belongs to root and
        // reads as not permitted unless this runs as root; the largest pid.
        for (final candidate in <int>[pid, gone, 1, 0x7fffffff]) {
          final expected = killCommandAnswer(candidate);
          if (expected == null) {
            markTestSkipped('no kill command to compare with');
            return;
          }
          expect(
            // The macOS path, which Linux hosts take only when asked to.
            pidLiveness(candidate, operatingSystem: 'macos'),
            expected,
            reason: 'pid $candidate',
          );
        }
        expect(pidLiveness(pid, operatingSystem: 'macos'), PidLiveness.alive);
        expect(pidLiveness(gone, operatingSystem: 'macos'), PidLiveness.dead);
      });

      test('cannot tell for a pid no pid_t can hold, which the kill command '
          'refused as illegal', () {
        for (final candidate in <int>[0x80000000, 99999999999]) {
          expect(
            pidLiveness(candidate, operatingSystem: 'macos'),
            PidLiveness.indeterminate,
            reason: 'pid $candidate',
          );
        }
      });

      test('is a system call, not a process launch', () {
        const probes = 200;
        final clock = Stopwatch()..start();
        for (var i = 0; i < probes; i++) {
          pidLiveness(pid, operatingSystem: 'macos');
        }
        clock.stop();
        // Measured on macOS: a probe takes about a microsecond; launching
        // the kill command took about four milliseconds, all of it on the
        // calling isolate.
        expect(
          clock.elapsed,
          lessThan(const Duration(milliseconds: 50)),
          reason: '$probes probes took ${clock.elapsed}',
        );
      });
    },
    skip: Platform.isWindows ? 'no kill(2) on Windows' : false,
  );
}

/// How long every operation on [_SlowDisk] takes.
const Duration _slowDiskDelay = Duration(milliseconds: 150);

/// The manifest directory on a disk where every operation takes
/// [_slowDiskDelay]. Paths outside [root] — `/proc`, the temp directory's
/// parents — are the real filesystem.
final class _SlowDisk {
  _SlowDisk(this.root);

  final String root;

  /// Members the scan called that this fake does not model. Such a call is
  /// answered with an error the scan may well swallow, so a test asserts
  /// this is empty rather than trusting its other answers.
  final List<String> unmodelled = <String>[];

  /// Operations on files (not directories) under [root].
  int fileOperations = 0;

  /// Directory listings begun, in progress now, and in progress at once at
  /// most.
  int listings = 0;
  int listingsInFlight = 0;
  int mostListingsAtOnce = 0;

  bool _owns(String path) => p.equals(path, root) || p.isWithin(root, path);

  /// Runs [body] with every `File` and `Directory` it makes under [root] on
  /// this disk — including those made by timers and callbacks it schedules.
  Future<T> run<T>(Future<T> Function() body) => IOOverrides.runZoned(
    body,
    createDirectory: (path) {
      final real = Zone.root.run(() => Directory(path));
      return _owns(path) ? _SlowDirectory(this, real) : real;
    },
    createFile: (path) {
      final real = Zone.root.run(() => File(path));
      return _owns(path) ? _SlowFile(this, real) : real;
    },
  );

  Future<void> _wait() => Future<void>.delayed(_slowDiskDelay);

  void _hold() => sleep(_slowDiskDelay);

  Object? _unmodelled(String type, Invocation invocation) {
    unmodelled.add('$type ${invocation.memberName}');
    throw UnsupportedError('$type ${invocation.memberName} on the slow disk');
  }
}

final class _SlowDirectory implements Directory {
  _SlowDirectory(this._disk, this._real);

  final _SlowDisk _disk;
  final Directory _real;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() async {
    await _disk._wait();
    return _real.exists();
  }

  @override
  bool existsSync() {
    _disk._hold();
    return _real.existsSync();
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    _disk
      ..listings += 1
      ..listingsInFlight += 1;
    if (_disk.listingsInFlight > _disk.mostListingsAtOnce) {
      _disk.mostListingsAtOnce = _disk.listingsInFlight;
    }
    try {
      await _disk._wait();
      yield* _real
          .list(recursive: recursive, followLinks: followLinks)
          .map(_onDisk);
    } finally {
      _disk.listingsInFlight -= 1;
    }
  }

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) {
    _disk._hold();
    return _real
        .listSync(recursive: recursive, followLinks: followLinks)
        .map(_onDisk)
        .toList();
  }

  /// The real lister makes its entries without consulting the override, so
  /// the files it reports are put on this disk here.
  FileSystemEntity _onDisk(FileSystemEntity entity) =>
      entity is File ? _SlowFile(_disk, entity) : entity;

  @override
  Future<FileStat> stat() async {
    await _disk._wait();
    return _real.stat();
  }

  @override
  FileStat statSync() {
    _disk._hold();
    return _real.statSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _disk._unmodelled('Directory', invocation);
}

final class _SlowFile implements File {
  _SlowFile(this._disk, this._real);

  final _SlowDisk _disk;
  final File _real;

  Future<void> _wait() {
    _disk.fileOperations++;
    return _disk._wait();
  }

  void _hold() {
    _disk.fileOperations++;
    _disk._hold();
  }

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() async {
    await _wait();
    return _real.exists();
  }

  @override
  bool existsSync() {
    _hold();
    return _real.existsSync();
  }

  @override
  Future<FileStat> stat() async {
    await _wait();
    return _real.stat();
  }

  @override
  FileStat statSync() {
    _hold();
    return _real.statSync();
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    await _wait();
    return _real.readAsString(encoding: encoding);
  }

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    _hold();
    return _real.readAsStringSync(encoding: encoding);
  }

  @override
  Future<DateTime> lastModified() async {
    await _wait();
    return _real.lastModified();
  }

  @override
  DateTime lastModifiedSync() {
    _hold();
    return _real.lastModifiedSync();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await _wait();
    await _real.delete(recursive: recursive);
    return this;
  }

  @override
  void deleteSync({bool recursive = false}) {
    _hold();
    _real.deleteSync(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _disk._unmodelled('File', invocation);
}

/// The longest the event loop went without running a 1 ms timer, between
/// [start] and [stop].
///
/// A gap is measured when the timer next fires, so [stop] measures the last
/// one itself. Without that, a stall that ended the measured work — the
/// scan's final reap, say, when the listing happens to put that file last —
/// was never followed by a firing and went uncounted. With it, every stall
/// lies between two observations, since none can happen during it.
final class _LoopProbe {
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  var _last = 0;
  Duration longest = Duration.zero;

  void start() {
    _clock.start();
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) => _observe());
  }

  void _observe() {
    final now = _clock.elapsedMicroseconds;
    if (now - _last > longest.inMicroseconds) {
      longest = Duration(microseconds: now - _last);
    }
    _last = now;
  }

  void stop() {
    final timer = _timer;
    if (timer == null || !timer.isActive) return;
    timer.cancel();
    _observe();
  }
}
