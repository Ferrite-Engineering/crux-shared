// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('crux_telemetry_queue');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  TelemetryEventQueue queueIn(
    Directory dir, {
    int maxEvents = kTelemetryMaxQueuedEvents,
    Duration maxAge = kTelemetryEventMaxAge,
  }) => TelemetryEventQueue(
    directoryFactory: () async => dir,
    maxEvents: maxEvents,
    maxAge: maxAge,
  );

  TelemetryEvent eventAt(
    String name,
    DateTime timestamp, {
    Map<String, Object?>? properties,
  }) => TelemetryEvent(name, properties: properties, timestamp: timestamp);

  final now = DateTime.utc(2026, 8, 4, 9, 15);

  group('hasPersistentBacking', () {
    // What the answer decides is the whole flush cadence: with no file there is
    // no next launch to hand the queue to, so `LiveTelemetryService` switches
    // to its near-term window. Getting this wrong in either direction is
    // either a web build that reports nothing or a desktop build that POSTs
    // every minute.

    test('true when a directory resolves', () async {
      expect(await queueIn(temp).hasPersistentBacking(), isTrue);
    });

    test(
      'false when the directory cannot be resolved — the web case',
      () async {
        // Exactly what web presents: `path_provider` has no web implementation,
        // so `getApplicationSupportDirectory()` throws.
        final queue = TelemetryEventQueue(
          directoryFactory: () async =>
              throw const FileSystemException('no app support dir'),
        );

        expect(await queue.hasPersistentBacking(), isFalse);
        // And the rest of the surface degrades in step, as it always has.
        await queue.append(TelemetryEvent('tab.opened'));
        expect(await queue.load(now: now), isEmpty);
      },
    );

    test('asked rather than inferred from an empty load', () async {
      // A healthy first launch on disk also loads empty. Inferring volatility
      // from that would put every desktop first launch on the web cadence.
      final queue = queueIn(temp);
      expect(await queue.load(now: now), isEmpty);
      expect(await queue.hasPersistentBacking(), isTrue);
    });
  });

  group('append + load', () {
    test('round-trips name, properties and timestamp', () async {
      final queue = queueIn(temp);
      await queue.append(
        eventAt(
          'decoder.opened',
          now.subtract(const Duration(minutes: 5)),
          properties: <String, Object?>{'decoder': 'spi'},
        ),
      );
      await queue.append(eventAt('workspace.restored', now));

      final loaded = await queue.load(now: now);

      expect(loaded, hasLength(2));
      expect(loaded.first.name, 'decoder.opened');
      expect(loaded.first.properties, <String, Object?>{'decoder': 'spi'});
      expect(
        loaded.first.timestamp,
        now.subtract(const Duration(minutes: 5)),
      );
      expect(loaded.last.name, 'workspace.restored');
    });

    test('appends across queue instances — the file is the handover', () async {
      await queueIn(temp).append(eventAt('tab.opened', now));
      await queueIn(temp).append(eventAt('pane.split', now));

      final loaded = await queueIn(temp).load(now: now);
      expect(loaded.map((e) => e.name), <String>['tab.opened', 'pane.split']);
    });

    test('a corrupt line costs that line, not the queue', () async {
      final queue = queueIn(temp);
      await queue.append(eventAt('tab.opened', now));
      File('${temp.path}/${TelemetryEventQueue.fileName}').writeAsStringSync(
        '{ this is not json\n',
        mode: FileMode.append,
      );
      await queue.append(eventAt('pane.split', now));

      final loaded = await queue.load(now: now);
      expect(loaded.map((e) => e.name), <String>['tab.opened', 'pane.split']);
    });

    test('returns empty when nothing has ever been written', () async {
      expect(await queueIn(temp).load(now: now), isEmpty);
    });
  });

  group('replaceAll', () {
    test('rewrites the file to exactly what is given', () async {
      final queue = queueIn(temp);
      await queue.append(eventAt('tab.opened', now));
      await queue.append(eventAt('pane.split', now));

      await queue.replaceAll(<TelemetryEvent>[eventAt('pane.closed', now)]);

      final loaded = await queue.load(now: now);
      expect(loaded.map((e) => e.name), <String>['pane.closed']);
    });

    test('leaves no file behind when the queue drains', () async {
      final queue = queueIn(temp);
      await queue.append(eventAt('tab.opened', now));
      await queue.replaceAll(<TelemetryEvent>[]);

      expect(
        File('${temp.path}/${TelemetryEventQueue.fileName}').existsSync(),
        isFalse,
      );
    });
  });

  group('degradation', () {
    test(
      'a directory factory that throws is memory-only, not an error',
      () async {
        final queue = TelemetryEventQueue(
          directoryFactory: () async =>
              throw const FileSystemException('no app support dir'),
        );

        await queue.append(eventAt('tab.opened', now));
        await queue.replaceAll(<TelemetryEvent>[eventAt('pane.split', now)]);

        expect(await queue.load(now: now), isEmpty);
      },
    );
  });

  group('pruneTelemetryEvents', () {
    test('drops events older than seven days', () {
      final kept = pruneTelemetryEvents(
        <TelemetryEvent>[
          eventAt('old', now.subtract(const Duration(days: 8))),
          eventAt('edge', now.subtract(const Duration(days: 7))),
          eventAt('fresh', now.subtract(const Duration(days: 6, hours: 23))),
        ],
        now: now,
      );
      // The 7-day boundary itself is retained; only strictly older goes.
      expect(kept.map((e) => e.name), <String>['edge', 'fresh']);
    });

    test('the disk load applies the age prune', () async {
      final queue = queueIn(temp);
      await queue.append(
        eventAt('stale', now.subtract(const Duration(days: 9))),
      );
      await queue.append(eventAt('recent', now));

      expect(
        (await queue.load(now: now)).map((e) => e.name),
        <String>['recent'],
      );
    });

    test('caps at 2000 by dropping the OLDEST', () {
      final events = <TelemetryEvent>[
        for (var i = 0; i < 2500; i++)
          eventAt('e$i', now.subtract(Duration(seconds: 2500 - i))),
      ];

      final kept = pruneTelemetryEvents(events, now: now);

      expect(kept, hasLength(kTelemetryMaxQueuedEvents));
      expect(kept.first.name, 'e500');
      expect(kept.last.name, 'e2499');
    });

    test('the cap is 2000', () {
      expect(kTelemetryMaxQueuedEvents, 2000);
      expect(kTelemetryEventMaxAge, const Duration(days: 7));
    });

    test('age is applied before the cap', () {
      // Two stale events plus three fresh ones, cap of three: the stale pair
      // must not consume cap slots the fresh events need.
      final kept = pruneTelemetryEvents(
        <TelemetryEvent>[
          eventAt('stale1', now.subtract(const Duration(days: 9))),
          eventAt('stale2', now.subtract(const Duration(days: 8))),
          eventAt('a', now.subtract(const Duration(minutes: 3))),
          eventAt('b', now.subtract(const Duration(minutes: 2))),
          eventAt('c', now.subtract(const Duration(minutes: 1))),
        ],
        now: now,
        maxEvents: 3,
      );
      expect(kept.map((e) => e.name), <String>['a', 'b', 'c']);
    });
  });
}
