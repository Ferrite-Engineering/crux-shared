// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:crux_telemetry_core/crux_telemetry_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_store.dart';

const String _idA = '00000000-0000-4000-8000-00000000000a';
const String _idB = '00000000-0000-4000-8000-00000000000b';

final DateTime _start = DateTime.utc(2026, 11, 23, 10, 15, 30, 250);

const Map<String, Object?> _call = <String, Object?>{
  'tool': 'info',
  'outcome': 'completed',
  'duration': 'lt_1s',
};

/// Every request a test's client was sent.
final class _Wire {
  final List<http.Request> requests = <http.Request>[];
  int status = 202;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    return http.Response('', status);
  });

  List<Map<String, Object?>> get bodies => <Map<String, Object?>>[
    for (final r in requests) jsonDecode(r.body) as Map<String, Object?>,
  ];
}

void main() {
  late _Wire wire;
  setUp(() => wire = _Wire());

  HeadlessTelemetry telemetry(
    List<FakeStore> stores, {
    bool pro = false,
    Map<String, String> environment = const <String, String>{},
    bool betaPeriod = false,
    bool dev = false,
    TelemetryPolicy policy = TelemetryPolicy.absent,
    String licenseTier = 'openCore',
    Duration flushDelay = const Duration(hours: 1),
    CruxTelemetryProduct product = CruxTelemetryProduct.wavecrux,
  }) => HeadlessTelemetry(
    product: product,
    pro: pro,
    appVersion: '2.0.0',
    licenseTier: licenseTier,
    policy: policy,
    environment: environment,
    consent: DesktopTelemetryConsent(stores),
    client: wire.client,
    dev: dev,
    betaPeriod: betaPeriod,
    flushDelay: flushDelay,
    now: () => _start,
    operatingSystem: 'linux',
  );

  test('consent absent: nothing is held and nothing is sent', () async {
    final t = telemetry([FakeStore(), FakeStore()]);
    expect(t.consented(), isFalse);
    t.record('mcp.tool_call', _call);
    expect(t.held, isEmpty);
    await t.close();
    expect(wire.requests, isEmpty);
  });

  test("consent present: one batch, the app's installation id, the same "
      'envelope and endpoint as the app', () async {
    final t = telemetry([FakeStore.answered('enabled', id: _idA)]);
    expect(t.consented(), isTrue);
    t
      ..record('mcp.tool_call', _call)
      ..record('mcp.tool_call', _call);
    await t.close();
    expect(wire.requests, hasLength(1));
    final request = wire.requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://telemetry.edacrux.app/v1/events',
    );
    expect(request.headers['User-Agent'], 'WaveCrux/2.0.0');
    // Written out by hand from the Worker's batch contract (`valid-batch.json`
    // in crux_telemetry's tests): envelope fields in that order, properties
    // sorted by key, two identical calls folded into one row of count 2, the
    // session start cut to whole seconds.
    expect(
      request.body,
      '{"installation_id":"$_idA","app_version":"2.0.0",'
      '"product":"wavecrux","os":"linux","form_factor":"desktop",'
      '"locale":"en","license_tier":"openCore",'
      '"session_start":"2026-11-23T10:15:30Z",'
      '"events":[{"name":"mcp.tool_call",'
      '"properties":{"duration":"lt_1s","outcome":"completed","tool":"info"},'
      '"count":2}]}',
    );
  });

  test('revoked after recording: what was held goes no further', () async {
    final store = FakeStore.answered('enabled', id: _idA);
    final t = telemetry([store])..record('mcp.tool_call', _call);
    expect(t.held, hasLength(1));
    store.values[kTelemetryConsentKey] = 'disabled';
    await t.flush();
    expect(wire.requests, isEmpty);
    expect(t.held, isEmpty);
    expect(t.consented(), isFalse);
  });

  test('revoked, then given again: the new installation id is used', () async {
    final store = FakeStore.answered('disabled');
    final t = telemetry([store])..record('mcp.tool_call', _call);
    expect(t.held, isEmpty);
    store.values
      ..[kTelemetryConsentKey] = 'enabled'
      ..[kTelemetryInstallationIdKey] = _idB;
    t.record('mcp.tool_call', _call);
    await t.close();
    expect(wire.bodies.single['installation_id'], _idB);
  });

  group('the Pro domain', () {
    test("a Pro binary sends under the Pro app's answer and id", () async {
      final t = telemetry([
        FakeStore.answered('enabled', id: _idB),
        FakeStore.answered('enabled', id: _idA),
      ], pro: true)..record('mcp.tool_call', _call);
      await t.close();
      expect(wire.bodies.single['installation_id'], _idB);
    });

    test('the real store order puts the Pro domain first for a Pro binary', () {
      final stores = desktopTelemetryStores(
        CruxTelemetryProduct.wavecrux,
        pro: true,
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/u'},
      );
      expect(
        stores.first.toString(),
        'defaults com.ferriteengineering.wavecruxPro',
      );
    });

    test('a Pro app that declined is not overridden by the open core', () {
      final t = telemetry([
        FakeStore.answered('disabled'),
        FakeStore.answered('enabled', id: _idA),
      ], pro: true);
      expect(t.consented(), isFalse);
    });
  });

  group('CI set: nothing sent', () {
    for (final value in <String>['true', '1', '', 'false']) {
      test('CI=$value', () async {
        final t = telemetry(
          [FakeStore.answered('enabled', id: _idA)],
          environment: <String, String>{'CI': value},
        );
        expect(t.consented(), isFalse);
        t.record('mcp.tool_call', _call);
        await t.close();
        expect(wire.requests, isEmpty);
      });
    }
  });

  test('the beta sends nothing; TELEMETRY_DEV goes to staging', () async {
    final consent = FakeStore.answered('enabled', id: _idA);
    final beta = telemetry([consent], betaPeriod: true)
      ..record('mcp.tool_call', _call);
    await beta.close();
    expect(wire.requests, isEmpty);
    final dev = telemetry([consent], betaPeriod: true, dev: true)
      ..record('mcp.tool_call', _call);
    await dev.close();
    expect(
      wire.requests.single.url.toString(),
      'https://telemetry.edacrux.app/dev/v1/events',
    );
  });

  test('a TELEMETRY_DEV build still needs the recorded consent', () {
    expect(telemetry([FakeStore()], dev: true).consented(), isFalse);
  });

  test('an Enterprise deny wins over a stored yes; allow is not a yes', () {
    expect(
      telemetry([
        FakeStore.answered('enabled', id: _idA),
      ], policy: TelemetryPolicy.deny).consented(),
      isFalse,
    );
    expect(
      telemetry([FakeStore()], policy: TelemetryPolicy.allow).consented(),
      isFalse,
    );
  });

  test('never an argument or a path: such an event is dropped whole', () async {
    final t = telemetry([FakeStore.answered('enabled', id: _idA)])
      ..record('mcp.tool_call', {..._call, 'tool': '/home/u/design.vcd'})
      ..record('mcp.tool_call', {..._call, 'signal': 'top.cpu.pc'})
      ..record('mcp.tool_call', {..._call, 'path': 'a/b'})
      ..record('mcp.tool_call', {..._call, 'Tool': 'info'})
      ..record('mcp.tool_call', {
        ..._call,
        'args': <String>['x'],
      })
      ..record('/tmp/x', _call)
      ..record('mcp.tool_call', {..._call, 'count': 3, 'cached': true});
    expect(t.held, hasLength(1));
    await t.close();
    final events = wire.bodies.single['events']! as List<Object?>;
    expect(events, hasLength(1));
  });

  test('sent by itself after the delay, without close', () async {
    final t = telemetry(
      [FakeStore.answered('enabled', id: _idA)],
      flushDelay: const Duration(milliseconds: 20),
    )..record('mcp.tool_call', _call);
    expect(wire.requests, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(wire.requests, hasLength(1));
    await t.close();
    expect(wire.requests, hasLength(1));
  });

  test('a 5xx or 429 keeps the events; a 4xx drops them', () async {
    final t = telemetry([FakeStore.answered('enabled', id: _idA)])
      ..record('mcp.tool_call', _call);
    wire.status = 503;
    await t.flush();
    expect(t.held, hasLength(1));
    wire.status = 429;
    await t.flush();
    expect(t.held, hasLength(1));
    wire.status = 400;
    await t.flush();
    expect(t.held, isEmpty);
    wire.status = 202;
    await t.close();
    expect(wire.requests, hasLength(3));
  });

  test('a transport failure keeps the events and never throws', () async {
    final t = HeadlessTelemetry(
      product: CruxTelemetryProduct.netcrux,
      pro: false,
      appVersion: '2.0.0',
      environment: const <String, String>{},
      consent: DesktopTelemetryConsent([
        FakeStore.answered('enabled', id: _idA),
      ]),
      client: MockClient((_) => throw http.ClientException('offline')),
      flushDelay: const Duration(hours: 1),
    )..record('mcp.tool_call', _call);
    await t.flush();
    expect(t.held, hasLength(1));
    await t.close();
    expect(t.held, isEmpty);
  });

  test('close is bounded by its budget', () async {
    final never = Completer<http.Response>();
    final t = HeadlessTelemetry(
      product: CruxTelemetryProduct.simcrux,
      pro: false,
      appVersion: '2.0.0',
      environment: const <String, String>{},
      consent: DesktopTelemetryConsent([
        FakeStore.answered('enabled', id: _idA),
      ]),
      client: MockClient((_) => never.future),
      postTimeout: const Duration(hours: 1),
      closeBudget: const Duration(milliseconds: 20),
    )..record('mcp.tool_call', _call);
    final watch = Stopwatch()..start();
    await t.close();
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('after close nothing is recorded', () async {
    final t = telemetry([FakeStore.answered('enabled', id: _idA)]);
    await t.close();
    expect(t.consented(), isFalse);
    t.record('mcp.tool_call', _call);
    expect(t.held, isEmpty);
  });

  test('a wiring mistake is loud: an unknown tier or an empty version', () {
    expect(
      () => telemetry([FakeStore()], licenseTier: 'Pro'),
      throwsArgumentError,
    );
    expect(
      () => HeadlessTelemetry(
        product: CruxTelemetryProduct.lintcrux,
        pro: false,
        appVersion: '',
      ),
      throwsArgumentError,
    );
  });

  test('the beta default matches crux_license', () {
    // crux_license's `kBetaPeriod` defaults to false (beta_period.dart); this
    // copy must too. crux_telemetry's tests compare the two constants.
    expect(kHeadlessTelemetryBetaPeriod, isFalse);
  });

  test('the os slug falls back to linux', () {
    expect(headlessTelemetryOsSlug('macos'), 'macos');
    expect(headlessTelemetryOsSlug('windows'), 'windows');
    expect(headlessTelemetryOsSlug('fuchsia'), 'linux');
    expect(kTelemetryOperatingSystems, contains(headlessTelemetryOsSlug('x')));
  });
}
