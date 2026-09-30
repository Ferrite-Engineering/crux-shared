// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _localId = PeerIdentity(
  peerId: 'wavecrux-link-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _remoteId = PeerIdentity(
  peerId: 'netcrux-link-2',
  productName: 'netcrux',
  productVersion: '0.0.0',
);

const ElementId _element = ElementId(
  kind: ElementKind.signal,
  path: 'top.cpu.pc',
);

/// Builds an inbound message as the connector would inject it for a frame
/// received from [_remoteId] over an outbound link.
InboundCxpMessage _fromRemote(CxpMessage message, {String id = 'link-in'}) =>
    InboundCxpMessage(
      envelope: CxpEnvelope(
        messageId: id,
        from: _remoteId.peerId,
        kind: message.kind,
        payload: message.toJson(),
      ),
      message: message,
      from: _remoteId,
    );

/// Regression suite for the directed-traffic half of the CXP transport:
/// a message sent to a peer that reached us via *its* outbound connector
/// arrives on that connector's client socket, not on our server's accept
/// loop. Before the link-routing seam existed those frames were emitted
/// on an unlistened broadcast stream and silently discarded while
/// `sendTo` reported success.
void main() {
  group('LocalCxpServer linked-peer routes', () {
    late LocalCxpServer server;

    setUp(() async {
      server = LocalCxpServer(selfIdentity: _localId);
      await server.start();
      addTearDown(server.stop);
    });

    test(
      'injectInbound surfaces on the single inbound dispatch stream',
      () async {
        final received = <InboundCxpMessage>[];
        server.inbound.listen(received.add);

        const message = RequestHighlight(element: _element);
        server.injectInbound(
          InboundCxpMessage(
            envelope: CxpEnvelope(
              messageId: 'link-m-1',
              from: _remoteId.peerId,
              kind: message.kind,
              payload: message.toJson(),
            ),
            message: message,
            from: _remoteId,
          ),
        );

        await pollUntil(
          () => received.length == 1,
          reason: 'injected message must reach the inbound stream',
        );
        expect(received.single.from, _remoteId);
        expect(received.single.message, isA<RequestHighlight>());
      },
    );

    test('sendTo falls back to an attached link route', () {
      final sent = <CxpMessage>[];
      server.attachLinkedPeer(_remoteId, sent.add);

      final delivered = server.sendTo(
        _remoteId.peerId,
        const RequestHighlightAck(inReplyTo: 'link-m-1', honored: true),
      );
      expect(delivered, isTrue);
      expect(sent, hasLength(1));
      expect(sent.single, isA<RequestHighlightAck>());

      server.detachLinkedPeer(_remoteId.peerId);
      final afterDetach = server.sendTo(
        _remoteId.peerId,
        const RequestHighlightAck(inReplyTo: 'link-m-2', honored: true),
      );
      expect(afterDetach, isFalse);
      expect(sent, hasLength(1), reason: 'detached link must not be used');
    });

    test('an inbound connection is preferred over an attached link', () async {
      final client = LocalCxpClient(selfIdentity: _remoteId);
      addTearDown(client.dispose);
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );

      final viaLink = <CxpMessage>[];
      server.attachLinkedPeer(_remoteId, viaLink.add);

      final viaSocket = <CxpClientInbound>[];
      client.inbound.listen(viaSocket.add);

      final delivered = server.sendTo(
        _remoteId.peerId,
        const NotifySelection(elements: [_element]),
      );
      expect(delivered, isTrue);

      await pollUntil(
        () => viaSocket.length == 1,
        reason: 'message must arrive over the inbound socket',
      );
      expect(viaLink, isEmpty);
    });

    test(
      'connectedPeers is the union of inbound and linked, de-duplicated',
      () async {
        server.attachLinkedPeer(_remoteId, (_) {});
        expect(server.connectedPeers, hasLength(1));

        final client = LocalCxpClient(selfIdentity: _remoteId);
        addTearDown(client.dispose);
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: server.authToken,
        );
        await pollUntil(
          () => server.connectedPeers.isNotEmpty,
          reason: 'inbound handshake must complete',
        );
        expect(
          server.connectedPeers,
          hasLength(1),
          reason: 'the same peer via two routes counts once',
        );
        expect(server.connectedPeers.single.peerId, _remoteId.peerId);
      },
    );

    test(
      'presence fires once per reachability transition, not per route',
      () async {
        final events = <PeerPresenceEvent>[];
        server.presence.listen(events.add);

        server.attachLinkedPeer(_remoteId, (_) {});
        await pollUntil(
          () => events.length == 1,
          reason: 'link attach must announce the peer',
        );
        expect(events.single.connected, isTrue);

        final client = LocalCxpClient(selfIdentity: _remoteId);
        addTearDown(client.dispose);
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: server.authToken,
        );
        await pollUntil(
          () => server.connectedPeers.isNotEmpty,
          reason: 'inbound handshake must complete',
        );
        expect(
          events,
          hasLength(1),
          reason: 'a second route to a reachable peer is not a transition',
        );

        server.detachLinkedPeer(_remoteId.peerId);
        expect(
          events,
          hasLength(1),
          reason: 'peer is still reachable over the inbound socket',
        );

        await client.disconnect();
        await pollUntil(
          () => events.length == 2,
          reason: 'losing the last route must announce the disconnect',
        );
        expect(events.last.connected, isFalse);
      },
    );
  });

  group('LocalCxpServer broadcast over connector links', () {
    late LocalCxpServer server;

    setUp(() async {
      server = LocalCxpServer(selfIdentity: _localId);
      await server.start();
      addTearDown(server.stop);
    });

    test(
      'a dialed-only peer receives a matching broadcast after it subscribes',
      () async {
        // Regression: broadcast only ever walked the inbound _peers list, so
        // notify_selection gossip reached a peer only if it had dialed us
        // back. A peer we merely dialed (attached as a linked peer) got
        // nothing. It now receives broadcasts over the link, filtered by the
        // subscription it announced over that link.
        final sent = <CxpMessage>[];
        // Nothing is delivered before the peer expresses interest.
        server
          ..attachLinkedPeer(_remoteId, sent.add)
          ..broadcast(const NotifySelection(elements: [_element]));
        expect(sent, isEmpty, reason: 'no delivery before a subscribe');

        // The peer subscribes over the link; the connector injects the frame.
        server
          ..injectInbound(
            _fromRemote(const Subscribe(subscriptions: cxpSubscribeToAll)),
          )
          ..broadcast(const NotifySelection(elements: [_element]));

        expect(sent, hasLength(1));
        expect(sent.single, isA<NotifySelection>());
      },
    );

    test('a linked peer only receives broadcasts its filter matches', () {
      final sent = <CxpMessage>[];
      server
        ..attachLinkedPeer(_remoteId, sent.add)
        ..injectInbound(
          _fromRemote(
            const Subscribe(
              subscriptions: [
                CxpSubscription(messageKind: CxpMessageKind.notifySelection),
              ],
            ),
          ),
        )
        ..broadcast(const NotifySelection(elements: [_element]))
        ..broadcast(const RequestHighlight(element: _element));

      expect(sent, hasLength(1), reason: 'only the subscribed kind is sent');
      expect(sent.single, isA<NotifySelection>());
    });

    test('an Unsubscribe over the link stops broadcast delivery', () {
      final sent = <CxpMessage>[];
      server
        ..attachLinkedPeer(_remoteId, sent.add)
        ..injectInbound(
          _fromRemote(const Subscribe(subscriptions: cxpSubscribeToAll)),
        )
        ..injectInbound(_fromRemote(const Unsubscribe()))
        ..broadcast(const NotifySelection(elements: [_element]));

      expect(sent, isEmpty);
    });

    test(
      'a Subscribe over a link is consumed, not surfaced on inbound',
      () async {
        final received = <InboundCxpMessage>[];
        // A non-subscribe frame from the same link still surfaces, and its
        // arrival bounds the absence check for the swallowed Subscribe.
        server
          ..inbound.listen(received.add)
          ..attachLinkedPeer(_remoteId, (_) {})
          ..injectInbound(
            _fromRemote(const Subscribe(subscriptions: cxpSubscribeToAll)),
          )
          ..injectInbound(
            _fromRemote(
              const RequestHighlight(element: _element),
              id: 'marker',
            ),
          );
        await pollUntil(
          () => received.any((m) => m.message is RequestHighlight),
          reason: 'a non-subscribe link frame must reach inbound',
        );
        expect(
          received.any((m) => m.message is Subscribe),
          isFalse,
          reason: 'the subscribe was consumed to update link filter state',
        );
      },
    );

    test(
      'broadcast does not double-deliver to a peer reachable both ways',
      () async {
        // Symmetric case: the peer both dialed us (inbound socket) and is an
        // attached link. It must receive the broadcast exactly once — over the
        // inbound socket — never additionally over the link.
        final client = LocalCxpClient(selfIdentity: _remoteId);
        addTearDown(client.dispose);
        await client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: server.authToken,
        );
        client.send(const Subscribe(subscriptions: cxpSubscribeToAll));
        await pollUntil(
          () => server.debugSubscriptionsOf(_remoteId.peerId).isNotEmpty,
          reason: 'the inbound subscription must register',
        );

        final viaLink = <CxpMessage>[];
        server
          ..attachLinkedPeer(_remoteId, viaLink.add)
          ..injectInbound(
            _fromRemote(const Subscribe(subscriptions: cxpSubscribeToAll)),
          );
        final viaSocket = <CxpClientInbound>[];
        client.inbound.listen(viaSocket.add);

        server.broadcast(const NotifySelection(elements: [_element]));

        await pollUntil(
          () => viaSocket.any((m) => m.message is NotifySelection),
          reason: 'the inbound socket delivers the broadcast',
        );
        expect(
          viaLink,
          isEmpty,
          reason:
              'the link must not double-deliver to an inbound-reachable peer',
        );
      },
    );
  });

  group('CxpPeerConnector link routing', () {
    late Directory sharedDir;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('crux_cxp_route_');
    });

    tearDown(() async {
      await sharedDir.delete(recursive: true);
    });

    test(
      'directed round trip with a peer that never dials back: request '
      'arrives via the link, ack returns over the same link',
      () async {
        // Local product: server + discovery + connector routed into the
        // server. Remote peer: server + manifest only — it runs no
        // connector, so the link is the ONLY channel between the two.
        final localServer = LocalCxpServer(selfIdentity: _localId);
        await localServer.start();
        addTearDown(localServer.stop);

        final remoteServer = LocalCxpServer(selfIdentity: _remoteId);
        await remoteServer.start();
        addTearDown(remoteServer.stop);
        final remoteWriter = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
        );
        addTearDown(remoteWriter.remove);
        await remoteWriter.write(
          identity: _remoteId,
          host: '127.0.0.1',
          port: remoteServer.boundPort!,
        );

        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final connector = CxpPeerConnector(
          selfIdentity: _localId,
          discovery: discovery,
          server: localServer,
          retryInterval: const Duration(milliseconds: 100),
        );
        addTearDown(connector.stop);
        await discovery.start();
        connector.start();

        await pollUntil(
          () => remoteServer.connectedPeers.any(
            (p) => p.peerId == _localId.peerId,
          ),
          reason: 'connector must dial the discovered peer',
        );

        final localInbound = <InboundCxpMessage>[];
        localServer.inbound.listen(localInbound.add);
        final remoteInbound = <InboundCxpMessage>[];
        remoteServer.inbound.listen(remoteInbound.add);

        // Remote → local: the frame travels over the socket the
        // connector opened and must surface on the local server's
        // inbound stream.
        final toLocal = remoteServer.sendTo(
          _localId.peerId,
          const RequestHighlight(element: _element),
        );
        expect(toLocal, isTrue);
        await pollUntil(
          () => localInbound.any((m) => m.message is RequestHighlight),
          reason: 'link traffic must reach the local dispatch stream',
        );
        final request = localInbound.firstWhere(
          (m) => m.message is RequestHighlight,
        );
        expect(request.from.peerId, _remoteId.peerId);

        // Local → remote: the local server has no inbound connection
        // from the remote, so the reply must return over the link.
        final toRemote = localServer.sendTo(
          _remoteId.peerId,
          RequestHighlightAck(
            inReplyTo: request.envelope.messageId,
            honored: true,
          ),
        );
        expect(toRemote, isTrue);
        await pollUntil(
          () => remoteInbound.any((m) => m.message is RequestHighlightAck),
          reason: 'the ack must return over the same link',
        );
        final ack =
            remoteInbound
                    .firstWhere((m) => m.message is RequestHighlightAck)
                    .message
                as RequestHighlightAck;
        expect(ack.inReplyTo, request.envelope.messageId);

        // The linked peer is visible on the local reachability surface.
        expect(
          localServer.connectedPeers.any(
            (p) => p.peerId == _remoteId.peerId,
          ),
          isTrue,
        );
      },
    );

    test('manifest removal tears the link route down', () async {
      final localServer = LocalCxpServer(selfIdentity: _localId);
      await localServer.start();
      addTearDown(localServer.stop);

      final remoteServer = LocalCxpServer(selfIdentity: _remoteId);
      await remoteServer.start();
      addTearDown(remoteServer.stop);
      final remoteWriter = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: null,
      );
      await remoteWriter.write(
        identity: _remoteId,
        host: '127.0.0.1',
        port: remoteServer.boundPort!,
      );

      final discovery = CxpDiscovery(
        manifestDirectory: sharedDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
      final connector = CxpPeerConnector(
        selfIdentity: _localId,
        discovery: discovery,
        server: localServer,
        retryInterval: const Duration(milliseconds: 100),
      );
      addTearDown(connector.stop);
      await discovery.start();
      connector.start();

      await pollUntil(
        () =>
            localServer.connectedPeers.any((p) => p.peerId == _remoteId.peerId),
        reason: 'link must attach after the handshake',
      );

      await remoteWriter.remove();
      await pollUntil(
        () => !localServer.connectedPeers.any(
          (p) => p.peerId == _remoteId.peerId,
        ),
        reason: 'losing the manifest must detach the link route',
      );
      expect(
        localServer.sendTo(
          _remoteId.peerId,
          const NotifySelection(elements: [_element]),
        ),
        isFalse,
      );
    });
  });
}
