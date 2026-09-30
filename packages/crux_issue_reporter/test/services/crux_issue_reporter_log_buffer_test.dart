// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  CruxIssueLogEntry entryAt(
    int second, {
    Level level = Level.INFO,
    String msg = 'm',
  }) => CruxIssueLogEntry(
    timestamp: DateTime.utc(2026, 6, 6, 0, 0, second),
    level: level,
    loggerName: 'test',
    message: msg,
  );

  group('CruxIssueReporterLogBuffer', () {
    test('defaults to a 500-entry ring', () {
      expect(CruxIssueReporterLogBuffer.defaultCapacity, 500);
      expect(CruxIssueReporterLogBuffer().capacity, 500);
    });

    test('rejects a non-positive capacity', () {
      expect(
        () => CruxIssueReporterLogBuffer(capacity: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('evicts oldest entries past capacity (ring overflow)', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 3);
      for (var i = 0; i < 5; i++) {
        buffer.add(entryAt(i, msg: 'm$i'));
      }
      expect(buffer.length, 3);
      final all = buffer.recentEntries(10);
      expect(all.map((e) => e.message).toList(), ['m2', 'm3', 'm4']);
    });

    test('recentEntries returns the most recent N in chronological order', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 100);
      for (var i = 0; i < 10; i++) {
        buffer.add(entryAt(i, msg: 'm$i'));
      }
      final recent = buffer.recentEntries(3);
      expect(recent.map((e) => e.message).toList(), ['m7', 'm8', 'm9']);
      // Timestamps ascend: the report renders oldest-first.
      expect(
        recent.map((e) => e.timestamp).toList(),
        orderedEquals(<DateTime>[
          DateTime.utc(2026, 6, 6, 0, 0, 7),
          DateTime.utc(2026, 6, 6, 0, 0, 8),
          DateTime.utc(2026, 6, 6, 0, 0, 9),
        ]),
      );
    });

    test('minLevel filters out entries below the threshold', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 100)
        ..add(entryAt(0, level: Level.FINE, msg: 'fine'))
        ..add(entryAt(1, msg: 'info'))
        ..add(entryAt(2, level: Level.WARNING, msg: 'warn'))
        ..add(entryAt(3, level: Level.SEVERE, msg: 'severe'));

      final warnings = buffer.recentEntries(100, minLevel: Level.WARNING);
      expect(warnings.map((e) => e.message).toList(), ['warn', 'severe']);
    });

    test('minLevel + count takes the most-recent matching entries', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 100);
      for (var i = 0; i < 6; i++) {
        buffer.add(entryAt(i, level: Level.WARNING, msg: 'w$i'));
      }
      final last2 = buffer.recentEntries(2, minLevel: Level.WARNING);
      expect(last2.map((e) => e.message).toList(), ['w4', 'w5']);
    });

    test('recentEntries(0) and empty buffer return empty', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 5);
      expect(buffer.recentEntries(0), isEmpty);
      expect(buffer.recentEntries(10), isEmpty);
    });

    test('clear empties the buffer', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 5)
        ..add(entryAt(0))
        ..add(entryAt(1));
      expect(buffer.length, 2);
      buffer.clear();
      expect(buffer.length, 0);
    });

    test('entries exposes an immutable oldest-first snapshot', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 5)
        ..add(entryAt(0, msg: 'a'))
        ..add(entryAt(1, msg: 'b'));
      expect(buffer.entries.map((e) => e.message).toList(), ['a', 'b']);
      expect(() => buffer.entries.add(entryAt(2)), throwsUnsupportedError);
    });

    test('notifies listeners on add and clear (live Logs panel)', () {
      final buffer = CruxIssueReporterLogBuffer(capacity: 5);
      var notifications = 0;
      void listener() => notifications++;
      buffer.addListener(listener);
      addTearDown(() => buffer.removeListener(listener));

      buffer.add(entryAt(0));
      expect(notifications, 1);
      buffer.clear();
      expect(notifications, 2);
    });

    test('toString renders level, logger and message', () {
      expect(
        entryAt(0, level: Level.WARNING, msg: 'oops').toString(),
        contains('WARNING test: oops'),
      );
    });

    test(
      'attachToLogging captures emitted records and is idempotent',
      () async {
        final buffer = CruxIssueReporterLogBuffer(capacity: 10)
          ..attachToLogging()
          // Second call must not double-subscribe.
          ..attachToLogging();
        addTearDown(buffer.detach);

        Logger('attach.test').warning('captured warning');
        // Logging delivers records asynchronously through a broadcast stream.
        await Future<void>.delayed(Duration.zero);

        final captured = buffer.recentEntries(10, minLevel: Level.WARNING);
        expect(captured, hasLength(1));
        expect(captured.last.message, 'captured warning');
        expect(captured.last.loggerName, 'attach.test');
      },
    );

    test(
      'captureFlutterErrors routes framework errors into the buffer',
      () async {
        final originalOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = originalOnError);
        // Swallow so the chained previous handler doesn't fail this test via
        // the flutter_test error reporter.
        FlutterError.onError = (_) {};

        final buffer = CruxIssueReporterLogBuffer(capacity: 10)
          ..attachToLogging();
        addTearDown(buffer.detach);
        buffer.captureFlutterErrors();

        FlutterError.reportError(
          FlutterErrorDetails(exception: StateError('boom from test')),
        );
        await Future<void>.delayed(Duration.zero);

        final captured = buffer.recentEntries(10, minLevel: Level.SEVERE);
        expect(captured, isNotEmpty);
        expect(captured.last.message, contains('boom from test'));
        expect(captured.last.loggerName, 'flutter');
      },
    );

    test('the SEVERE record for either handler carries the error and its '
        'stack', () async {
      // A listener that prints a record — a product's stderr sink — can only
      // say where an error came from if the record carries the stack. The
      // message alone was a one-line summary with no location.
      final originalOnError = FlutterError.onError;
      final originalDispatcherOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = originalOnError;
        PlatformDispatcher.instance.onError = originalDispatcherOnError;
      });
      FlutterError.onError = (_) {};
      PlatformDispatcher.instance.onError = (_, _) => true;

      final records = <LogRecord>[];
      final sub = Logger.root.onRecord
          .where((r) => r.level >= Level.SEVERE)
          .listen(records.add);
      addTearDown(sub.cancel);
      CruxIssueReporterLogBuffer(capacity: 10).captureFlutterErrors(
        errorCounter: TelemetryUncaughtErrorCounter(inert: true),
      );

      final frameworkError = StateError('framework boom');
      final frameworkStack = StackTrace.fromString('#0 frameworkFrame');
      FlutterError.reportError(
        FlutterErrorDetails(exception: frameworkError, stack: frameworkStack),
      );
      final platformError = ArgumentError('platform boom');
      final platformStack = StackTrace.fromString('#0 platformFrame');
      PlatformDispatcher.instance.onError!(platformError, platformStack);
      await Future<void>.delayed(Duration.zero);

      expect(records, hasLength(2));
      expect(records[0].error, same(frameworkError));
      expect(records[0].stackTrace, same(frameworkStack));
      expect(records[1].error, same(platformError));
      expect(records[1].stackTrace, same(platformStack));
      expect(
        records.map((r) => r.message),
        [contains('framework boom'), 'Uncaught: $platformError'],
        reason: 'the one-line summary the buffer keeps is unchanged',
      );
    });

    test('captureFlutterErrors counts both handlers for telemetry', () {
      final originalOnError = FlutterError.onError;
      final originalDispatcherOnError = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = originalOnError;
        PlatformDispatcher.instance.onError = originalDispatcherOnError;
      });
      FlutterError.onError = (_) {};
      PlatformDispatcher.instance.onError = (_, _) => true;

      final counted = _RecordingTelemetryService();
      final counter = TelemetryUncaughtErrorCounter(inert: false)
        ..attach(counted);
      CruxIssueReporterLogBuffer(
        capacity: 10,
      ).captureFlutterErrors(errorCounter: counter);

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('/Users/someone/secret.v'),
          library: 'rendering library',
        ),
      );
      final handled = PlatformDispatcher.instance.onError!(
        ArgumentError('/Users/someone/secret.v'),
        StackTrace.empty,
      );

      expect(handled, isTrue, reason: 'the previous handler still decides');
      expect(counted.events.map((e) => e.properties), <Map<String, Object?>>[
        <String, Object?>{
          'source': 'flutter',
          'kind': 'state_error',
          'library': 'rendering',
          'silent': false,
        },
        <String, Object?>{
          'source': 'platform',
          'kind': 'argument_error',
          'library': 'none',
          'silent': false,
        },
      ]);
      expect(
        counted.events.every((e) => e.name == kTelemetryUncaughtErrorEvent),
        isTrue,
      );
      expect(counted.events.toString(), isNot(contains('secret')));
    });
  });
}

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}
