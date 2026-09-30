// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];
  bool closed = false;

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async => closed = true;

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}

/// A sink that fails the way a full disk does. The recorder must survive it —
/// `AuditSink.record` never throwing is a contract emitters rely on to stay
/// synchronous.
class _ThrowingSink implements AuditSink {
  @override
  Future<void> record(AuditEvent event) async => throw StateError('disk full');

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health =>
      AuditSinkHealth.failed('disk full', DateTime.utc(2026));
}

void main() {
  group('CruxAuditRecorder', () {
    test('stamps product, kind, severity, peer and a UTC timestamp', () async {
      final sink = _CapturingSink();
      final recorder = CruxAuditRecorder(
        sink: sink,
        productId: 'lintcrux',
        peerId: 'peer-7',
      );

      await recorder.recordAndFlush(
        'waiver.created',
        payload: <String, Object?>{'waiverId': 'w1'},
      );

      final event = sink.events.single;
      expect(event.product, 'lintcrux');
      expect(event.kind, 'waiver.created');
      expect(event.severity, AuditSeverity.info);
      expect(event.peerId, 'peer-7');
      expect(event.payload, <String, Object?>{'waiverId': 'w1'});
      expect(event.timestamp.isUtc, isTrue);
    });

    test('an explicit `at` is normalised to UTC', () async {
      final sink = _CapturingSink();
      final recorder = CruxAuditRecorder(sink: sink, productId: 'simcrux');

      await recorder.recordAndFlush(
        'regression.started',
        at: DateTime(2026, 8, 21, 13, 45),
      );

      expect(sink.events.single.timestamp.isUtc, isTrue);
    });

    test('omits the peer when the product has none', () async {
      final sink = _CapturingSink();
      final recorder = CruxAuditRecorder(sink: sink, productId: 'wavecrux');

      await recorder.recordAndFlush('session.saved');

      expect(sink.events.single.peerId, isNull);
      expect(sink.events.single.toJson().containsKey('peer'), isFalse);
    });

    test(
      'record() survives a sink that violates the never-throws contract',
      () async {
        final diagnostics = <String>[];
        final recorder = CruxAuditRecorder(
          sink: _ThrowingSink(),
          productId: 'netcrux',
          onDiagnostic: diagnostics.add,
        );

        // The whole point of the void return: an emitter stays synchronous, and
        // a sink that cannot write must never take the call site down with it.
        // `unawaited` alone is NOT enough — the rejected future would
        // surface as an unhandled asynchronous error, which in a Flutter app
        // is a red screen raised by the audit log.
        expect(() => recorder.record('session.saved'), returnsNormally);
        await pumpEventQueue();

        // Dropped, but not silently: a support bundle carries the reason.
        expect(diagnostics, isNotEmpty);
        expect(diagnostics.first, contains('contract'));
        expect(diagnostics.first, contains('disk full'));
      },
    );

    test('recordAndFlush propagates, so a CLI can see the failure', () {
      final recorder = CruxAuditRecorder(
        sink: _ThrowingSink(),
        productId: 'netcrux',
        onDiagnostic: (_) {},
      );
      // The awaitable variant is for a caller who chose to care.
      expect(recorder.recordAndFlush('session.saved'), throwsStateError);
    });
  });

  group('cruxAuditRecorderProvider', () {
    test('defaults to a Noop sink and a product id that is visibly wrong', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final recorder = c.read(cruxAuditRecorderProvider);
      expect(recorder.sink, isA<NoopAuditSink>());
      // Not a plausible-looking default: an event tagged `unconfigured` in a
      // shared file is a wiring bug someone can report.
      expect(recorder.productId, 'unconfigured');
      expect(recorder.peerId, isNull);
    });

    test('a product overrides the id and the peer', () {
      final c = ProviderContainer(
        overrides: [
          cruxAuditProductIdProvider.overrideWithValue('lintcrux'),
          cruxAuditPeerIdProvider.overrideWithValue('peer-42'),
        ],
      );
      addTearDown(c.dispose);
      final recorder = c.read(cruxAuditRecorderProvider);
      expect(recorder.productId, 'lintcrux');
      expect(recorder.peerId, 'peer-42');
    });
  });

  group('CruxSharedAuditKinds', () {
    test('names the three events that describe the shared machinery', () {
      expect(CruxSharedAuditKinds.all, <String>{
        'policy.loaded',
        'policy.rejected',
        'plugin.load.refused',
      });
    });

    test('every shared kind is dotted lower-case, like every product kind', () {
      // One file holds four products' events; a kind that spelled itself
      // differently would be unfilterable next to the rest.
      for (final kind in CruxSharedAuditKinds.all) {
        expect(kind, matches(RegExp(r'^[a-z]+(\.[a-z]+)+$')), reason: kind);
      }
    });
  });
}
