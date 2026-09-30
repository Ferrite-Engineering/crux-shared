// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _serverId = PeerIdentity(
  peerId: 'wavecrux-rob-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _rawId = PeerIdentity(
  peerId: 'raw-rob-2',
  productName: 'rawpeer',
  productVersion: '0.0.0',
);

const PeerIdentity _fakeId = PeerIdentity(
  peerId: 'fake-rob-3',
  productName: 'fakeserver',
  productVersion: '0.0.0',
);

const ElementId _element = ElementId(
  kind: ElementKind.signal,
  path: 'top.rob.q',
);

/// Fault-path conformance: malformed payloads, handshake rejection and
/// timeout, mid-broadcast disconnects, version negotiation, and the
/// frame-length cap. Every case pins a failure mode that previously
/// either escaped the read loop as an uncaught exception, wedged a
/// connection forever, or was silently ignored.
void main() {
  group('malformed payload of a known kind', () {
    test('server replies malformed_payload and stays connected', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
      );
      await pollUntil(
        () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
        reason: 'handshake must complete',
      );

      // notify_selection with an empty payload fails its fromJson: the
      // `elements` key is absent entirely, which §9.3 requires. (An
      // `elements` key present but *empty* is legal — see the
      // cleared-selection group below.)
      raw.sendEnvelope(
        kind: CxpMessageKind.notifySelection,
        payload: const <String, Object?>{},
        messageId: 'bad-payload-1',
      );
      await pollUntil(
        () => raw.errorPayloads(CxpErrorCode.malformedPayload).isNotEmpty,
        reason: 'undecodable payload must produce malformed_payload',
      );
      final error = raw.errorPayloads(CxpErrorCode.malformedPayload).single;
      expect(error['in_reply_to'], 'bad-payload-1');

      // The connection survives: a valid message still dispatches.
      final inbound = <InboundCxpMessage>[];
      server.inbound.listen(inbound.add);
      raw.sendEnvelope(
        kind: CxpMessageKind.requestHighlight,
        payload: const RequestHighlight(element: _element).toJson(),
      );
      await pollUntil(
        () => inbound.any((m) => m.message is RequestHighlight),
        reason: 'connection must survive a malformed payload',
      );
    });

    test('client replies malformed_payload and stays connected', () async {
      final fake = await _FakeCxpServer.start((fake, socket, envelope) {
        if (envelope['kind'] == CxpMessageKind.hello) {
          fake.writeHelloAck(socket, envelope);
        }
      });
      addTearDown(fake.close);

      final client = LocalCxpClient(selfIdentity: _rawId);
      addTearDown(client.dispose);
      await client.connect(host: '127.0.0.1', port: fake.port);

      fake.writeEnvelope(
        fake.sockets.single,
        kind: CxpMessageKind.notifySelection,
        payload: const <String, Object?>{},
        messageId: 'bad-payload-2',
      );

      await pollUntil(
        () => fake
            .errorPayloads(CxpErrorCode.malformedPayload)
            .any((p) => p['in_reply_to'] == 'bad-payload-2'),
        reason: 'client must report the undecodable payload',
      );
      expect(client.isConnected, isTrue);
    });
  });

  // CXP §9.3: `elements` "MAY be empty to signal cleared selection". The
  // wire form an external implementer will send for "my user deselected
  // everything" is literally `{"elements": []}`, and it MUST NOT be
  // answered malformed_payload. Before 0.4.4 it was — the reference
  // implementation rejected what its own published spec permitted, and a
  // second (TypeScript) implementation inherited the divergence by
  // matching the code instead of the spec.
  group('cleared selection (empty elements)', () {
    test('server accepts an empty elements array and dispatches it', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
      );
      await pollUntil(
        () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
        reason: 'handshake must complete',
      );

      final inbound = <InboundCxpMessage>[];
      server.inbound.listen(inbound.add);

      raw
        ..sendEnvelope(
          kind: CxpMessageKind.notifySelection,
          payload: const <String, Object?>{'elements': <Object?>[]},
          messageId: 'cleared-1',
        )
        // A following well-formed message bounds the absence check: both
        // frames share the socket in order, so once the marker dispatches,
        // an error_response for the cleared selection would already have
        // been written if the server were going to write one.
        ..sendEnvelope(
          kind: CxpMessageKind.requestHighlight,
          payload: const RequestHighlight(element: _element).toJson(),
          messageId: 'marker-1',
        );
      await pollUntil(
        () => inbound.any((m) => m.message is RequestHighlight),
        reason: 'the ordering marker must dispatch',
      );

      expect(
        raw.errorPayloads(CxpErrorCode.malformedPayload),
        isEmpty,
        reason: 'an empty elements array is legal per CXP §9.3',
      );
      final selections = inbound
          .map((m) => m.message)
          .whereType<NotifySelection>()
          .toList();
      expect(selections, hasLength(1));
      expect(selections.single.elements, isEmpty);
      expect(selections.single.referencedElements, isEmpty);
    });

    test(
      'a cleared selection broadcasts to an unfiltered subscriber',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'handshake must complete',
        );
        raw.sendEnvelope(
          kind: CxpMessageKind.subscribe,
          payload: const Subscribe(subscriptions: cxpSubscribeToAll).toJson(),
        );
        await pollUntil(
          () => server.debugSubscriptionsOf(_rawId.peerId).isNotEmpty,
          reason: 'the subscription must register before broadcasting',
        );

        server.broadcast(const NotifySelection(elements: []));
        await pollUntil(
          () => raw.ofKind(CxpMessageKind.notifySelection).isNotEmpty,
          reason: 'the cleared selection must survive the dispatch path',
        );
        final payload =
            (raw.ofKind(CxpMessageKind.notifySelection).single['payload']!
                    as Map)
                .cast<String, Object?>();
        expect(
          payload['elements'],
          isEmpty,
          reason: 'the empty array must survive the encode/decode round trip',
        );
      },
    );
  });

  group('handshake robustness', () {
    test(
      'an ErrorResponse during the handshake fails connect() and leaves '
      'the client reusable',
      () async {
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          fake.writeEnvelope(
            socket,
            kind: CxpMessageKind.errorResponse,
            payload: const ErrorResponse(
              code: CxpErrorCode.unsupportedVersion,
              message: 'rejected',
            ).toJson(),
          );
        });
        addTearDown(fake.close);

        final client = LocalCxpClient(selfIdentity: _rawId);
        addTearDown(client.dispose);
        await expectLater(
          client.connect(host: '127.0.0.1', port: fake.port),
          throwsA(isA<CxpHandshakeException>()),
        );
        expect(client.isConnected, isFalse);

        // The failed handshake must have torn the socket down, so the
        // same client can dial a healthy peer.
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: server.authToken,
        );
        expect(client.isConnected, isTrue);
        expect(client.remotePeer?.peerId, _serverId.peerId);
      },
    );

    test(
      'a peer that accepts but never answers times the handshake out',
      () async {
        final fake = await _FakeCxpServer.start(null);
        addTearDown(fake.close);

        final client = LocalCxpClient(
          selfIdentity: _rawId,
          handshakeTimeout: const Duration(milliseconds: 200),
        );
        addTearDown(client.dispose);
        await expectLater(
          client.connect(host: '127.0.0.1', port: fake.port),
          throwsA(isA<TimeoutException>()),
        );
        expect(client.isConnected, isFalse);

        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: server.authToken,
        );
        expect(client.isConnected, isTrue);
      },
    );

    test(
      'a connector link to a wedging peer keeps retrying and recovers',
      () async {
        final fake = await _FakeCxpServer.start(null);
        final port = fake.port;

        final sharedDir = await Directory.systemTemp.createTemp(
          'crux_cxp_wedge_',
        );
        addTearDown(() => sharedDir.delete(recursive: true));
        final writer = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
        );
        addTearDown(writer.remove);
        await writer.write(
          identity: _fakeId,
          host: '127.0.0.1',
          port: port,
        );

        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final connector = CxpPeerConnector(
          selfIdentity: _rawId,
          discovery: discovery,
          retryInterval: const Duration(milliseconds: 100),
          clientFactory: (self) => LocalCxpClient(
            selfIdentity: self,
            handshakeTimeout: const Duration(milliseconds: 150),
          ),
        );
        addTearDown(connector.stop);
        await discovery.start();
        connector.start();

        // Without the handshake timeout the first dial never completes:
        // the link stays marked connecting and the retry loop skips it
        // forever. Progressing dial attempts prove the link is released.
        await pollUntil(
          () => connector.dialAttempts >= 2,
          reason: 'a wedged handshake must be released for retry',
        );
        expect(connector.connectedPeers, isEmpty);

        // The peer comes up for real on the same port; a later retry
        // must complete the handshake.
        await fake.close();
        final server = LocalCxpServer(selfIdentity: _fakeId, port: port);
        await server.start();
        addTearDown(server.stop);
        await pollUntil(
          () => connector.connectedPeers.any(
            (p) => p.peerId == _fakeId.peerId,
          ),
          reason: 'retry loop must connect once the peer answers',
        );
      },
    );
  });

  // Public-contract conformance: a Hello MUST precede all other traffic.
  // These pin the two ordering failures an external implementer could hit —
  // sending a frame before the handshake, and dropping before it completes.
  group('handshake ordering', () {
    test(
      'traffic before Hello is rejected with handshake_required and the peer '
      'never registers',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        // A request_highlight with no prior Hello.
        raw.sendEnvelope(
          kind: CxpMessageKind.requestHighlight,
          payload: const RequestHighlight(element: _element).toJson(),
          messageId: 'pre-hs-1',
        );
        await pollUntil(
          () => raw.errorPayloads(CxpErrorCode.handshakeRequired).isNotEmpty,
          reason: 'pre-handshake traffic must produce handshake_required',
        );
        expect(
          raw
              .errorPayloads(CxpErrorCode.handshakeRequired)
              .single['in_reply_to'],
          'pre-hs-1',
        );
        expect(
          server.connectedPeers,
          isEmpty,
          reason: 'a peer that never said Hello must not be registered',
        );

        // The rejection does not tear the connection down: a proper Hello on
        // the same socket still completes the handshake.
        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
          messageId: 'hs-2',
        );
        await pollUntil(
          () => server.connectedPeers.any((p) => p.peerId == _rawId.peerId),
          reason: 'a Hello after the rejection must still register the peer',
        );
        expect(raw.closed, isFalse);
      },
    );

    test('a peer that drops before sending Hello never registers', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);

      final presence = <PeerPresenceEvent>[];
      server.presence.listen(presence.add);

      // Connect and drop immediately — the handshake never completes.
      final aborted = await _RawPeer.connect(server.boundPort!);
      await aborted.close();

      // A second peer completes a real handshake; once it registers, an
      // aborted pre-handshake connection would already have surfaced if it
      // were ever going to.
      final good = await _RawPeer.connect(server.boundPort!);
      addTearDown(good.close);
      good.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _fakeId, token: server.authToken).toJson(),
      );
      await pollUntil(
        () => server.connectedPeers.any((p) => p.peerId == _fakeId.peerId),
        reason: 'the well-behaved peer must register',
      );

      expect(
        server.connectedPeers.map((p) => p.peerId).toList(),
        [_fakeId.peerId],
        reason: 'a peer that dropped before Hello must never register',
      );
      expect(
        presence.where((e) => e.connected).map((e) => e.peer.peerId),
        [_fakeId.peerId],
        reason: 'no connect presence event for a pre-handshake drop',
      );
    });

    // The narrow window the two tests above do NOT cover: the peer sends a
    // well-formed Hello and then vanishes before it could ever read the
    // hello_ack. The server has genuinely accepted this peer — unlike the
    // pre-Hello cases — so it may legitimately register and emit a connect
    // event. What it must not do is LEAK that registration: a peer that is
    // gone has to be reaped, or connectedPeers accumulates ghosts that
    // broadcasts then try to write to.
    test(
      'a peer that sends Hello then drops before reading hello_ack is reaped',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);

        final presence = <PeerPresenceEvent>[];
        server.presence.listen(presence.add);

        final ghost = await _RawPeer.connect(server.boundPort!);
        ghost.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
          messageId: 'hs-ghost-1',
        );
        // Drop without ever reading the socket. Whether the server had time to
        // register the peer before the close lands is a race, and the contract
        // holds either way — which is exactly why the assertion below is about
        // the END state, not about whether a connect event fired.
        await ghost.close();

        await pollUntil(
          () => !server.connectedPeers.any((p) => p.peerId == _rawId.peerId),
          reason:
              'a peer that dropped mid-handshake must not remain registered',
        );

        // Every connect for this peer is matched by a disconnect — no ghost
        // left behind in the presence stream either.
        final connects = presence
            .where((e) => e.connected && e.peer.peerId == _rawId.peerId)
            .length;
        final disconnects = presence
            .where((e) => !e.connected && e.peer.peerId == _rawId.peerId)
            .length;
        expect(
          disconnects,
          connects,
          reason:
              'presence must balance: $connects connect(s) but $disconnects '
              'disconnect(s) for a peer that is gone',
        );

        // And the server is still healthy afterwards — the reaped ghost must
        // not have wedged the accept loop for the next peer.
        final good = await _RawPeer.connect(server.boundPort!);
        addTearDown(good.close);
        good.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _fakeId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => server.connectedPeers.any((p) => p.peerId == _fakeId.peerId),
          reason: 'the server must still accept peers after reaping a ghost',
        );
      },
    );
  });

  group('broadcast resilience', () {
    test(
      'a peer failing mid-broadcast is disconnected without corrupting '
      'delivery to the remaining peers',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);

        PeerIdentity id(int n) => PeerIdentity(
          peerId: 'rob-bcast-$n',
          productName: 'rawpeer',
          productVersion: '0.0.0',
        );
        final clients = <LocalCxpClient>[];
        for (var n = 0; n < 3; n++) {
          final client = LocalCxpClient(selfIdentity: id(n));
          addTearDown(client.dispose);
          await client.connect(
            host: '127.0.0.1',
            port: server.boundPort!,
            token: server.authToken,
          );
          client.send(
            const Subscribe(
              subscriptions: [
                CxpSubscription(
                  messageKind: CxpMessageKind.notifySelection,
                ),
              ],
            ),
          );
          clients.add(client);
        }
        await pollUntil(
          () => [
            for (var n = 0; n < 3; n++)
              server.debugSubscriptionsOf(id(n).peerId),
          ].every((subs) => subs.isNotEmpty),
          reason: 'all three subscriptions must register',
        );

        // The first-connected peer fails inside the broadcast loop; its
        // disconnect removes it from the peer list mid-iteration.
        server.debugFailNextSendTo(id(0).peerId);
        final received1 = <CxpClientInbound>[];
        final received2 = <CxpClientInbound>[];
        clients[1].inbound.listen(received1.add);
        clients[2].inbound.listen(received2.add);

        server.broadcast(const NotifySelection(elements: [_element]));

        await pollUntil(
          () =>
              received1.any((m) => m.message is NotifySelection) &&
              received2.any((m) => m.message is NotifySelection),
          reason: 'surviving peers must still receive the broadcast',
        );
        await pollUntil(
          () => !server.connectedPeers.any(
            (p) => p.peerId == id(0).peerId,
          ),
          reason: 'the failed peer must be disconnected',
        );
      },
    );
  });

  group('asynchronous write failure', () {
    test(
      'a peer killed mid-broadcast is disconnected, and its write error '
      'does not escape as an uncaught async error',
      () async {
        // `socket.write` is an IOSink write: it never throws
        // synchronously, so the try/catch that used to wrap it was dead
        // code and a SocketException from a dead peer went to
        // Zone.handleUncaughtError — which fails this test — while the
        // peer lingered in `_peers`. The fix listens on `socket.done`.
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);

        final raw = await _RawPeer.connect(server.boundPort!);
        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'handshake must complete',
        );
        raw.sendEnvelope(
          kind: CxpMessageKind.subscribe,
          payload: const Subscribe(subscriptions: cxpSubscribeToAll).toJson(),
        );
        await pollUntil(
          () => server.debugSubscriptionsOf(_rawId.peerId).isNotEmpty,
          reason: 'subscription must register',
        );

        // Hard-kill the peer, then keep broadcasting at it.
        await raw.close();
        for (var i = 0; i < 40; i++) {
          server.broadcast(const NotifySelection(elements: [_element]));
        }

        await pollUntil(
          () => !server.connectedPeers.any((p) => p.peerId == _rawId.peerId),
          reason: 'a peer whose socket died must be dropped from _peers',
        );
        // The server must still be healthy for everyone else.
        final second = await _RawPeer.connect(server.boundPort!);
        addTearDown(second.close);
        second.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _fakeId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => second.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'the server must keep serving after a peer dies',
        );
      },
    );
  });

  group('outbound backpressure', () {
    test(
      'a peer that stops reading is dropped once its outbound backlog '
      'exceeds maxPendingWriteBytes',
      () async {
        // The inbound direction was always capped (CappedLineSplitter);
        // outbound was not, so a peer that handshakes and then stops
        // draining grew this process's heap without bound. The cap is the
        // outbound mirror of that.
        final server = LocalCxpServer(
          selfIdentity: _serverId,
          maxPendingWriteBytes: 4096,
        );
        await server.start();
        addTearDown(server.stop);

        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);
        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'handshake must complete inside the cap',
        );
        expect(
          server.debugPendingWriteBytesOf(_rawId.peerId),
          lessThan(4096),
          reason: 'one handshake frame must not approach the cap',
        );
        raw.sendEnvelope(
          kind: CxpMessageKind.subscribe,
          payload: const Subscribe(subscriptions: cxpSubscribeToAll).toJson(),
        );
        await pollUntil(
          () => server.debugSubscriptionsOf(_rawId.peerId).isNotEmpty,
          reason: 'subscription must register',
        );

        // One synchronous burst: every frame is queued before any flush
        // can complete, so the backlog is unambiguously over the cap.
        for (var i = 0; i < 200; i++) {
          server.broadcast(const NotifySelection(elements: [_element]));
        }

        await pollUntil(
          () => !server.connectedPeers.any((p) => p.peerId == _rawId.peerId),
          reason: 'an unbounded outbound backlog must drop the peer',
        );
      },
    );
  });

  group('server lifecycle', () {
    test(
      'a failed bind does not leave the server falsely marked running',
      () async {
        // _running was set before the await, so a bind failure left a
        // server that reported success from every later start() while
        // being permanently dead.
        final blocker = await ServerSocket.bind('127.0.0.1', 0);
        final port = blocker.port;

        final server = LocalCxpServer(selfIdentity: _serverId, port: port);
        addTearDown(server.stop);
        await expectLater(
          server.start(),
          throwsA(isA<SocketException>()),
          reason: 'binding an occupied port must surface the failure',
        );
        expect(
          server.boundPort,
          isNull,
          reason: 'a failed bind must not report a bound port',
        );

        // The retry, once the port frees up, must actually work — that is
        // the behavior the early `_running = true` silently destroyed.
        await blocker.close();
        await server.start();
        expect(server.boundPort, isNotNull);

        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);
        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'the retried server must really be serving',
        );
      },
    );

    test('a stop/start cycle still delivers inbound and presence', () async {
      // stop() closed the broadcast controllers permanently, so a user
      // toggling CXP off and on in settings got a server that re-bound and
      // re-accepted but dropped every message on an isClosed guard.
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      await server.stop();
      await server.start();
      addTearDown(server.stop);

      final inbound = <InboundCxpMessage>[];
      final presence = <PeerPresenceEvent>[];
      server.inbound.listen(inbound.add);
      server.presence.listen(presence.add);

      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);
      raw.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
      );
      await pollUntil(
        () =>
            presence.any((e) => e.connected && e.peer.peerId == _rawId.peerId),
        reason: 'presence must fire after a restart',
      );

      raw.sendEnvelope(
        kind: CxpMessageKind.requestHighlight,
        payload: const RequestHighlight(element: _element).toJson(),
      );
      await pollUntil(
        () => inbound.any((m) => m.message is RequestHighlight),
        reason: 'inbound dispatch must survive a restart',
      );

      // injectInbound is the connector's path into the same stream.
      server.injectInbound(
        const InboundCxpMessage(
          envelope: CxpEnvelope(
            messageId: 'restart-1',
            from: 'fake-rob-3',
            kind: CxpMessageKind.notifySelection,
            payload: <String, Object?>{},
          ),
          message: NotifySelection(elements: [_element]),
          from: _fakeId,
        ),
      );
      await pollUntil(
        () => inbound.any((m) => m.message is NotifySelection),
        reason: 'injectInbound must survive a restart',
      );
    });
  });

  group('connect-failure diagnostics', () {
    test(
      'an unreachable peer produces observable dial failures and backs off',
      () async {
        // Connect failures were caught by a bare `on Object` with only a
        // comment: no diagnostic, no backoff, no signal to the product.
        final dead = await ServerSocket.bind('127.0.0.1', 0);
        final deadPort = dead.port;
        await dead.close(); // nothing listens here now

        final sharedDir = await Directory.systemTemp.createTemp(
          'crux_cxp_dial_',
        );
        addTearDown(() => sharedDir.delete(recursive: true));
        final writer = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
        );
        addTearDown(writer.remove);
        await writer.write(
          identity: _fakeId,
          host: '127.0.0.1',
          port: deadPort,
        );

        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final connector = CxpPeerConnector(
          selfIdentity: _rawId,
          discovery: discovery,
          retryInterval: const Duration(milliseconds: 30),
          maxRetryBackoffTicks: 4,
        );
        addTearDown(connector.dispose);

        final failures = <CxpDialFailure>[];
        connector.dialFailures.listen(failures.add);
        await discovery.start();
        connector.start();

        await pollUntil(
          () => failures.length >= 3,
          reason: 'each failed dial must be reported, not swallowed',
        );
        final first = failures.first;
        expect(first.peerId, _fakeId.peerId);
        expect(first.port, deadPort);
        expect(first.error, isNotNull);
        expect(
          connector.lastDialFailures[_fakeId.peerId],
          isNotNull,
          reason: 'the last failure per peer must be queryable',
        );

        // Backoff grows rather than hammering at full rate forever.
        expect(
          failures.map((f) => f.consecutiveFailures).toList(),
          orderedEquals(
            List<int>.generate(failures.length, (i) => i + 1),
          ),
          reason: 'consecutive failures must accumulate',
        );
        expect(
          failures[2].nextRetryAfterTicks,
          greaterThan(failures[0].nextRetryAfterTicks),
          reason: 'the retry interval must back off, not stay flat',
        );
        expect(
          failures.map((f) => f.nextRetryAfterTicks),
          everyElement(lessThanOrEqualTo(4)),
          reason: 'backoff must respect maxRetryBackoffTicks',
        );
      },
    );

    test('a successful handshake clears the recorded failure', () async {
      final sharedDir = await Directory.systemTemp.createTemp(
        'crux_cxp_recover_',
      );
      addTearDown(() => sharedDir.delete(recursive: true));

      final peer = LocalCxpServer(selfIdentity: _fakeId);
      await peer.start();
      addTearDown(peer.stop);
      final port = peer.boundPort!;
      await peer.stop(); // manifest points at a port nobody serves yet

      final writer = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      await writer.write(identity: _fakeId, host: '127.0.0.1', port: port);

      final discovery = CxpDiscovery(
        manifestDirectory: sharedDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
      final connector = CxpPeerConnector(
        selfIdentity: _rawId,
        discovery: discovery,
        retryInterval: const Duration(milliseconds: 30),
        maxRetryBackoffTicks: 1,
      );
      addTearDown(connector.dispose);
      await discovery.start();
      connector.start();

      await pollUntil(
        () => connector.lastDialFailures.containsKey(_fakeId.peerId),
        reason: 'the unreachable peer must be recorded as failing',
      );

      final revived = LocalCxpServer(selfIdentity: _fakeId, port: port);
      await revived.start();
      addTearDown(revived.stop);

      await pollUntil(
        () => connector.connectedPeers.any((p) => p.peerId == _fakeId.peerId),
        reason: 'backoff must still recover once the peer answers',
      );
      expect(
        connector.lastDialFailures,
        isEmpty,
        reason: 'a successful handshake must clear the failure record',
      );
    });
  });

  group('version negotiation', () {
    test(
      'server rejects a major-version mismatch with an error AND closes',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
          cxpVersion: '9.9',
        );
        await pollUntil(
          () => raw.errorPayloads(CxpErrorCode.unsupportedVersion).isNotEmpty,
          reason: 'major mismatch must produce unsupported_version',
        );
        await pollUntil(
          () => raw.closed,
          reason: 'major mismatch must close the connection',
        );
        expect(server.connectedPeers, isEmpty);
      },
    );

    test('server accepts a minor-version difference', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        cxpVersion: '1.9',
      );
      await pollUntil(
        () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
        reason: 'minor difference must complete the handshake',
      );

      final inbound = <InboundCxpMessage>[];
      server.inbound.listen(inbound.add);
      raw.sendEnvelope(
        kind: CxpMessageKind.requestHighlight,
        payload: const RequestHighlight(element: _element).toJson(),
        cxpVersion: '1.9',
      );
      await pollUntil(
        () => inbound.any((m) => m.message is RequestHighlight),
        reason: 'traffic from a 1.x peer must dispatch',
      );
      expect(raw.closed, isFalse);
    });

    test('client fails the handshake on a major-version mismatch', () async {
      final fake = await _FakeCxpServer.start((fake, socket, envelope) {
        if (envelope['kind'] == CxpMessageKind.hello) {
          fake.writeHelloAck(socket, envelope, cxpVersion: '2.0');
        }
      });
      addTearDown(fake.close);

      final client = LocalCxpClient(selfIdentity: _rawId);
      addTearDown(client.dispose);
      await expectLater(
        client.connect(host: '127.0.0.1', port: fake.port),
        throwsA(isA<CxpHandshakeException>()),
      );
      expect(client.isConnected, isFalse);
    });
  });

  // CXP §9.8: a peer MUST NOT send an error_response in reply to an
  // error_response — two peers that did could answer each other forever.
  // CXP §6.1: a receiver MUST answer an unrecognised kind with unknown_kind
  // and keep serving the connection, in whichever role it holds it.
  group('an error is never answered with an error', () {
    Future<_RawPeer> handshaken(LocalCxpServer server) async {
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);
      raw.sendEnvelope(
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
      );
      await pollUntil(
        () => raw.ofKind(CxpMessageKind.helloAck).isNotEmpty,
        reason: 'handshake must complete',
      );
      return raw;
    }

    List<Object?> repliesTo(
      Iterable<Map<String, Object?>> envelopes,
      String id,
    ) => [
      for (final e in envelopes)
        if (e['kind'] == CxpMessageKind.errorResponse &&
            (e['payload']! as Map)['in_reply_to'] == id)
          (e['payload']! as Map)['code'],
    ];

    test('server: an error_response whose payload does not decode', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await handshaken(server);

      raw
        ..sendEnvelope(
          kind: CxpMessageKind.errorResponse,
          payload: const <String, Object?>{},
          messageId: 'bad-error-1',
        )
        // An unknown kind after it is answered, which bounds the silence.
        ..sendEnvelope(
          kind: 'notify_cursor',
          payload: const <String, Object?>{},
          messageId: 'unknown-1',
        );
      await pollUntil(
        () => repliesTo(raw.envelopes, 'unknown-1').isNotEmpty,
        reason: 'the unknown kind is answered',
      );
      expect(repliesTo(raw.envelopes, 'bad-error-1'), isEmpty);
      expect(raw.closed, isFalse);
    });

    test(
      'server: an error_response that arrives before the handshake',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        raw
          ..sendEnvelope(
            kind: CxpMessageKind.errorResponse,
            payload: const ErrorResponse(
              code: CxpErrorCode.internalError,
              message: 'early',
            ).toJson(),
            messageId: 'early-error-1',
          )
          ..sendEnvelope(
            kind: CxpMessageKind.requestHighlight,
            payload: const RequestHighlight(element: _element).toJson(),
            messageId: 'early-request-1',
          );
        await pollUntil(
          () => repliesTo(raw.envelopes, 'early-request-1').isNotEmpty,
          reason: 'a request before the handshake is answered',
        );
        expect(repliesTo(raw.envelopes, 'early-request-1'), [
          CxpErrorCode.handshakeRequired,
        ]);
        expect(repliesTo(raw.envelopes, 'early-error-1'), isEmpty);
      },
    );

    test(
      'server: an error_response of another major version closes the '
      'connection without an answer',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await handshaken(server);

        raw.sendEnvelope(
          kind: CxpMessageKind.errorResponse,
          payload: const ErrorResponse(
            code: CxpErrorCode.internalError,
            message: 'from the future',
          ).toJson(),
          messageId: 'v9-error-1',
          cxpVersion: '9.0',
        );
        await pollUntil(() => raw.closed, reason: 'a major mismatch closes');
        expect(raw.ofKind(CxpMessageKind.errorResponse), isEmpty);
      },
    );

    test(
      'server: a product reply that answers an error_response with one is '
      'not sent, on either route',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final inbound = <InboundCxpMessage>[];
        server.inbound.listen(inbound.add);
        final raw = await handshaken(server);

        raw.sendEnvelope(
          kind: CxpMessageKind.errorResponse,
          payload: const ErrorResponse(
            code: CxpErrorCode.unsupported,
            message: 'not here',
            inReplyTo: 'whatever',
          ).toJson(),
          messageId: 'peer-error-1',
        );
        await pollUntil(
          () => inbound.any((m) => m.message is ErrorResponse),
          reason: 'the error is dispatched to the product',
        );
        // A product that answers everything it does not handle — one did.
        server
          ..sendTo(
            _rawId.peerId,
            const ErrorResponse(
              code: CxpErrorCode.unsupported,
              message: 'answering an error',
              inReplyTo: 'peer-error-1',
            ),
          )
          ..sendTo(
            _rawId.peerId,
            const ErrorResponse(
              code: CxpErrorCode.unsupported,
              message: 'answering a request',
              inReplyTo: 'peer-request-1',
            ),
          );
        await pollUntil(
          () => repliesTo(raw.envelopes, 'peer-request-1').isNotEmpty,
          reason: 'an error answering a request is sent',
        );
        expect(repliesTo(raw.envelopes, 'peer-error-1'), isEmpty);

        // The same over a connector link.
        const linked = PeerIdentity(
          peerId: 'linked-rob-4',
          productName: 'linked',
          productVersion: '0.0.0',
        );
        final overLink = <CxpMessage>[];
        server
          ..attachLinkedPeer(linked, overLink.add)
          ..injectInbound(
            InboundCxpMessage(
              envelope: CxpEnvelope(
                messageId: 'link-error-1',
                from: linked.peerId,
                kind: CxpMessageKind.errorResponse,
                payload: const <String, Object?>{},
              ),
              message: const ErrorResponse(code: 'x', message: 'y'),
              from: linked,
            ),
          )
          ..sendTo(
            linked.peerId,
            const ErrorResponse(
              code: CxpErrorCode.unsupported,
              message: 'answering an error',
              inReplyTo: 'link-error-1',
            ),
          );
        expect(overLink, isEmpty);
      },
    );

    test(
      'client: an error_response whose payload does not decode, after the '
      'handshake',
      () async {
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          if (envelope['kind'] == CxpMessageKind.hello) {
            fake.writeHelloAck(socket, envelope);
          }
        });
        addTearDown(fake.close);
        final client = LocalCxpClient(selfIdentity: _rawId);
        addTearDown(client.dispose);
        await client.connect(host: '127.0.0.1', port: fake.port);

        fake
          ..writeEnvelope(
            fake.sockets.single,
            kind: CxpMessageKind.errorResponse,
            payload: const <String, Object?>{},
            messageId: 'bad-error-2',
          )
          ..writeEnvelope(
            fake.sockets.single,
            kind: 'notify_cursor',
            payload: const <String, Object?>{},
            messageId: 'unknown-2',
          );
        await pollUntil(
          () => repliesTo(fake.receivedEnvelopes, 'unknown-2').isNotEmpty,
          reason: 'the unknown kind is answered',
        );
        expect(repliesTo(fake.receivedEnvelopes, 'bad-error-2'), isEmpty);
        expect(client.isConnected, isTrue);
      },
    );

    test(
      'client: an undecodable error_response in place of hello_ack fails '
      'the handshake at once, unanswered',
      () async {
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          if (envelope['kind'] == CxpMessageKind.hello) {
            fake.writeEnvelope(
              socket,
              kind: CxpMessageKind.errorResponse,
              payload: const <String, Object?>{'code': 'unauthorized'},
              messageId: 'bad-refusal-1',
            );
          }
        });
        addTearDown(fake.close);
        final client = LocalCxpClient(
          selfIdentity: _rawId,
          handshakeTimeout: const Duration(seconds: 30),
        );
        addTearDown(client.dispose);
        final stopwatch = Stopwatch()..start();
        await expectLater(
          client.connect(host: '127.0.0.1', port: fake.port),
          throwsA(
            isA<CxpHandshakeException>().having(
              (e) => e.code,
              'code',
              CxpErrorCode.unauthorized,
            ),
          ),
        );
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
        expect(repliesTo(fake.receivedEnvelopes, 'bad-refusal-1'), isEmpty);
      },
    );
  });

  group('an unknown kind is always answered', () {
    test(
      'client: answers unknown_kind and keeps the connection (§6.1)',
      () async {
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          if (envelope['kind'] == CxpMessageKind.hello) {
            fake.writeHelloAck(socket, envelope);
          }
        });
        addTearDown(fake.close);
        final client = LocalCxpClient(selfIdentity: _rawId);
        addTearDown(client.dispose);
        final inbound = <CxpClientInbound>[];
        client.inbound.listen(inbound.add);
        await client.connect(host: '127.0.0.1', port: fake.port);

        fake
          ..writeEnvelope(
            fake.sockets.single,
            kind: 'notify_cursor',
            payload: const <String, Object?>{'t': 1},
            messageId: 'unknown-3',
          )
          ..writeEnvelope(
            fake.sockets.single,
            kind: CxpMessageKind.requestHighlight,
            payload: const RequestHighlight(element: _element).toJson(),
            messageId: 'known-3',
          );
        await pollUntil(
          () => inbound.any((m) => m.message is RequestHighlight),
          reason: 'the connection survives an unknown kind',
        );
        await pollUntil(
          () => fake
              .errorPayloads(CxpErrorCode.unknownKind)
              .any((p) => p['in_reply_to'] == 'unknown-3'),
          reason: 'the unknown kind is answered unknown_kind',
        );
        expect(client.isConnected, isTrue);
        expect(inbound.map((m) => m.envelope.kind), [
          CxpMessageKind.requestHighlight,
        ]);
      },
    );
  });

  group('frame-length cap', () {
    test(
      'server drops a connection streaming an unterminated over-long line '
      'and keeps serving others',
      () async {
        final server = LocalCxpServer(
          selfIdentity: _serverId,
          maxLineLength: 1024,
        );
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        raw.socket.write('x' * 5000);
        await pollUntil(
          () => raw.closed,
          reason: 'an unbounded line must not buffer forever',
        );

        final second = await _RawPeer.connect(server.boundPort!);
        addTearDown(second.close);
        second.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => second.ofKind(CxpMessageKind.helloAck).isNotEmpty,
          reason: 'the server must keep serving new connections',
        );
      },
    );

    test('server drops a connection sending an over-long frame', () async {
      final server = LocalCxpServer(
        selfIdentity: _serverId,
        maxLineLength: 1024,
      );
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.socket.write('${'y' * 5000}\n');
      await pollUntil(
        () => raw.closed,
        reason: 'an over-long terminated frame must drop the connection',
      );
    });

    test('client drops a connection sending an over-long frame', () async {
      final fake = await _FakeCxpServer.start((fake, socket, envelope) {
        if (envelope['kind'] == CxpMessageKind.hello) {
          fake.writeHelloAck(socket, envelope);
        }
      });
      addTearDown(fake.close);

      final client = LocalCxpClient(
        selfIdentity: _rawId,
        maxLineLength: 512,
      );
      addTearDown(client.dispose);
      await client.connect(host: '127.0.0.1', port: fake.port);
      expect(client.isConnected, isTrue);

      fake.sockets.single.write('${'z' * 2000}\n');
      await pollUntil(
        () => !client.isConnected,
        reason: 'an over-long frame must drop the client connection',
      );
    });
  });

  // Every product listens on a fixed default port (54322–54325), and a web
  // page can `fetch()` a loopback port with a `text/plain` POST that needs no
  // preflight. The HTTP request line and headers arrive as frames the
  // decoder rejects; the body is whatever the page chose. A server that
  // answered each bad frame and read on would dispatch the body — blind,
  // from any site the user had open. An HTTP request cannot start with a
  // JSON object, so the first unparseable frame must end the connection.
  group('unparseable frames close the connection', () {
    /// A browser POST whose body is a complete, well-formed CXP session:
    /// a Hello followed by a request the product would act on.
    String browserPost(LocalCxpServer server) {
      final port = server.boundPort!;
      // The body carries the server's real token: the property under test
      // is that the request line closes the socket before the body is
      // read, and it must hold even for a body that would otherwise pass
      // the handshake.
      final hello = CxpEnvelope(
        messageId: 'b-1',
        from: _rawId.peerId,
        kind: CxpMessageKind.hello,
        payload: Hello(identity: _rawId, token: server.authToken).toJson(),
      );
      const open = RequestOpenSource(filePath: '/etc/passwd', line: 1);
      final request = CxpEnvelope(
        messageId: 'b-2',
        from: _rawId.peerId,
        kind: CxpMessageKind.requestOpenSource,
        payload: open.toJson(),
      );
      final body = '${hello.encodeLine()}${request.encodeLine()}';
      return 'POST / HTTP/1.1\r\n'
          'Host: 127.0.0.1:$port\r\n'
          'Content-Type: text/plain;charset=UTF-8\r\n'
          'Origin: https://attacker.example\r\n'
          'Content-Length: ${utf8.encode(body).length}\r\n'
          '\r\n'
          '$body';
    }

    test(
      'a browser POST to the port is dropped at its request line and its '
      'body is never dispatched',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final inbound = <InboundCxpMessage>[];
        server.inbound.listen(inbound.add);
        final presence = <PeerPresenceEvent>[];
        server.presence.listen(presence.add);

        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);
        raw.socket.write(browserPost(server));

        await pollUntil(
          () => raw.closed,
          reason: 'the request line is not an envelope; the socket must close',
        );
        expect(
          raw.errorPayloads(CxpErrorCode.malformedEnvelope),
          isNotEmpty,
          reason: 'the rejection is answered before the close',
        );
        // A well-behaved peer registering afterwards bounds the negative
        // assertions: the body's Hello and request shared the socket in
        // order with the request line, so if either had been dispatched it
        // would have happened before this peer's handshake completed.
        final good = await _RawPeer.connect(server.boundPort!);
        addTearDown(good.close);
        good.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _fakeId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => server.connectedPeers.any((p) => p.peerId == _fakeId.peerId),
          reason: 'the server must keep serving after dropping the browser',
        );
        expect(
          inbound,
          isEmpty,
          reason:
              'the request_open_source in the POST body must never reach '
              'the product handler',
        );
        expect(
          presence.map((e) => e.peer.peerId),
          [_fakeId.peerId],
          reason: 'the Hello in the POST body must never register a peer',
        );
      },
    );

    test('a frame that is not JSON closes the connection', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.socket.write('GET / HTTP/1.1\r\n');
      await pollUntil(() => raw.closed, reason: 'non-JSON must close');
      expect(raw.errorPayloads(CxpErrorCode.malformedEnvelope), hasLength(1));
    });

    test('a JSON frame that is not an object closes the connection', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final raw = await _RawPeer.connect(server.boundPort!);
      addTearDown(raw.close);

      raw.socket.write('[1, 2, 3]\n');
      await pollUntil(() => raw.closed, reason: 'a JSON array must close');
      expect(raw.errorPayloads(CxpErrorCode.malformedEnvelope), hasLength(1));
    });

    test(
      'a JSON object missing a required envelope field closes the connection',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        // A well-formed object that is not an envelope: no cxp_version,
        // message_id or from. §5 requires malformed_envelope; the close is
        // this implementation's containment on top of it.
        raw.socket.write('{"kind": "hello", "payload": {}}\n');
        await pollUntil(() => raw.closed, reason: 'a non-envelope must close');
        expect(
          raw.errorPayloads(CxpErrorCode.malformedEnvelope),
          hasLength(1),
        );
      },
    );

    test(
      'an established peer that sends garbage is dropped, and the drop is '
      'reported as a disconnect',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final presence = <PeerPresenceEvent>[];
        server.presence.listen(presence.add);
        final raw = await _RawPeer.connect(server.boundPort!);
        addTearDown(raw.close);

        raw.sendEnvelope(
          kind: CxpMessageKind.hello,
          payload: Hello(identity: _rawId, token: server.authToken).toJson(),
        );
        await pollUntil(
          () => server.connectedPeers.any((p) => p.peerId == _rawId.peerId),
          reason: 'handshake must complete',
        );
        raw.socket.write('not an envelope\n');
        await pollUntil(() => raw.closed, reason: 'garbage must close');
        await pollUntil(
          () => presence.any((e) => !e.connected),
          reason: 'the drop must surface as a disconnect presence event',
        );
        expect(server.connectedPeers, isEmpty);
      },
    );

    test(
      'the client drops a peer that answers with something other than '
      'envelopes',
      () async {
        // A dialled port that turns out to speak HTTP (a squatter, a
        // misconfigured tool) must not stay attached as a link.
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          if (envelope['kind'] == CxpMessageKind.hello) {
            fake.writeHelloAck(socket, envelope);
          }
        });
        addTearDown(fake.close);
        final client = LocalCxpClient(selfIdentity: _rawId);
        addTearDown(client.dispose);
        final events = <CxpConnectionEvent>[];
        client.events.listen(events.add);
        await client.connect(host: '127.0.0.1', port: fake.port);
        expect(client.isConnected, isTrue);

        fake.sockets.single.write('HTTP/1.1 200 OK\r\n');
        await pollUntil(
          () => !client.isConnected,
          reason: 'a non-envelope frame must drop the client connection',
        );
        expect(
          events.last.error,
          isA<FormatException>(),
          reason: 'the disconnect must say why',
        );
      },
    );

    test(
      'a client that has not finished the handshake fails it on garbage',
      () async {
        final fake = await _FakeCxpServer.start((fake, socket, envelope) {
          socket.write('HTTP/1.1 400 Bad Request\r\n');
        });
        addTearDown(fake.close);
        final client = LocalCxpClient(selfIdentity: _rawId);
        addTearDown(client.dispose);
        await expectLater(
          client.connect(host: '127.0.0.1', port: fake.port),
          throwsA(isA<FormatException>()),
        );
        expect(client.isConnected, isFalse);
      },
    );
  });
}

