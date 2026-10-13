// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

class _Capturing implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('crux_unclean_shutdown_');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File markerFor(int pid) => File(
    '${dir.path}${Platform.pathSeparator}'
    '${TelemetryUncleanShutdownDetector.markerPrefix}$pid'
    '${TelemetryUncleanShutdownDetector.markerSuffix}',
  );

  /// A post-beta, release, desktop detector with the event switched on unless
  /// a test says otherwise. [held] lists the marker files a live process holds.
  TelemetryUncleanShutdownDetector detector({
    bool eventEnabled = true,
    bool supported = true,
    bool inert = false,
    Set<String> held = const <String>{},
    int processId = 4242,
  }) => TelemetryUncleanShutdownDetector(
    directoryFactory: () async => dir,
    markerHeld: (file) => held.contains(file.path),
    eventEnabled: eventEnabled,
    supported: supported,
    inert: inert,
    processId: processId,
    installLifecycleListener: false,
  );

  Iterable<TelemetryEvent> unclean(Iterable<TelemetryEvent> events) =>
      events.where((e) => e.name == kTelemetryUncleanShutdownEvent);

  test('the event ships switched off', () {
    expect(kCruxUncleanShutdownEventEnabled, isFalse);
    expect(kTelemetryUncleanShutdownEvent, 'app.unclean_shutdown');
  });

  test('a stale marker records one event and is replaced by this '
      "session's", () async {
    markerFor(100).createSync();
    markerFor(101).createSync();
    final d = detector();
    final service = _Capturing();
    d.attach(service);

    expect(await d.start(), isTrue);

    final events = unclean(service.events).toList();
    expect(events, hasLength(1));
    expect(events.single.properties, isEmpty);
    expect(markerFor(100).existsSync(), isFalse);
    expect(markerFor(101).existsSync(), isFalse);
    expect(markerFor(4242).existsSync(), isTrue);
    d.markCleanExit();
  });

  test('no marker: no event, and this session is marked', () async {
    final d = detector();
    final service = _Capturing();
    d.attach(service);

    expect(await d.start(), isFalse);
    expect(service.events, isEmpty);
    expect(markerFor(4242).existsSync(), isTrue);
    d.markCleanExit();
  });

  test(
    'a clean exit removes the marker, so the next launch is clean',
    () async {
      final first = detector();
      await first.start();
      first.markCleanExit();
      expect(markerFor(4242).existsSync(), isFalse);

      final next = detector(processId: 4343);
      final service = _Capturing();
      next.attach(service);
      expect(await next.start(), isFalse);
      expect(service.events, isEmpty);
      next.markCleanExit();
    },
  );

  test('a marker a live instance still holds is not an unclean shutdown', () {
    final live = markerFor(77)..createSync();
    final d = detector(held: <String>{live.path});
    final service = _Capturing();
    d.attach(service);

    return d.start().then((result) {
      expect(result, isFalse);
      expect(service.events, isEmpty);
      expect(live.existsSync(), isTrue);
      d.markCleanExit();
    });
  });

  test('with the event switched off the marker still rotates and nothing is '
      'recorded', () async {
    markerFor(100).createSync();
    final d = detector(eventEnabled: false);
    final service = _Capturing();
    d.attach(service);

    expect(await d.start(), isTrue);
    expect(service.events, isEmpty);
    expect(d.unattached, isNull);
    expect(markerFor(100).existsSync(), isFalse);
    expect(markerFor(4242).existsSync(), isTrue);
    d.markCleanExit();
  });

  test('a build that can never transmit constructs no event, and still '
      'rotates the marker', () async {
    markerFor(100).createSync();
    final d = detector(inert: true);
    final service = _Capturing();
    d.attach(service);

    expect(await d.start(), isTrue);
    expect(service.events, isEmpty);
    expect(markerFor(4242).existsSync(), isTrue);
    d.markCleanExit();
  });

  test('telemetry off: the no-op discards the event, the marker rotates', () {
    markerFor(100).createSync();
    final d = detector()..attach(const NoopTelemetryService());
    return d.start().then((result) {
      expect(result, isTrue);
      expect(d.unattached, isNull);
      expect(markerFor(4242).existsSync(), isTrue);
      d.markCleanExit();
    });
  });

  test('off the desktop, or in a debug build, nothing is read or written', () {
    markerFor(100).createSync();
    final d = detector(supported: false);
    final service = _Capturing();
    d.attach(service);
    return d.start().then((result) {
      expect(result, isFalse);
      expect(service.events, isEmpty);
      expect(markerFor(100).existsSync(), isTrue);
      expect(markerFor(4242).existsSync(), isFalse);
    });
  });

  test('an event found before any service is attached waits for one', () async {
    markerFor(100).createSync();
    final d = detector();
    expect(await d.start(), isTrue);
    expect(d.unattached?.name, kTelemetryUncleanShutdownEvent);

    final service = _Capturing();
    d.attach(service);
    expect(unclean(service.events), hasLength(1));
    expect(d.unattached, isNull);
    d.markCleanExit();
  });

  test('start is idempotent', () async {
    markerFor(100).createSync();
    final d = detector();
    final service = _Capturing();
    d.attach(service);
    final first = d.start();
    final second = d.start();
    expect(identical(first, second), isTrue);
    await first;
    expect(unclean(service.events), hasLength(1));
    d.markCleanExit();
  });

  test('the production probe reads an unlocked marker as abandoned', () async {
    markerFor(100).createSync();
    final d = TelemetryUncleanShutdownDetector(
      directoryFactory: () async => dir,
      eventEnabled: true,
      supported: true,
      inert: false,
      processId: 4242,
      installLifecycleListener: false,
    );
    expect(await d.start(), isTrue);
    expect(markerFor(100).existsSync(), isFalse);
    d.markCleanExit();
  });

  testWidgets('the detached lifecycle state is a clean exit', (tester) async {
    final d = TelemetryUncleanShutdownDetector(
      directoryFactory: () async => dir,
      markerHeld: (_) => false,
      eventEnabled: true,
      supported: true,
      inert: false,
      processId: 4242,
    );
    await tester.runAsync(d.start);
    expect(markerFor(4242).existsSync(), isTrue);

    const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    expect(markerFor(4242).existsSync(), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('telemetryServiceProvider starts the detector and attaches the service '
      'it resolved', () async {
    markerFor(100).createSync();
    final d = detector();
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        telemetryBetaPeriodProvider.overrideWithValue(true),
        telemetryUncleanShutdownDetectorProvider.overrideWithValue(d),
      ],
    );
    addTearDown(container.dispose);

    // During the beta the gate is closed for good: the no-op is attached, so
    // the event the detector found is discarded rather than left waiting.
    expect(
      container.read(telemetryServiceProvider),
      isA<NoopTelemetryService>(),
    );
    expect(await d.start(), isTrue);
    expect(d.unattached, isNull);
    expect(markerFor(4242).existsSync(), isTrue);
    d.markCleanExit();
  });
}
