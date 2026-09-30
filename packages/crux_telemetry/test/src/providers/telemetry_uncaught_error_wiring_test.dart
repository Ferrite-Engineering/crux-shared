// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart' show FlutterErrorDetails;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../harness.dart';

/// The uncaught-error counter through the real gate.
///
/// The counter has no consent logic of its own — it hands its events to
/// whatever `telemetryServiceProvider` resolved — so these tests are about
/// that hand-off: the gate that decides for every other event decides for
/// this one too, including for the errors that happened before there was a
/// container to ask.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Boots a container the way a product does, with storage that holds the
  /// consent load open until [release] is called, so the pending window is
  /// observable.
  ({
    ProviderContainer container,
    List<http.BaseRequest> requests,
    void Function() release,
  })
  boot({
    required TelemetryUncaughtErrorCounter counter,
    TelemetryConsentState? stored,
    bool beta = false,
    bool dev = false,
    TelemetryPolicy policy = TelemetryPolicy.absent,
  }) {
    final gate = Completer<void>();
    final sent = <http.BaseRequest>[];
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(
          _GatedStorage(
            InMemoryTelemetryStorage(<String, String>{
              if (stored != null) kTelemetryConsentKey: stored.name,
            }),
            gate.future,
          ),
        ),
        telemetryBetaPeriodProvider.overrideWithValue(beta),
        telemetryDevModeProvider.overrideWithValue(dev),
        telemetryPolicyProvider.overrideWithValue(policy),
        telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
        telemetryUncaughtErrorCounterProvider.overrideWithValue(counter),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            sent.add(request);
            return http.Response('{"accepted":1,"dropped":0}', 202);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, requests: sent, release: gate.complete);
  }

  late TelemetryUncaughtErrorCounter counter;

  setUp(() {
    // A post-beta counter. The default instance is inert in a beta build, and
    // these tests are about the gate, not about that.
    counter = TelemetryUncaughtErrorCounter(inert: false);
  });

  Iterable<TelemetryEvent> uncaught(Iterable<TelemetryEvent> events) =>
      events.where((e) => e.name == kTelemetryUncaughtErrorEvent);

  test('with consent, startup errors reach the live queue', () async {
    // Before the container exists — the handlers are installed ahead of
    // runApp, so this is where a startup crash lands.
    counter
      ..recordPlatformError(StateError('before runApp'))
      ..recordPlatformError(ArgumentError('before runApp'));
    expect(counter.unattached, hasLength(2));

    final app = boot(counter: counter, stored: TelemetryConsentState.enabled);
    app.container.read(telemetryServiceProvider);
    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);

    final live = app.container.read(telemetryServiceProvider);
    expect(live, isA<LiveTelemetryService>());
    counter.recordPlatformError(const FormatException('after'));

    expect(
      uncaught(
        (live as LiveTelemetryService).pending,
      ).map((e) => e.properties['kind']).toList(),
      <String>['state_error', 'argument_error', 'format_exception'],
    );
    expect(counter.unattached, isEmpty);

    await live.flush();
    final body = (app.requests.single as http.Request).body;
    final events =
        (jsonDecode(body) as Map<String, Object?>)['events']! as List<Object?>;
    expect(
      events.cast<Map<String, Object?>>().where(
        (e) => e['name'] == 'app.uncaught_error',
      ),
      hasLength(3),
    );
    expect(body, isNot(contains('before runApp')));
  });

  test('consent off: nothing is recorded, not even queued', () async {
    counter.recordPlatformError(StateError('before runApp'));

    final app = boot(counter: counter, stored: TelemetryConsentState.disabled);
    app.container.read(telemetryServiceProvider);
    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);

    final service = app.container.read(telemetryServiceProvider);
    expect(service, isA<NoopTelemetryService>());
    counter
      ..recordPlatformError(ArgumentError('after'))
      ..recordFlutterError(
        FlutterErrorDetails(exception: TypeError(), library: 'widgets library'),
      );

    expect(counter.unattached, isEmpty, reason: 'dropped at the gate');
    expect(app.container.read(telemetryPendingBufferProvider), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(app.requests, isEmpty);
  });

  test('an unanswered disclosure is not consent', () async {
    // Post-beta, `unset` without the dev flag closes the gate — the EEA
    // default before the disclosure is answered. Closed, but not for good:
    // the disclosure is on screen, so the error the launch produced waits in
    // memory for its answer exactly as it did while the store was loading,
    // and nothing is sent until that answer is yes.
    counter.recordPlatformError(StateError('x'));
    final app = boot(counter: counter);
    app.container.read(telemetryServiceProvider);
    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);

    expect(
      app.container.read(telemetryServiceProvider),
      isA<PendingTelemetryService>(),
    );
    expect(counter.unattached, isEmpty);
    expect(
      uncaught(app.container.read(telemetryPendingBufferProvider)),
      hasLength(1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(app.requests, isEmpty, reason: 'waiting is not collecting');
  });

  test('while consent is loading the errors wait in memory, then go', () async {
    final app = boot(counter: counter, stored: TelemetryConsentState.enabled);
    expect(
      app.container.read(telemetryServiceProvider),
      isA<PendingTelemetryService>(),
    );

    counter.recordPlatformError(StateError('during the load'));
    expect(
      uncaught(app.container.read(telemetryPendingBufferProvider)),
      hasLength(1),
    );
    expect(app.requests, isEmpty, reason: 'buffering is not collecting');

    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);
    final live = app.container.read(telemetryServiceProvider);
    expect(uncaught((live as LiveTelemetryService).pending), hasLength(1));
  });

  test('while consent is loading, a refusal drops what waited', () async {
    final app = boot(counter: counter, stored: TelemetryConsentState.disabled);
    app.container.read(telemetryServiceProvider);
    counter.recordPlatformError(StateError('during the load'));
    expect(app.container.read(telemetryPendingBufferProvider), hasLength(1));

    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);
    expect(
      app.container.read(telemetryServiceProvider),
      isA<NoopTelemetryService>(),
    );
    expect(app.container.read(telemetryPendingBufferProvider), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(app.requests, isEmpty);
  });

  test('the beta gate closes it even for a counter that is not inert', () {
    counter.recordPlatformError(StateError('x'));
    final app = boot(
      counter: counter,
      beta: true,
      stored: TelemetryConsentState.enabled,
    );
    expect(
      app.container.read(telemetryServiceProvider),
      isA<NoopTelemetryService>(),
    );
    expect(counter.unattached, isEmpty);
  });

  test('an Enterprise deny closes it', () {
    counter.recordPlatformError(StateError('x'));
    final app = boot(
      counter: counter,
      stored: TelemetryConsentState.enabled,
      policy: TelemetryPolicy.deny,
    );
    expect(
      app.container.read(telemetryServiceProvider),
      isA<NoopTelemetryService>(),
    );
    expect(counter.unattached, isEmpty);
  });

  test('disposing the container detaches the counter', () async {
    final app = boot(counter: counter, stored: TelemetryConsentState.enabled);
    app.container.read(telemetryServiceProvider);
    app.release();
    await app.container.read(telemetryConsentReadyProvider.future);
    app.container.read(telemetryServiceProvider);

    app.container.dispose();
    counter.recordPlatformError(StateError('after dispose'));
    expect(counter.unattached, hasLength(1));
  });

  test('a product that replaces the service attaches nothing', () {
    // An editor host relays events to its own sender through an override of
    // `telemetryServiceProvider`; the counter never reaches that sender.
    final relay = _Recording();
    final container = ProviderContainer(
      overrides: [
        telemetryServiceProvider.overrideWithValue(relay),
        telemetryUncaughtErrorCounterProvider.overrideWithValue(counter),
      ],
    );
    addTearDown(container.dispose);
    container.read(telemetryServiceProvider);

    counter.recordPlatformError(StateError('x'));
    expect(relay.events, isEmpty);
    expect(counter.unattached, hasLength(1));
  });

  test('the default binding is the process-wide counter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(telemetryUncaughtErrorCounterProvider),
      same(TelemetryUncaughtErrorCounter.instance),
    );
  });
}

class _Recording implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}

/// Storage whose reads complete only once [_gate] does — the cold-start window
/// held open.
class _GatedStorage extends TelemetryStorage {
  const _GatedStorage(this._inner, this._gate);

  final TelemetryStorage _inner;
  final Future<void> _gate;

  @override
  Future<String?> read(String key) async {
    await _gate;
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> remove(String key) => _inner.remove(key);
}