/// Raw TCP peer speaking newline-JSON directly, for driving the server
/// with frames a well-behaved [LocalCxpClient] cannot produce.
class _RawPeer {
  _RawPeer._(this.socket) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isEmpty) return;
            envelopes.add((jsonDecode(line) as Map).cast<String, Object?>());
          },
          onError: (Object _) => closed = true,
          onDone: () => closed = true,
          cancelOnError: false,
        );
  }

  static Future<_RawPeer> connect(int port) async =>
      _RawPeer._(await Socket.connect('127.0.0.1', port));

  final Socket socket;
  final List<Map<String, Object?>> envelopes = <Map<String, Object?>>[];
  bool closed = false;

  void sendEnvelope({
    required String kind,
    required Map<String, Object?> payload,
    String messageId = 'raw-m-1',
    String cxpVersion = cxpProtocolVersion,
  }) {
    socket.write(
      CxpEnvelope(
        messageId: messageId,
        from: _rawId.peerId,
        kind: kind,
        payload: payload,
        cxpVersion: cxpVersion,
      ).encodeLine(),
    );
  }

  Iterable<Map<String, Object?>> ofKind(String kind) =>
      envelopes.where((e) => e['kind'] == kind);

  List<Map<String, Object?>> errorPayloads(String code) => [
    for (final envelope in ofKind(CxpMessageKind.errorResponse))
      if ((envelope['payload']! as Map).cast<String, Object?>()['code'] == code)
        (envelope['payload']! as Map).cast<String, Object?>(),
  ];

  Future<void> close() async {
    socket.destroy();
  }
}

