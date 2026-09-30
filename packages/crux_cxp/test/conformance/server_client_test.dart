// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _serverIdentity = PeerIdentity(
  peerId: 'wavecrux-test-server-1',
  productName: 'wavecrux',
  productVersion: '0.0.0-test',
);

PeerIdentity _clientIdentity(int n) => PeerIdentity(
  peerId: 'client-test-$n',
  productName: 'client',
  productVersion: '0.0.0-test',
);

Future<({LocalCxpServer server, LocalCxpClient client})> _connectPair() async {
  final server = LocalCxpServer(selfIdentity: _serverIdentity);
  await server.start();
  final client = LocalCxpClient(selfIdentity: _clientIdentity(1));
  await client.connect(
    host: '127.0.0.1',
    port: server.boundPort!,
    token: server.authToken,
  );
  return (server: server, client: client);
}

Future<void> _tearDownPair(LocalCxpServer server, LocalCxpClient client) async {
  await client.dispose();
  await server.stop();
}

void main() {
  group('Handshake', () {
    test(
      'LocalCxpClient completes Hello/HelloAck with LocalCxpServer',
      () async {
        final pair = await _connectPair();
        expect(pair.client.isConnected, isTrue);
        expect(pair.client.remotePeer?.peerId, _serverIdentity.peerId);
        await _tearDownPair(pair.server, pair.client);
      },
    );

    test('server emits presence event after handshake', () async {
      final server = LocalCxpServer(selfIdentity: _serverIdentity);
      await server.start();
      final presenceFuture = server.presence.first;
      final client = LocalCxpClient(selfIdentity: _clientIdentity(2));
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );
      final event = await presenceFuture.timeout(const Duration(seconds: 2));
      expect(event.connected, isTrue);
      expect(event.peer.peerId, _clientIdentity(2).peerId);
      await client.dispose();
      await server.stop();
    });
  });

  group('Subscribe + broadcast', () {
    test('subscriber receives broadcast messages it asked for', () async {
      final pair = await _connectPair();
      pair.client.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      await pollUntil(
        () => pair.server
            .debugSubscriptionsOf(_clientIdentity(1).peerId)
            .isNotEmpty,
        reason: 'the subscription must register before broadcasting',
      );

      final received = pair.client.inbound.first;
      const message = NotifySelection(
        elements: [ElementId(kind: ElementKind.signal, path: 'top.a')],
      );
      pair.server.broadcast(message);

      final inbound = await received.timeout(const Duration(seconds: 2));
      expect(inbound.message, isA<NotifySelection>());
      expect((inbound.message as NotifySelection).elements.first.path, 'top.a');

      await _tearDownPair(pair.server, pair.client);
    });

    test('subscriber receives nothing after Unsubscribe', () async {
      final pair = await _connectPair();
      pair.client.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      await pollUntil(
        () => pair.server
            .debugSubscriptionsOf(_clientIdentity(1).peerId)
            .isNotEmpty,
        reason: 'the subscription must register first',
      );
      pair.client.send(const Unsubscribe());
      await pollUntil(
        () =>
            pair.server.debugSubscriptionsOf(_clientIdentity(1).peerId).isEmpty,
        reason: 'the unsubscribe must register before broadcasting',
      );

      final received = <CxpClientInbound>[];
      final sub = pair.client.inbound.listen(received.add);
      pair.server.broadcast(
        const NotifySelection(
          elements: [ElementId(kind: ElementKind.signal, path: 'top.a')],
        ),
      );
      // A directed marker bounds the absence check: sendTo bypasses
      // subscriptions and shares the broadcast's socket, so once the
      // marker arrives, the earlier broadcast would already have been
      // delivered if it had been sent.
      pair.server.sendTo(
        _clientIdentity(1).peerId,
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.marker'),
        ),
      );
      await pollUntil(
        () => received.any((m) => m.message is RequestHighlight),
        reason: 'the directed marker must arrive',
      );
      await sub.cancel();

      expect(received.where((m) => m.message is NotifySelection), isEmpty);
      await _tearDownPair(pair.server, pair.client);
    });
  });

  // Public-contract conformance: the server MUST drop a broadcast that does
  // not match a subscriber's filter. The filter predicate (CxpSubscription.
  // matches) is unit-tested in isolation; these pin the end-to-end drop an
  // external implementer would have to reproduce — the filter enforced at the
  // socket, not just in the predicate.
  group('Filter enforcement', () {
    test(
      'a path_prefix subscriber does not receive a non-matching '
      'notify_selection',
      () async {
        final pair = await _connectPair();
        pair.client.send(
          const Subscribe(
            subscriptions: [
              CxpSubscription(
                messageKind: CxpMessageKind.notifySelection,
                pathPrefix: 'top.cpu.',
              ),
            ],
          ),
        );
        await pollUntil(
          () => pair.server
              .debugSubscriptionsOf(_clientIdentity(1).peerId)
              .isNotEmpty,
          reason: 'the filtered subscription must register',
        );

        final received = <CxpClientInbound>[];
        final sub = pair.client.inbound.listen(received.add);

        // Non-matching path — the server MUST drop it.
        pair.server.broadcast(
          const NotifySelection(
            elements: [ElementId(kind: ElementKind.signal, path: 'top.mem.q')],
          ),
        );
        // Matching path — delivered, and it orders the absence check: both
        // broadcasts share the peer's socket in order, so once this frame
        // arrives the earlier one would already have arrived if it had been
        // sent.
        pair.server.broadcast(
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'top.cpu.alu'),
            ],
          ),
        );
        await pollUntil(
          () => received.any(
            (m) =>
                m.message is NotifySelection &&
                (m.message as NotifySelection).elements.first.path ==
                    'top.cpu.alu',
          ),
          reason: 'the prefix-matching selection must be delivered',
        );
        await sub.cancel();

        final paths = received
            .map((m) => m.message)
            .whereType<NotifySelection>()
            .map((s) => s.elements.first.path)
            .toList();
        expect(
          paths,
          ['top.cpu.alu'],
          reason: 'only the prefix-matching selection may reach the subscriber',
        );

        await _tearDownPair(pair.server, pair.client);
      },
    );

    test(
      'an element_kinds subscriber does not receive a selection of another '
      'kind',
      () async {
        final pair = await _connectPair();
        pair.client.send(
          Subscribe(
            subscriptions: [
              CxpSubscription(
                messageKind: CxpMessageKind.notifySelection,
                elementKinds: {ElementKind.signal},
              ),
            ],
          ),
        );
        await pollUntil(
          () => pair.server
              .debugSubscriptionsOf(_clientIdentity(1).peerId)
              .isNotEmpty,
          reason: 'the filtered subscription must register',
        );

        final received = <CxpClientInbound>[];
        final sub = pair.client.inbound.listen(received.add);

        // A scope-only selection carries no signal element — MUST be dropped.
        pair.server.broadcast(
          const NotifySelection(
            elements: [ElementId(kind: ElementKind.scope, path: 'top.mem')],
          ),
        );
        // A signal selection — delivered, and orders the absence check.
        pair.server.broadcast(
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'top.cpu.clk'),
            ],
          ),
        );
        await pollUntil(
          () => received.any(
            (m) =>
                m.message is NotifySelection &&
                (m.message as NotifySelection).elements.first.kind ==
                    ElementKind.signal,
          ),
          reason: 'the signal-kind selection must be delivered',
        );
        await sub.cancel();

        final kinds = received
            .map((m) => m.message)
            .whereType<NotifySelection>()
            .map((s) => s.elements.first.kind)
            .toList();
        expect(
          kinds,
          [ElementKind.signal],
          reason: 'only the signal-kind selection may reach the subscriber',
        );

        await _tearDownPair(pair.server, pair.client);
      },
    );

    // The other half of the rule, and the case the pre-0.5.0 predicate got
    // wrong: §9.1.2 exempts a retraction — a `notify_selection` with an
    // empty `elements` array — from element filtering, so it MUST reach a
    // subscriber that filters by kind *and* path. Without this the narrowed
    // subscriber above could never learn that `top.cpu.alu` had been
    // deselected, and would hold the highlight for as long as both peers
    // run. See CXP §9.1.2.
    test(
      'a retraction reaches an element-filtered subscriber',
      () async {
        final pair = await _connectPair();
        pair.client.send(
          Subscribe(
            subscriptions: [
              CxpSubscription(
                messageKind: CxpMessageKind.notifySelection,
                elementKinds: {ElementKind.signal},
                pathPrefix: 'top.cpu.',
              ),
            ],
          ),
        );
        await pollUntil(
          () => pair.server
              .debugSubscriptionsOf(_clientIdentity(1).peerId)
              .isNotEmpty,
          reason: 'the filtered subscription must register',
        );

        final received = <CxpClientInbound>[];
        final sub = pair.client.inbound.listen(received.add);

        pair.server.broadcast(
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'top.cpu.alu'),
            ],
          ),
        );
        // The user cleared the selection. Matches neither filter and MUST
        // be delivered anyway.
        pair.server.broadcast(const NotifySelection(elements: []));
        await pollUntil(
          () => received
              .map((m) => m.message)
              .whereType<NotifySelection>()
              .any((s) => s.elements.isEmpty),
          reason: 'the retraction must reach the filtered subscriber',
        );
        await sub.cancel();

        expect(
          received
              .map((m) => m.message)
              .whereType<NotifySelection>()
              .map((s) => s.elements.length)
              .toList(),
          [1, 0],
          reason: 'the selection then its retraction, in order',
        );

        await _tearDownPair(pair.server, pair.client);
      },
    );
  });

  group('Server-side dispatch', () {
    test('server publishes inbound messages on its inbound stream', () async {
      final pair = await _connectPair();

      final inboundFuture = pair.server.inbound.first;
      pair.client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.q'),
        ),
      );
      final inbound = await inboundFuture.timeout(const Duration(seconds: 2));
      expect(inbound.message, isA<RequestHighlight>());
      expect(
        (inbound.message as RequestHighlight).element.path,
        'top.q',
      );
      expect(inbound.from.peerId, _clientIdentity(1).peerId);

      await _tearDownPair(pair.server, pair.client);
    });

    test('server replies to unknown kinds with ErrorResponse', () async {
      final pair = await _connectPair();
      final errorFuture = pair.client.inbound.firstWhere(
        (m) => m.message is ErrorResponse,
      );

      // Send a raw envelope with an unknown kind by abusing the wire format.
      // We do this via a custom message kind that decodeCxpMessage rejects.
      pair.client.send(_UnknownKindMessage());
      final inbound = await errorFuture.timeout(const Duration(seconds: 2));
      final err = inbound.message as ErrorResponse;
      expect(err.code, CxpErrorCode.unknownKind);

      await _tearDownPair(pair.server, pair.client);
    });
  });

  group('Targeted send', () {
    test('sendTo delivers to the named peer only', () async {
      final server = LocalCxpServer(selfIdentity: _serverIdentity);
      await server.start();
      final a = LocalCxpClient(selfIdentity: _clientIdentity(10));
      final b = LocalCxpClient(selfIdentity: _clientIdentity(11));
      await a.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );
      await b.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );

      a.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      b.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      await pollUntil(
        () =>
            server
                .debugSubscriptionsOf(_clientIdentity(10).peerId)
                .isNotEmpty &&
            server.debugSubscriptionsOf(_clientIdentity(11).peerId).isNotEmpty,
        reason: 'both subscriptions must register',
      );

      final aFuture = a.inbound.first;
      final bMessages = <CxpClientInbound>[];
      final bSub = b.inbound.listen(bMessages.add);

      final delivered = server.sendTo(
        _clientIdentity(10).peerId,
        const NotifySelection(
          elements: [ElementId(kind: ElementKind.signal, path: 'top.t')],
        ),
      );
      expect(delivered, isTrue);
      // Wait for a's delivery; then bound b's absence check with a
      // directed marker on b's own socket — once the marker arrives,
      // any earlier (mis)delivery to b would already have surfaced.
      await aFuture.timeout(const Duration(seconds: 2));
      server.sendTo(
        _clientIdentity(11).peerId,
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'top.marker'),
        ),
      );
      await pollUntil(
        () => bMessages.any((m) => m.message is RequestHighlight),
        reason: "the marker must arrive on b's socket",
      );
      await bSub.cancel();
      expect(bMessages.where((m) => m.message is NotifySelection), isEmpty);

      await a.dispose();
      await b.dispose();
      await server.stop();
    });

    test('sendTo returns false for an unknown peer', () async {
      final pair = await _connectPair();
      final ok = pair.server.sendTo(
        'no-such-peer',
        const NotifySelection(
          elements: [ElementId(kind: ElementKind.signal, path: 'x')],
        ),
      );
      expect(ok, isFalse);
      await _tearDownPair(pair.server, pair.client);
    });
  });

  group('Clean shutdown', () {
    test('client disconnect removes peer from server', () async {
      final pair = await _connectPair();
      await pollUntil(
        () => pair.server.connectedPeers.length == 1,
        reason: 'the handshake must register the peer',
      );

      final presenceEvents = <PeerPresenceEvent>[];
      final sub = pair.server.presence.listen(presenceEvents.add);

      await pair.client.disconnect();

      await pollUntil(
        () => presenceEvents.any((e) => !e.connected),
        reason: 'expected a disconnect presence event',
      );
      await sub.cancel();
      expect(pair.server.connectedPeers, isEmpty);

      await pair.client.dispose();
      await pair.server.stop();
    });
  });

  group('Stress', () {
    test('100 concurrent client connections complete handshake', () async {
      final server = LocalCxpServer(selfIdentity: _serverIdentity);
      await server.start();

      final clients = <LocalCxpClient>[];
      final futures = <Future<void>>[];
      for (var i = 0; i < 100; i++) {
        final c = LocalCxpClient(selfIdentity: _clientIdentity(1000 + i));
        clients.add(c);
        futures.add(
          c.connect(
            host: '127.0.0.1',
            port: server.boundPort!,
            token: server.authToken,
          ),
        );
      }
      await Future.wait(futures).timeout(const Duration(seconds: 15));

      await pollUntil(
        () => server.connectedPeers.length == 100,
        reason: 'every handshake must register a peer',
      );

      for (final c in clients) {
        await c.dispose();
      }
      await server.stop();
    });
  });
}

/// Stand-in message used by the unknown-kind test. Encodes onto the wire as
/// a kind no decoder recognises.
class _UnknownKindMessage extends CxpMessage {
  @override
  String get kind => 'unknown_future_extension_kind';

  @override
  Map<String, Object?> toJson() => const <String, Object?>{};
}
