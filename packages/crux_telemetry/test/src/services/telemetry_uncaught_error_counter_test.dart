// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart' show kBetaPeriod;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A service that keeps what it is handed, in order.
class _Recording implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

/// A service that breaks the `record` contract, to prove the counter's own
/// never-throw guarantee does not lean on the service's.
class _Throwing implements TelemetryService {
  @override
  void record(TelemetryEvent event) => throw StateError('broken service');
}

/// A service that raises another error while recording, the way a failure
/// inside an error handler would.
class _Reentrant implements TelemetryService {
  _Reentrant(this.counter);

  final TelemetryUncaughtErrorCounter counter;
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) {
    events.add(event);
    counter.recordPlatformError(
      const FormatException('raised while recording'),
    );
  }
}

FlutterErrorDetails _details(
  Object exception, {
  String? library = 'widgets library',
  bool silent = false,
}) => FlutterErrorDetails(
  exception: exception,
  library: library,
  silent: silent,
);

void main() {
  late TelemetryUncaughtErrorCounter counter;
  late _Recording service;

  setUp(() {
    counter = TelemetryUncaughtErrorCounter(inert: false);
    service = _Recording();
    counter.attach(service);
  });

  group('the event', () {
    test('carries exactly source, kind, library and silent', () {
      counter.recordFlutterError(
        _details(StateError('x'), library: 'rendering library', silent: true),
      );

      final event = service.events.single;
      expect(event.name, kTelemetryUncaughtErrorEvent);
      expect(event.properties, <String, Object?>{
        'source': 'flutter',
        'kind': 'state_error',
        'library': 'rendering',
        'silent': true,
      });
    });

    test('a platform error has library none and is never silent', () {
      counter.recordPlatformError(ArgumentError('x'));

      expect(service.events.single.properties, <String, Object?>{
        'source': 'platform',
        'kind': 'argument_error',
        'library': 'none',
        'silent': false,
      });
    });

    test('never carries the message, the stack or a path', () {
      const secret = '/Users/someone/chip/secret_top.sv';
      counter
        ..recordFlutterError(
          FlutterErrorDetails(
            exception: const FileSystemException('open failed', secret),
            stack: StackTrace.current,
            library: 'services library',
            context: ErrorDescription('while loading $secret'),
          ),
        )
        ..recordPlatformError(StateError(secret));

      for (final event in service.events) {
        expect(event.toString(), isNot(contains('secret')));
        expect(event.toString(), isNot(contains('/Users')));
        expect(
          event.properties.keys,
          unorderedEquals(<String>[
            'source',
            'kind',
            'library',
            'silent',
          ]),
        );
      }
    });

    test('every value it can produce is in the closed vocabulary', () {
      final errors = <Object?>[
        FlutterError('x'),
        StateError('x'),
        const SocketException('x'),
        Object(),
        'a thrown string',
        null,
      ];
      final libraries = <String?>[
        ...kTelemetryFlutterLibraryTokens.keys,
        'crux_workspace',
        null,
      ];
      final wide = TelemetryUncaughtErrorCounter(inert: false, sessionCap: 1000)
        ..attach(service);
      for (final error in errors) {
        wide.recordPlatformError(error ?? 'null');
        for (final library in libraries) {
          wide.recordFlutterError(_details(error ?? 'null', library: library));
        }
      }

      expect(service.events, isNotEmpty);
      for (final event in service.events) {
        final p = event.properties;
        expect(kTelemetryUncaughtErrorSources, contains(p['source']));
        expect(kTelemetryUncaughtErrorKinds, contains(p['kind']));
        expect(kTelemetryUncaughtErrorLibraries, contains(p['library']));
        expect(p['silent'], isA<bool>());
      }
    });
  });

  group('once per session per (source, kind, library)', () {
    test('a repeat of the same tuple is not recorded again', () {
      for (var i = 0; i < 50; i++) {
        counter.recordFlutterError(_details(StateError('attempt $i')));
      }
      expect(service.events, hasLength(1));
      expect(counter.countedTuples, 1);
    });

    test('silent is not part of the tuple — the first answer stands', () {
      counter
        ..recordFlutterError(_details(StateError('x'), silent: true))
        ..recordFlutterError(_details(StateError('x')));
      expect(service.events.single.properties['silent'], isTrue);
    });

    test('a different kind, library or source is a new tuple', () {
      counter
        ..recordFlutterError(_details(StateError('x')))
        ..recordFlutterError(_details(ArgumentError('x')))
        ..recordFlutterError(
          _details(StateError('x'), library: 'rendering library'),
        )
        ..recordPlatformError(StateError('x'));
      expect(
        service.events.map(
          (e) => (
            e.properties['source'],
            e.properties['kind'],
            e.properties['library'],
          ),
        ),
        <(Object?, Object?, Object?)>[
          ('flutter', 'state_error', 'widgets'),
          ('flutter', 'argument_error', 'widgets'),
          ('flutter', 'state_error', 'rendering'),
          ('platform', 'state_error', 'none'),
        ],
      );
    });

    test('two spellings of one framework library are one tuple', () {
      counter
        ..recordFlutterError(_details(StateError('x')))
        ..recordFlutterError(_details(StateError('x'), library: 'widgets'));
      expect(service.events, hasLength(1));
    });
  });

  group('the session cap', () {
    test('defaults to $kTelemetryUncaughtErrorSessionCap tuples', () {
      expect(counter.sessionCap, kTelemetryUncaughtErrorSessionCap);
      expect(kTelemetryUncaughtErrorSessionCap, 10);
    });

    test('stops recording new tuples once reached', () {
      final libraries = kTelemetryFlutterLibraryTokens.keys.toList();
      // More distinct tuples than the cap: every kind the SDK can produce, on
      // two sources.
      final errors = <Object>[
        StateError('x'),
        ArgumentError('x'),
        RangeError('x'),
        const FormatException('x'),
        TypeError(),
        UnsupportedError('x'),
        AssertionError('x'),
        FlutterError('x'),
      ];
      for (final error in errors) {
        counter.recordPlatformError(error);
        for (final library in libraries) {
          counter.recordFlutterError(_details(error, library: library));
        }
      }

      expect(service.events, hasLength(kTelemetryUncaughtErrorSessionCap));
      expect(counter.countedTuples, kTelemetryUncaughtErrorSessionCap);
    });

    test('an already-counted tuple past the cap is still not a new row', () {
      final small = TelemetryUncaughtErrorCounter(inert: false, sessionCap: 2)
        ..attach(service)
        ..recordPlatformError(StateError('a'))
        ..recordPlatformError(ArgumentError('b'))
        ..recordPlatformError(StateError('a again'))
        ..recordPlatformError(TypeError());
      expect(service.events, hasLength(2));
      expect(small.countedTuples, 2);
    });
  });

  group('before a service is attached', () {
    late TelemetryUncaughtErrorCounter early;

    setUp(() => early = TelemetryUncaughtErrorCounter(inert: false));

    test('buffers, deduplicated, and bounded by the cap', () {
      for (var i = 0; i < 100; i++) {
        early
          ..recordPlatformError(StateError('$i'))
          ..recordFlutterError(_details(ArgumentError('$i')));
      }
      expect(early.unattached, hasLength(2));

      final flood = TelemetryUncaughtErrorCounter(inert: false, sessionCap: 3);
      for (final library in kTelemetryFlutterLibraryTokens.keys) {
        flood.recordFlutterError(_details(StateError('x'), library: library));
      }
      expect(flood.unattached, hasLength(3));
    });

    test('attach hands the buffer over, in order, exactly once', () {
      early
        ..recordPlatformError(StateError('first'))
        ..recordFlutterError(_details(TypeError()));

      final later = _Recording();
      early.attach(later);

      expect(later.events.map((e) => e.properties['kind']), <String>[
        'state_error',
        'type_error',
      ]);
      expect(early.unattached, isEmpty);

      early.recordPlatformError(const FormatException('after'));
      expect(later.events, hasLength(3), reason: 'straight to the service');

      final another = _Recording();
      early.attach(another);
      expect(another.events, isEmpty, reason: 'handed over once, not copied');
    });

    test('attaching the no-op drops the buffer — consent off', () {
      early
        ..recordPlatformError(StateError('x'))
        ..attach(const NoopTelemetryService());
      expect(early.unattached, isEmpty);

      final afterwards = _Recording();
      early
        ..recordPlatformError(ArgumentError('x'))
        ..attach(afterwards);
      expect(
        afterwards.events,
        isEmpty,
        reason: 'recorded while the no-op was attached, so discarded',
      );
    });

    test('detach returns to buffering, and only for the attached service', () {
      final first = _Recording();
      final second = _Recording();
      early
        ..attach(first)
        ..attach(second)
        // A container torn down after a newer one attached must not detach it.
        ..detach(first)
        ..recordPlatformError(StateError('x'));
      expect(second.events, hasLength(1));

      early
        ..detach(second)
        ..recordPlatformError(ArgumentError('x'));
      expect(second.events, hasLength(1));
      expect(early.unattached, hasLength(1));
    });
  });

  group('inert in a build that cannot transmit', () {
    test('counts, buffers and sends nothing', () {
      final inert = TelemetryUncaughtErrorCounter(inert: true);
      final sink = _Recording();
      inert
        ..recordPlatformError(StateError('x'))
        ..recordFlutterError(_details(StateError('x')));
      expect(inert.unattached, isEmpty);
      expect(inert.countedTuples, 0);

      inert
        ..attach(sink)
        ..recordPlatformError(ArgumentError('x'));
      expect(sink.events, isEmpty);
    });

    test('defaults to the dark-launch condition', () {
      // `TELEMETRY_DEV` is off in the test runner, so the default follows the
      // beta flag alone.
      expect(TelemetryUncaughtErrorCounter().inert, kBetaPeriod);
      expect(TelemetryUncaughtErrorCounter.instance.inert, kBetaPeriod);
    });
  });

  group('never throws into the error handler it runs in', () {
    test('a service that throws is contained', () {
      final guarded = TelemetryUncaughtErrorCounter(inert: false)
        ..recordPlatformError(StateError('buffered'));
      expect(() => guarded.attach(_Throwing()), returnsNormally);
      expect(
        () => guarded.recordPlatformError(ArgumentError('live')),
        returnsNormally,
      );
    });

    test(
      'an error raised while recording is not counted, and cannot recurse',
      () {
        final guarded = TelemetryUncaughtErrorCounter(inert: false);
        final reentrant = _Reentrant(guarded);
        guarded
          ..attach(reentrant)
          ..recordPlatformError(StateError('x'));
        expect(reentrant.events, hasLength(1));
        expect(guarded.countedTuples, 1);
      },
    );
  });
}
