// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../harness.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_live_telemetry');
  });

  tearDown(() {
    // The service's disk chain is deliberately fire-and-forget, so a queued
    // append can still land between the directory scan and the unlink. Losing
    // that race is the *service* behaving correctly; failing the run over it
    // would be the test asserting the opposite of the contract.
    try {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    } on FileSystemException catch (_) {
      // A stray temp directory is the OS's problem, not this suite's.
    }
  });

  final envelope = testEnvelope();

  final endpoint = Uri.parse('https://telemetry.edacrux.app/dev/v1/events');

  LiveTelemetryService serviceWith({
    required http.Client client,
    Directory? directory,
    Future<TelemetryEnvelope?> Function()? envelopeResolver,
    DateTime Function()? now,
    Duration initialRetryDelay = const Duration(minutes: 1),
    bool isWeb = false,
  }) {
    final dir = directory ?? temp;
    return LiveTelemetryService(
      endpoint: endpoint,
      envelopeResolver: envelopeResolver ?? () async => envelope,
      client: client,
      directoryFactory: () async => dir,
      initialRetryDelay: initialRetryDelay,
      now: now,
      isWeb: isWeb,
    );
  }

  group('flush', () {
    test('coalesces the queue into one POST and drains it', () async {
      final bodies = <String>[];
      final requests = <http.BaseRequest>[];
      final service = serviceWith(
        client: MockClient((request) async {
          requests.add(request);
          bodies.add(request.body);
          return http.Response('{"accepted":2,"dropped":0}', 202);
        }),
      );
      addTearDown(service.dispose);

      service
        ..record(
          TelemetryEvent(
            'decoder.opened',
            properties: const <String, Object?>{'decoder': 'spi'},
          ),
        )
        ..record(
          TelemetryEvent(
            'decoder.opened',
            properties: const <String, Object?>{'decoder': 'spi'},
          ),
        )
        ..record(TelemetryEvent('workspace.restored'));

      await service.flush();

      expect(bodies, hasLength(1));
      final decoded = jsonDecode(bodies.single) as Map<String, Object?>;
      final events = (decoded['events']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(events, hasLength(2));
      expect(events.first['name'], 'decoder.opened');
      expect(events.first['count'], 2);
      expect(events.last['count'], 1);

      // Accepted rows leave the queue and the file.
      expect(service.pending, isEmpty);
      expect(
        File('${temp.path}/${TelemetryEventQueue.fileName}').existsSync(),
        isFalse,
      );
    });

    test('sends the User-Agent the update check sends', () async {
      final requests = <http.BaseRequest>[];
      final service = serviceWith(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();

      expect(requests.single.headers['User-Agent'], 'WaveCrux/0.6.0');
      expect(requests.single.url, endpoint);
      expect(
        requests.single.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
    });

    test('a browser build sends no User-Agent', () async {
      // Safari and Firefox honour a page-set `User-Agent` and name it in the
      // CORS preflight; Chrome drops it. So a browser POST carrying the header
      // was a preflight the Worker refused on two of the three engines, a
      // `failed` outcome the client retried forever, and zero web rows in
      // production, ever. The envelope already says which product and version
      // this is, so the header has nothing to add on web.
      final requests = <http.BaseRequest>[];
      final service = serviceWith(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 202);
        }),
        isWeb: true,
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();

      expect(requests.single.headers.keys.map((k) => k.toLowerCase()), [
        'content-type',
      ]);
      expect(
        requests.single.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
    });

    test(
      'every header the client sends is on the Worker CORS allow-list',
      () async {
        // `test/fixtures/cors-allowed-headers.json` carries the same list as the
        // ingestion Worker's `contract/cors-allowed-headers.json`, and the
        // Worker's own test asserts its preflight answers with exactly that
        // list. Together they close the gap that hid the web editions: a header
        // this client sends that the Worker does not allow is a preflight that
        // fails, and a failed preflight is invisible to everything but the
        // browser console.
        final allowed =
            (jsonDecode(
                      File(
                        'test/fixtures/cors-allowed-headers.json',
                      ).readAsStringSync(),
                    )
                    as List<Object?>)
                .cast<String>()
                .map((h) => h.toLowerCase())
                .toSet();

        for (final isWeb in <bool>[false, true]) {
          final requests = <http.BaseRequest>[];
          final service = serviceWith(
            client: MockClient((request) async {
              requests.add(request);
              return http.Response('{}', 202);
            }),
            directory: Directory.systemTemp.createTempSync('crux_cors_$isWeb'),
            isWeb: isWeb,
          );
          addTearDown(service.dispose);

          service.record(TelemetryEvent('tab.opened'));
          await service.flush();

          for (final name in requests.single.headers.keys) {
            expect(
              allowed,
              contains(name.toLowerCase()),
              reason:
                  '`$name` is sent with isWeb=$isWeb but is not on the '
                  'Worker allow-list — a browser preflight would refuse it',
            );
          }
        }
      },
    );

    test('posts nothing when the queue is empty', () async {
      var calls = 0;
      final service = serviceWith(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
      );
      addTearDown(service.dispose);

      await service.flush();
      expect(calls, 0);
    });

    test('skips the flush when the envelope cannot be resolved yet', () async {
      var calls = 0;
      final service = serviceWith(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 202);
        }),
        // Build info racing startup: a version we do not have must not be
        // invented, because a bad app_version rejects the whole batch.
        envelopeResolver: () async => null,
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();

      expect(calls, 0);
      expect(service.pending, hasLength(1));
    });

    test('start() posts the queue the previous session left behind', () async {
      // The launch flush ships the PREVIOUS session's queue — the file is the
      // handover, and nothing is ever sent inline with the event that produced
      // it.
      await TelemetryEventQueue(
        directoryFactory: () async => temp,
      ).append(TelemetryEvent('workspace.restored'));

      final bodies = <String>[];
      // Wait for the POST itself rather than for a guessed number of
      // event-loop turns. The previous form spun
      // `Future.delayed(Duration.zero)` fifty times and then asserted; that
      // is enough on an idle laptop and
      // was not enough on a loaded CI runner, because the launch flush reads
      // the handover file from disk before it posts. It failed on 2026-08-18
      // with `Actual: []` — the flush had simply not got there yet.
      //
      // A Completer the mock client fires is deterministic: the test blocks
      // until the thing it is asserting about has actually happened, and the
      // timeout turns a hang into a legible failure instead of a 50-turn
      // false negative.
      final posted = Completer<void>();
      final reader = serviceWith(
        client: MockClient((request) async {
          bodies.add(request.body);
          if (!posted.isCompleted) posted.complete();
          return http.Response('{}', 202);
        }),
      );
      addTearDown(reader.dispose);

      reader.start();
      await posted.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail(
          'the launch flush never posted the previous session queue',
        ),
      );

      expect(bodies, hasLength(1));
      expect(bodies.single, contains('workspace.restored'));
    });

    test('dispose persists what is still buffered', () async {
      serviceWith(client: MockClient((_) async => http.Response('', 503)))
        ..record(TelemetryEvent('pane.split'))
        ..dispose();

      // `dispose()` is deliberately fire-and-forget — it ends in
      // `unawaited(_onDisk(...))` — so the write lands an unknowable number of
      // event-loop turns later, after a 503 round-trip and a file write.
      //
      // This used to pump a fixed 50 zero-duration turns and then assert. That
      // is a race with an arbitrary budget: it passed on an idle machine and
      // lost on a loaded CI runner (crux-shared run 31234289780 failed here
      // while the identical tree had passed 30 minutes earlier). Poll for the
      // condition instead — returns the instant the write lands, so it is
      // faster in the normal case, and still fails loudly if the behaviour
      // actually regresses.
      var names = const <String>[];
      for (var attempt = 0; attempt < 200; attempt++) {
        final persisted = await TelemetryEventQueue(
          directoryFactory: () async => temp,
        ).load(now: DateTime.now());
        names = persisted.map((e) => e.name).toList();
        if (names.contains('pane.split')) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        names,
        contains('pane.split'),
        reason:
            'dispose() must persist the buffered event within 2s; it never '
            'appeared on disk, which is a real regression rather than the '
            'timing flake this poll replaced',
      );
    });
  });

  group('volatile mode — a queue with no persistent backing', () {
    // On web `path_provider` is unavailable, so the queue is memory-only:
    // `load()` returns empty, the launch flush returns at `_pending.isEmpty`
    // WITHOUT arming anything, and the only surviving trigger is a six-hourly
    // timer that no browser session outlives. Four products' web builds
    // transmitted zero rows.
    //
    // A `directoryFactory` that throws is exactly what web presents.
    LiveTelemetryService volatileService({
      required http.Client client,
      TelemetryLifecycleObserver? lifecycleObserver,
      Duration volatileFlushInterval = const Duration(seconds: 60),
    }) => LiveTelemetryService(
      endpoint: endpoint,
      envelopeResolver: () async => envelope,
      client: client,
      directoryFactory: () async =>
          throw const FileSystemException('no app support dir'),
      lifecycleObserver: lifecycleObserver ?? (_) => () {},
      volatileFlushInterval: volatileFlushInterval,
    );

    test('start() detects that there is no file behind the queue', () {
      fakeAsync((async) {
        final service = volatileService(
          client: MockClient((_) async => http.Response('{}', 202)),
        )..start();
        async.flushMicrotasks();

        expect(service.isVolatile, isTrue);

        service.dispose();
        async.flushTimers();
      });
    });

    test('a session recorded after an empty launch flush still ships', () {
      // The defect, end to end: nothing in the queue at launch, events recorded
      // afterwards, and the tab closed long before six hours.
      fakeAsync((async) {
        final bodies = <String>[];
        final service = volatileService(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
        )..start();
        async.flushMicrotasks();

        service.record(TelemetryEvent('workspace.restored'));
        async.elapse(const Duration(seconds: 59));
        expect(
          bodies,
          isEmpty,
          reason: 'still inside the window — nothing waits on the network',
        );

        async.elapse(const Duration(seconds: 2));
        expect(bodies, hasLength(1));
        expect(bodies.single, contains('workspace.restored'));
        expect(service.pending, isEmpty);

        service.dispose();
        async.flushTimers();
      });
    });

    test(
      'the window is per flush, not per event — a busy session progresses',
      () {
        // Deliberately NOT a timer each record pushes further out. A session
        // recording steadily would never reach the end of that debounce and
        // would report nothing at all — the defect rather than the fix.
        fakeAsync((async) {
          final bodies = <String>[];
          final service = volatileService(
            client: MockClient((request) async {
              bodies.add(request.body);
              return http.Response('{}', 202);
            }),
          )..start();
          async.flushMicrotasks();

          // One event every 10 s for two minutes.
          for (var i = 0; i < 12; i++) {
            service.record(TelemetryEvent('tab.opened'));
            async.elapse(const Duration(seconds: 10));
          }

          expect(bodies, hasLength(2), reason: 'one flush per 60 s window');
          // And they coalesced rather than going out one POST per event.
          expect(bodies.first, contains('"count":6'));

          service.dispose();
          async.flushTimers();
        });
      },
    );

    test('a flush that skipped on an unresolved envelope re-arms', () {
      // The launch flush of a cold web start: `app_version` has not landed, so
      // the envelope is null. Nothing new is recorded afterwards either, so if
      // the window were armed only from `record` it would never be armed again
      // and the session would report nothing — the same failure, one layer in.
      fakeAsync((async) {
        var version = false;
        final bodies = <String>[];
        final service = LiveTelemetryService(
          endpoint: endpoint,
          envelopeResolver: () async => version ? envelope : null,
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
          directoryFactory: () async =>
              throw const FileSystemException('no app support dir'),
          lifecycleObserver: (_) => () {},
        )..start();
        async.flushMicrotasks();

        service.record(TelemetryEvent('workspace.restored'));
        async.elapse(const Duration(seconds: 61));
        expect(bodies, isEmpty);
        expect(service.pending, hasLength(1));

        version = true;
        async.elapse(const Duration(seconds: 61));
        expect(bodies, hasLength(1));

        service.dispose();
        async.flushTimers();
      });
    });

    test('a lifecycle hide flushes — the only warning a tab gives', () {
      fakeAsync((async) {
        void Function()? backgrounded;
        var cancelled = false;
        final bodies = <String>[];
        final service = volatileService(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
          lifecycleObserver: (onBackgrounded) {
            backgrounded = onBackgrounded;
            return () => cancelled = true;
          },
        )..start();
        async.flushMicrotasks();

        service.record(TelemetryEvent('file.opened'));
        expect(backgrounded, isNotNull);

        // The tab goes to the background five seconds in — well inside the
        // 60 s window, and on web quite possibly the last thing that happens.
        async.elapse(const Duration(seconds: 5));
        backgrounded!();
        async.flushMicrotasks();

        expect(bodies, hasLength(1));
        expect(bodies.single, contains('file.opened'));

        service.dispose();
        async.flushTimers();
        expect(cancelled, isTrue, reason: 'dispose unsubscribes');
      });
    });

    test('a lifecycle surface that is unavailable is not fatal', () {
      // A bare host with no widget binding. The interval cadence still covers
      // it, and nothing may escape this class in any case.
      fakeAsync((async) {
        final bodies = <String>[];
        final service = volatileService(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
          lifecycleObserver: (_) => throw StateError('no widget binding'),
        );

        expect(service.start, returnsNormally);
        async.flushMicrotasks();
        service.record(TelemetryEvent('tab.opened'));
        async.elapse(const Duration(seconds: 61));
        expect(bodies, hasLength(1));

        service.dispose();
        async.flushTimers();
      });
    });

    test('the interval is configurable, not hard-coded at 60 s', () {
      fakeAsync((async) {
        final bodies = <String>[];
        final service = volatileService(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
          volatileFlushInterval: const Duration(seconds: 5),
        )..start();
        async.flushMicrotasks();

        service.record(TelemetryEvent('tab.opened'));
        async.elapse(const Duration(seconds: 6));
        expect(bodies, hasLength(1));

        service.dispose();
        async.flushTimers();
      });
    });
  });

  group('the persistent-queue contract is untouched', () {
    // The near-term cadence exists exactly and only where there is no next
    // launch to hand the queue to. On desktop and mobile the file IS the
    // handover, so this session's events must still go out on the next
    // six-hourly tick or the next launch — not a minute after they happen.
    test('a persistent queue arms no near-term flush', () {
      fakeAsync((async) {
        final bodies = <String>[];
        final service = serviceWith(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
        )..start();
        async.flushMicrotasks();

        expect(service.isVolatile, isFalse);

        service.record(TelemetryEvent('workspace.restored'));
        async.elapse(const Duration(minutes: 30));
        expect(
          bodies,
          isEmpty,
          reason:
              'nothing is sent inline with the event that produced it, and on '
              'a persistent queue the next launch is what ships it',
        );

        async.elapse(const Duration(hours: 6));
        expect(bodies, hasLength(1));

        service.dispose();
        async.flushTimers();
      });
    });

    test('but a DEFERRED flush retries in a minute, on disk too', () {
      // The exception, and it is not a cadence: the envelope could not be
      // resolved, so a flush that was already due did not happen. These are the
      // launch flush's own events, finished late — nothing goes out inline with
      // the event that produced it.
      //
      // Without this, deferring on an unknown `form_factor` would have broken
      // mobile the way the memory-only queue broke web:
      // the launch flush loses the first-frame race, defers, and hands the
      // queue to a next launch that races the same frame again. Six hours is
      // not "the next tick" for a queue that is already full.
      fakeAsync((async) {
        var formFactorKnown = false;
        final bodies = <String>[];
        final service = serviceWith(
          client: MockClient((request) async {
            bodies.add(request.body);
            return http.Response('{}', 202);
          }),
          envelopeResolver: () async => formFactorKnown ? envelope : null,
        )..record(TelemetryEvent('workspace.restored'));

        service.flush().ignore();
        async.flushMicrotasks();
        expect(bodies, isEmpty);
        expect(service.pending, hasLength(1));

        // The first frame lands; the retry is already armed.
        formFactorKnown = true;
        async.elapse(const Duration(seconds: 61));
        expect(bodies, hasLength(1));
        expect(bodies.single, contains('workspace.restored'));

        // And it stops there — a resolved flush arms nothing on a disk queue.
        service.record(TelemetryEvent('tab.opened'));
        async.elapse(const Duration(minutes: 30));
        expect(bodies, hasLength(1));

        service.dispose();
        async.flushTimers();
      });
    });

    test('a persistent queue subscribes to no lifecycle surface', () {
      fakeAsync((async) {
        var observed = false;
        final service = LiveTelemetryService(
          endpoint: endpoint,
          envelopeResolver: () async => envelope,
          client: MockClient((_) async => http.Response('{}', 202)),
          directoryFactory: () async => temp,
          lifecycleObserver: (_) {
            observed = true;
            return () {};
          },
        )..start();
        async.flushMicrotasks();

        expect(observed, isFalse);

        service.dispose();
        async.flushTimers();
      });
    });
  });

  group('backoff', () {
    test('doubles the retry delay on repeated 500s, then caps', () {
      fakeAsync((async) {
        var calls = 0;
        final service = serviceWith(
          client: MockClient((_) async {
            calls++;
            return http.Response('upstream is unwell', 500);
          }),
        )..record(TelemetryEvent('tab.opened'));
        service.flush().ignore();
        async.flushMicrotasks();

        expect(calls, 1);
        // The queue is kept — a 5xx is "later", not "never".
        expect(service.pending, hasLength(1));
        expect(service.retryDelay, const Duration(minutes: 2));

        async.elapse(const Duration(minutes: 1));
        expect(calls, 2);
        expect(service.retryDelay, const Duration(minutes: 4));

        async.elapse(const Duration(minutes: 2));
        expect(calls, 3);
        expect(service.retryDelay, const Duration(minutes: 8));

        // Straight to the ceiling and no further.
        async.elapse(const Duration(days: 2));
        expect(service.retryDelay, const Duration(hours: 6));

        service.dispose();
        async.flushTimers();
      });
    });

    test('a transport failure backs off the same way as a 500', () {
      fakeAsync((async) {
        var calls = 0;
        final service = serviceWith(
          client: MockClient((_) async {
            calls++;
            throw const SocketException('offline');
          }),
        )..record(TelemetryEvent('tab.opened'));
        service.flush().ignore();
        async.flushMicrotasks();

        expect(calls, 1);
        expect(service.pending, hasLength(1));

        async.elapse(const Duration(minutes: 1));
        expect(calls, 2);

        service.dispose();
        async.flushTimers();
      });
    });

    test('a success resets the delay to the first step', () async {
      var fail = true;
      final service = serviceWith(
        client: MockClient(
          (_) async => fail ? http.Response('', 503) : http.Response('{}', 202),
        ),
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();
      expect(service.retryDelay, const Duration(minutes: 2));

      fail = false;
      await service.flush();
      expect(service.retryDelay, const Duration(minutes: 1));
      expect(service.pending, isEmpty);
    });

    test('a 4xx drops the batch instead of retrying it forever', () async {
      var calls = 0;
      final service = serviceWith(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '{"error":"invalid batch","reason":"os must be a known platform"}',
            400,
          );
        }),
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();

      expect(calls, 1);
      // A permanent rejection that stayed queued would wedge everything behind
      // it and knock on the endpoint forever.
      expect(service.pending, isEmpty);
      expect(service.retryDelay, const Duration(minutes: 1));
    });

    test('a 429 is treated as "later", not "never"', () async {
      final service = serviceWith(
        client: MockClient((_) async => http.Response('', 429)),
      );
      addTearDown(service.dispose);

      service.record(TelemetryEvent('tab.opened'));
      await service.flush();

      expect(service.pending, hasLength(1));
      expect(service.retryDelay, const Duration(minutes: 2));
    });
  });

  group('the never-throws contract', () {
    test('record survives a disk that cannot be written', () async {
      final service = LiveTelemetryService(
        endpoint: endpoint,
        envelopeResolver: () async => envelope,
        client: MockClient((_) async => http.Response('{}', 202)),
        directoryFactory: () async =>
            throw const FileSystemException('no app support dir'),
      );
      addTearDown(service.dispose);

      expect(
        () => service.record(TelemetryEvent('tab.opened')),
        returnsNormally,
      );
      // Memory-only, but still collecting.
      expect(service.pending, hasLength(1));
    });

    test('record and flush survive an HTTP client that throws', () async {
      final service = serviceWith(
        client: MockClient((_) async => throw StateError('client is broken')),
      );
      addTearDown(service.dispose);

      expect(
        () => service.record(TelemetryEvent('tab.opened')),
        returnsNormally,
      );
      await expectLater(service.flush(), completes);
    });

    test('everything fails at once and nothing escapes', () async {
      final service = LiveTelemetryService(
        endpoint: endpoint,
        envelopeResolver: () async => throw StateError('no build info'),
        client: MockClient((_) async => throw StateError('client is broken')),
        directoryFactory: () async => throw const FileSystemException('gone'),
      );
      addTearDown(service.dispose);

      expect(
        () => service.record(TelemetryEvent('tab.opened')),
        returnsNormally,
      );
      expect(service.start, returnsNormally);
      await expectLater(service.flush(), completes);
      expect(service.dispose, returnsNormally);
    });

    test('record after dispose is a no-op, not an error', () {
      final service = serviceWith(
        client: MockClient((_) async => http.Response('{}', 202)),
      )..dispose();

      expect(
        () => service.record(TelemetryEvent('tab.opened')),
        returnsNormally,
      );
      expect(service.pending, isEmpty);
    });
  });

  group('queue limits', () {
    test(
      'the in-memory buffer honours the hard cap, dropping oldest',
      () async {
        final service = LiveTelemetryService(
          endpoint: endpoint,
          envelopeResolver: () async => envelope,
          client: MockClient((_) async => http.Response('{}', 202)),
          directoryFactory: () async => temp,
          maxQueuedEvents: 5,
          // Pinned, because `_trim` prunes by BOTH count and age. The events
          // below are stamped 2026-08-04, and with the wall clock this test
          // quietly became a time bomb: from 2026-08-11 — seven days on, the
          // `kTelemetryEventMaxAge` boundary — every event was too old, the
          // buffer came back empty, and the count assertion failed for a reason
          // that has nothing to do with counting.
          now: () => DateTime.utc(2026, 8, 4, 10),
        );
        addTearDown(service.dispose);

        for (var i = 0; i < 9; i++) {
          service.record(
            TelemetryEvent(
              'tool.opened',
              properties: <String, Object?>{'seq': i},
              timestamp: DateTime.utc(2026, 8, 4, 9, i),
            ),
          );
        }

        expect(service.pending, hasLength(5));
        expect(service.pending.first.properties['seq'], 4);
        expect(service.pending.last.properties['seq'], 8);
      },
    );

    test('stale events are dropped unsent', () async {
      final now = DateTime.utc(2026, 8, 4, 9, 15);
      final bodies = <String>[];
      final service = serviceWith(
        client: MockClient((request) async {
          bodies.add(request.body);
          return http.Response('{}', 202);
        }),
        now: () => now,
      );
      addTearDown(service.dispose);

      service
        ..record(
          TelemetryEvent(
            'ancient.event',
            timestamp: now.subtract(const Duration(days: 9)),
          ),
        )
        ..record(TelemetryEvent('recent.event', timestamp: now));

      await service.flush();

      expect(bodies.single, isNot(contains('ancient.event')));
      expect(bodies.single, contains('recent.event'));
    });
  });
}
