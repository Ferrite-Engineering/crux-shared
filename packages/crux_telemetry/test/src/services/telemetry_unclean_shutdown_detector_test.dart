// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show AppExitResponse, AppLifecycleState;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../harness.dart';

/// Stands in for the process ending, so `cruxExit` can return to the test.
class _Exited implements Exception {
  const _Exited();
}

/// A decoder plugin's isolate that is still busy when the user quits.
Future<void> _spin(Object? _) async {
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

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

  test('the event ships switched on', () {
    expect(kCruxUncleanShutdownEventEnabled, isTrue);
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

  testWidgets('an exit request removes the marker', (tester) async {
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

    // What the desktop embedders send for Cmd+Q from the system, an Apple
    // Event quit, the Dock, logout, closing the last window, and WM_CLOSE.
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(markerFor(4242).existsSync(), isFalse);
  });

  testWidgets('an exit request that arrives while start is still finding the '
      'directory leaves no marker behind', (tester) async {
    // macOS answers the quit with NSTerminateCancel and terminates once Dart
    // replies, so a quit right after launch can reach Dart before start has
    // found the application-support directory. The session ends anyway; a
    // marker claimed after that is one the next launch counts as a crash.
    final directory = Completer<Directory>();
    final d = TelemetryUncleanShutdownDetector(
      directoryFactory: () => directory.future,
      markerHeld: (_) => false,
      eventEnabled: true,
      supported: true,
      inert: false,
      processId: 4242,
    );
    final started = d.start();

    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    directory.complete(dir);
    await tester.runAsync(() => started);

    expect(markerFor(4242).existsSync(), isFalse);
    expect(d.marker, isNull);
  });

  test(
    'a clean exit before start keeps start from claiming a marker',
    () async {
      final d = detector()..markCleanExit();
      expect(await d.start(), isFalse);
      expect(markerFor(4242).existsSync(), isFalse);
    },
  );

  test('markCleanExit is idempotent', () async {
    final d = detector();
    await d.start();
    d
      ..markCleanExit()
      ..markCleanExit();
    expect(markerFor(4242).existsSync(), isFalse);
  });

  test('cruxExit removes the marker before the process ends, whatever is '
      'still open', () async {
    final d = detector();
    await d.start();
    expect(markerFor(4242).existsSync(), isTrue);

    // A busy session: a waveform open, a decoder plugin's
    // isolate running, and a dialog still waiting for an answer.
    final document = File('${dir.path}${Platform.pathSeparator}trace.vcd')
      ..writeAsStringSync(r'$timescale 1ns $end');
    final handle = document.openSync();
    addTearDown(handle.closeSync);
    final plugin = await Isolate.spawn(_spin, null);
    addTearDown(() => plugin.kill(priority: Isolate.immediate));
    final dialog = Completer<void>();
    addTearDown(dialog.complete);

    final codes = <int>[];
    debugCruxExitOverride = (code) {
      codes.add(code);
      throw const _Exited();
    };
    addTearDown(() => debugCruxExitOverride = null);

    expect(() => cruxExit(3), throwsA(isA<_Exited>()));
    expect(codes, <int>[3]);
    expect(markerFor(4242).existsSync(), isFalse);
    expect(document.existsSync(), isTrue);
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