/// Scripted TCP acceptor standing in for a remote CXP server, for
/// driving the client with handshake behaviors a well-behaved
/// [LocalCxpServer] cannot produce (rejection, silence, bad versions).
class _FakeCxpServer {
  _FakeCxpServer._(this._server, this._onEnvelope) {
    _server.listen((socket) {
      sockets.add(socket);
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) return;
              final envelope = (jsonDecode(line) as Map)
                  .cast<String, Object?>();
              receivedEnvelopes.add(envelope);
              _onEnvelope?.call(this, socket, envelope);
            },
            onError: (Object _) {},
            onDone: () {},
            cancelOnError: false,
          );
    });
  }

  static Future<_FakeCxpServer> start(
    void Function(
      _FakeCxpServer fake,
      Socket socket,
      Map<String, Object?> envelope,
    )?
    onEnvelope,
  ) async => _FakeCxpServer._(
    await ServerSocket.bind('127.0.0.1', 0),
    onEnvelope,
  );

  final ServerSocket _server;
  final void Function(_FakeCxpServer, Socket, Map<String, Object?>)?
  _onEnvelope;
  final List<Socket> sockets = <Socket>[];
  final List<Map<String, Object?>> receivedEnvelopes = <Map<String, Object?>>[];

  int get port => _server.port;

  void writeEnvelope(
    Socket socket, {
    required String kind,
    required Map<String, Object?> payload,
    String messageId = 'fake-m-1',
    String cxpVersion = cxpProtocolVersion,
  }) {
    socket.write(
      CxpEnvelope(
        messageId: messageId,
        from: _fakeId.peerId,
        kind: kind,
        payload: payload,
        cxpVersion: cxpVersion,
      ).encodeLine(),
    );
  }

  void writeHelloAck(
    Socket socket,
    Map<String, Object?> helloEnvelope, {
    String cxpVersion = cxpProtocolVersion,
  }) {
    writeEnvelope(
      socket,
      kind: CxpMessageKind.helloAck,
      payload: HelloAck(
        identity: _fakeId,
        inReplyTo: helloEnvelope['message_id']! as String,
      ).toJson(),
      cxpVersion: cxpVersion,
    );
  }

  List<Map<String, Object?>> errorPayloads(String code) => [
    for (final envelope in receivedEnvelopes)
      if (envelope['kind'] == CxpMessageKind.errorResponse &&
          (envelope['payload']! as Map).cast<String, Object?>()['code'] == code)
        (envelope['payload']! as Map).cast<String, Object?>(),
  ];

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}
