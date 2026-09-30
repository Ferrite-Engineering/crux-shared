// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_file_watcher/crux_file_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a [WatchFactory] that emits [events] and then closes.
WatchFactory _factory(List<FileSystemEvent> events) {
  return (_) {
    final controller = StreamController<FileSystemEvent>();
    unawaited(
      Future.microtask(() async {
        events.forEach(controller.add);
        await controller.close();
      }),
    );
    return controller.stream;
  };
}

/// A [WatchFactory] that never emits anything.
WatchFactory get _silentFactory =>
    (_) => const Stream.empty();

/// Creates a fake [FileSystemModifyEvent].
FileSystemEvent _modifyEvent(String path) =>
    FileSystemModifyEvent(path, false, false);

/// Creates a fake [FileSystemDeleteEvent].
FileSystemEvent _deleteEvent(String path) => FileSystemDeleteEvent(path, false);

/// Creates a fake [FileSystemMoveEvent].
FileSystemEvent _moveEvent(String path) =>
    FileSystemMoveEvent(path, false, null);

void main() {
  group('FileWatcherService', () {
    test('events stream is initially empty when not watching', () async {
      final service = FileWatcherService(watchFactory: _silentFactory);
      addTearDown(service.dispose);

      final emitted = <FileWatchEvent>[];
      final sub = service.events.listen(emitted.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted, isEmpty);
    });

    test('modify event emits FileWatchEvent.modified after debounce', () async {
      final completer = Completer<FileWatchEvent>();
      final service = FileWatcherService(
        watchFactory: _factory([_modifyEvent('/tmp/a.vcd')]),
      );
      addTearDown(service.dispose);

      service.events.listen(completer.complete);
      service.startWatching('/tmp/a.vcd');

      final event = await completer.future.timeout(const Duration(seconds: 2));
      expect(event, FileWatchEvent.modified);
    });

    test('delete event emits FileWatchEvent.deleted after debounce', () async {
      final completer = Completer<FileWatchEvent>();
      final service = FileWatcherService(
        watchFactory: _factory([_deleteEvent('/tmp/a.vcd')]),
      );
      addTearDown(service.dispose);

      service.events.listen(completer.complete);
      service.startWatching('/tmp/a.vcd');

      final event = await completer.future.timeout(const Duration(seconds: 2));
      expect(event, FileWatchEvent.deleted);
    });

    test('move event emits FileWatchEvent.deleted', () async {
      final completer = Completer<FileWatchEvent>();
      final service = FileWatcherService(
        watchFactory: _factory([_moveEvent('/tmp/a.vcd')]),
      );
      addTearDown(service.dispose);

      service.events.listen(completer.complete);
      service.startWatching('/tmp/a.vcd');

      final event = await completer.future.timeout(const Duration(seconds: 2));
      expect(event, FileWatchEvent.deleted);
    });

    test('rapid modify events are debounced to a single emission', () async {
      final ctrl = StreamController<FileSystemEvent>();
      final service = FileWatcherService(watchFactory: (_) => ctrl.stream);
      addTearDown(service.dispose);
      addTearDown(ctrl.close);

      final emitted = <FileWatchEvent>[];
      service.events.listen(emitted.add);
      service.startWatching('/tmp/a.vcd');

      // Fire 5 modify events in quick succession.
      for (var i = 0; i < 5; i++) {
        ctrl.add(_modifyEvent('/tmp/a.vcd'));
      }

      // Wait longer than the 500ms debounce window.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(emitted.length, 1);
      expect(emitted.first, FileWatchEvent.modified);
    });

    test(
      'stopWatching cancels the subscription and pending debounce',
      () async {
        final ctrl = StreamController<FileSystemEvent>();
        final service = FileWatcherService(watchFactory: (_) => ctrl.stream);
        addTearDown(service.dispose);
        addTearDown(ctrl.close);

        final emitted = <FileWatchEvent>[];
        service.events.listen(emitted.add);
        service.startWatching('/tmp/a.vcd');

        ctrl.add(_modifyEvent('/tmp/a.vcd'));
        service.stopWatching(); // cancel before debounce fires

        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(emitted, isEmpty);
      },
    );

    test(
      'startWatching stops previous watcher before starting new one',
      () async {
        var callCount = 0;
        Stream<FileSystemEvent> countingFactory(String _) {
          callCount++;
          return const Stream.empty();
        }

        final service = FileWatcherService(watchFactory: countingFactory);
        addTearDown(service.dispose);

        service
          ..startWatching('/tmp/a.vcd')
          ..startWatching('/tmp/b.vcd');
        expect(callCount, 2);
      },
    );

    test('dispose closes the events stream', () async {
      final service = FileWatcherService(watchFactory: _silentFactory);
      var closed = false;
      service.events.listen(null, onDone: () => closed = true);

      service.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(closed, isTrue);
    });

    test('stopWatching is safe when called before startWatching', () {
      final service = FileWatcherService(watchFactory: _silentFactory);
      expect(service.stopWatching, returnsNormally);
      service.dispose();
    });

    test('stopWatching is idempotent', () {
      final service = FileWatcherService(watchFactory: _silentFactory)
        ..startWatching('/tmp/a.vcd');
      expect(() {
        service
          ..stopWatching()
          ..stopWatching();
      }, returnsNormally);
      service.dispose();
    });

    test('sustained writes still emit — the debounce is bounded', () async {
      // The workload this package exists to serve: a simulator writing into
      // a dump file continuously, faster than the quiet period. Against a
      // plain restart-the-timer debounce this emits ZERO events, because
      // every write cancels the pending timer before it can fire.
      final ctrl = StreamController<FileSystemEvent>();
      final service = FileWatcherService(
        watchFactory: (_) => ctrl.stream,
        debounceDelay: const Duration(milliseconds: 200),
        maxWait: const Duration(milliseconds: 600),
      );
      addTearDown(service.dispose);

      final emitted = <FileWatchEvent>[];
      service.events.listen(emitted.add);
      service.startWatching('/tmp/a.vcd');

      // Write every 50 ms for 1.4 s — never a 200 ms quiet gap, so the
      // quiet-period timer can never fire on its own.
      final ticker = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => ctrl.add(_modifyEvent('/tmp/a.vcd')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      ticker.cancel();

      expect(
        emitted,
        isNotEmpty,
        reason: 'a continuously-written file must still drive auto-reload',
      );
      // ~1.4 s of sustained writes at a 600 ms ceiling: at least two emits.
      expect(emitted.length, greaterThanOrEqualTo(2));
      expect(emitted.every((e) => e == FileWatchEvent.modified), isTrue);
      await ctrl.close();
    });

    test('the quiet period still coalesces once writes stop', () async {
      // The max-wait must not degrade into "emit every maxWait regardless":
      // a short burst followed by silence is still one event.
      final ctrl = StreamController<FileSystemEvent>();
      final service = FileWatcherService(
        watchFactory: (_) => ctrl.stream,
        debounceDelay: const Duration(milliseconds: 200),
        maxWait: const Duration(milliseconds: 600),
      );
      addTearDown(service.dispose);
      addTearDown(ctrl.close);

      final emitted = <FileWatchEvent>[];
      service.events.listen(emitted.add);
      service.startWatching('/tmp/a.vcd');

      for (var i = 0; i < 5; i++) {
        ctrl.add(_modifyEvent('/tmp/a.vcd'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(emitted, [FileWatchEvent.modified]);
    });

    test('a burst emit does not double-fire from both timers', () async {
      // Both the quiet-period timer and the ceiling timer target the same
      // emit; whichever fires first must cancel the other.
      final ctrl = StreamController<FileSystemEvent>();
      final service = FileWatcherService(
        watchFactory: (_) => ctrl.stream,
        debounceDelay: const Duration(milliseconds: 100),
        maxWait: const Duration(milliseconds: 150),
      );
      addTearDown(service.dispose);
      addTearDown(ctrl.close);

      final emitted = <FileWatchEvent>[];
      service.events.listen(emitted.add);
      service.startWatching('/tmp/a.vcd');

      ctrl.add(_modifyEvent('/tmp/a.vcd'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(emitted, hasLength(1));
    });

    group('watch death', () {
      test('a watch error is reported on stopped, not swallowed', () async {
        // macOS FSEvents dropping the watch, or a platform-level watch
        // error. Previously `onError: (_) {}` discarded this and left the
        // service believing it was still watching.
        final ctrl = StreamController<FileSystemEvent>();
        final service = FileWatcherService(watchFactory: (_) => ctrl.stream);
        addTearDown(service.dispose);

        final stops = <FileWatchStopped>[];
        service.stopped.listen(stops.add);
        service.startWatching('/tmp/a.vcd');
        expect(service.isWatching, isTrue);

        ctrl.addError(const FileSystemException('watch dropped'));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(stops, hasLength(1));
        expect(stops.single.reason, FileWatchStopReason.error);
        expect(stops.single.path, '/tmp/a.vcd');
        expect(stops.single.error, isA<FileSystemException>());
        expect(
          service.isWatching,
          isFalse,
          reason: 'a dead watch must not report itself as live',
        );
        await ctrl.close();
      });

      test(
        'a watch error cancels the subscription — no further events leak',
        () async {
          // Regression: the error path used to report the death but never
          // cancel the FS subscription nor retire the generation. An
          // errored-but-unclosed source stream could then keep delivering
          // events for a watch the service had already reported as stopped —
          // a leak that drives phantom auto-reloads. The fix cancels the
          // subscription (cancelOnError plus an explicit cancel) and bumps
          // the generation so any late callback is ignored.
          final ctrl = StreamController<FileSystemEvent>();
          final service = FileWatcherService(
            watchFactory: (_) => ctrl.stream,
            debounceDelay: const Duration(milliseconds: 50),
          );
          addTearDown(service.dispose);

          final emitted = <FileWatchEvent>[];
          final stops = <FileWatchStopped>[];
          service.events.listen(emitted.add);
          service.stopped.listen(stops.add);
          service.startWatching('/tmp/a.vcd');

          ctrl.addError(const FileSystemException('watch dropped'));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(stops, hasLength(1));
          expect(service.isWatching, isFalse);

          // The source has not closed; push more events at it. A live
          // subscription would deliver these and emit a phantom reload.
          ctrl
            ..add(_modifyEvent('/tmp/a.vcd'))
            ..add(_modifyEvent('/tmp/a.vcd'));
          await Future<void>.delayed(const Duration(milliseconds: 200));

          expect(
            emitted,
            isEmpty,
            reason: 'a cancelled watch must deliver nothing after its death',
          );
          expect(stops, hasLength(1), reason: 'the death is reported once');
          await ctrl.close();
        },
      );

      test('a watch that ends on its own is reported on stopped', () async {
        // `rm -rf build/` — the parent directory disappears and the
        // directory watch simply completes. Nothing is ever watched again.
        final ctrl = StreamController<FileSystemEvent>();
        final service = FileWatcherService(watchFactory: (_) => ctrl.stream);
        addTearDown(service.dispose);

        final stops = <FileWatchStopped>[];
        service.stopped.listen(stops.add);
        service.startWatching('/tmp/build/a.vcd');

        await ctrl.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(stops, hasLength(1));
        expect(stops.single.reason, FileWatchStopReason.watchClosed);
        expect(stops.single.path, '/tmp/build/a.vcd');
        expect(service.isWatching, isFalse);
      });

      test('a watch that cannot be established fails loudly', () async {
        // Watching a path whose parent does not exist previously failed
        // completely silently via `on Exception catch (_)`.
        final service = FileWatcherService(
          watchFactory: (_) =>
              throw const FileSystemException('no such directory'),
        );
        addTearDown(service.dispose);

        final stops = <FileWatchStopped>[];
        service.stopped.listen(stops.add);

        expect(() => service.startWatching('/nope/a.vcd'), returnsNormally);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(stops, hasLength(1));
        expect(stops.single.reason, FileWatchStopReason.error);
        expect(service.isWatching, isFalse);
      });

      test('re-arming after a death resumes delivery', () async {
        var attempt = 0;
        late StreamController<FileSystemEvent> live;
        Stream<FileSystemEvent> factory(String _) {
          attempt++;
          if (attempt == 1) {
            return Stream<FileSystemEvent>.error(
              const FileSystemException('dropped'),
            );
          }
          live = StreamController<FileSystemEvent>();
          return live.stream;
        }

        final service = FileWatcherService(
          watchFactory: factory,
          debounceDelay: const Duration(milliseconds: 100),
        );
        addTearDown(service.dispose);

        final stops = <FileWatchStopped>[];
        final emitted = <FileWatchEvent>[];
        service.stopped.listen(stops.add);
        service.events.listen(emitted.add);

        service.startWatching('/tmp/a.vcd');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(stops, hasLength(1));

        // Re-arm — the host's "auto-reload stopped, retry?" affordance.
        service.startWatching('/tmp/a.vcd');
        expect(service.isWatching, isTrue);
        live.add(_modifyEvent('/tmp/a.vcd'));
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(emitted, [FileWatchEvent.modified]);
        await live.close();
      });

      test('a deliberate stopWatching does not report a death', () async {
        final ctrl = StreamController<FileSystemEvent>();
        final service = FileWatcherService(watchFactory: (_) => ctrl.stream);
        addTearDown(service.dispose);
        addTearDown(ctrl.close);

        final stops = <FileWatchStopped>[];
        service.stopped.listen(stops.add);
        service
          ..startWatching('/tmp/a.vcd')
          ..stopWatching();

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          stops,
          isEmpty,
          reason: 'stopped reports spontaneous deaths only',
        );
      });
    });

    test('multiple subscribers receive events', () async {
      final completer1 = Completer<FileWatchEvent>();
      final completer2 = Completer<FileWatchEvent>();

      final service = FileWatcherService(
        watchFactory: _factory([_modifyEvent('/tmp/a.vcd')]),
      );
      addTearDown(service.dispose);

      service.events.listen(completer1.complete);
      service.events.listen(completer2.complete);
      service.startWatching('/tmp/a.vcd');

      final results = await Future.wait([
        completer1.future.timeout(const Duration(seconds: 2)),
        completer2.future.timeout(const Duration(seconds: 2)),
      ]);
      expect(results, [FileWatchEvent.modified, FileWatchEvent.modified]);
    });
  });
}
