// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _localId = PeerIdentity(
  peerId: 'wavecrux-sub-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _remoteId = PeerIdentity(
  peerId: 'simcrux-sub-2',
  productName: 'simcrux',
  productVersion: '0.0.0',
);

const ElementId _element = ElementId(
  kind: ElementKind.signal,
  path: 'top.dut.clk',
);

/// Regression suite for the broadcast half of the CXP transport:
/// `LocalCxpServer.broadcast` delivers only to peers with a registered
/// Subscribe filter, and no product ever sent one — `notify_selection`
/// gossip was dead between real products. The connector now subscribes
/// automatically after every link handshake.
void main() {
  group('CxpPeerConnector auto-subscribe', () {
    late Directory sharedDir;
    late LocalCxpServer localServer;
    late LocalCxpServer remoteServer;
    late CxpDiscovery discovery;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('crux_cxp_sub_');
      localServer = LocalCxpServer(selfIdentity: _localId);
      await localServer.start();
      addTearDown(localServer.stop);
      remoteServer = LocalCxpServer(selfIdentity: _remoteId);
      await remoteServer.start();
      addTearDown(remoteServer.stop);
      final writer = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      await writer.write(
        identity: _remoteId,
        host: '127.0.0.1',
        port: remoteServer.boundPort!,
      );
      discovery = CxpDiscovery(
        manifestDirectory: sharedDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
    });

    tearDown(() async {
      await sharedDir.delete(recursive: true);
    });

    CxpPeerConnector startConnector({
      List<CxpSubscription>? subscriptions,
    }) {
      final connector = CxpPeerConnector(
        selfIdentity: _localId,
        discovery: discovery,
        server: localServer,
        subscriptions: subscriptions,
        retryInterval: const Duration(milliseconds: 100),
      );
      addTearDown(connector.stop);
      connector.start();
      return connector;
    }

    test('the link announces the subscribe-to-all default after the '
        'handshake', () async {
      await discovery.start();
      startConnector();

      await pollUntil(
        () => remoteServer.debugSubscriptionsOf(_localId.peerId).isNotEmpty,
        reason: 'the remote server must register the auto-subscription',
      );
      expect(
        remoteServer.debugSubscriptionsOf(_localId.peerId),
        cxpSubscribeToAll,
      );
    });

    test('notify_selection gossip reaches the linked product', () async {
      await discovery.start();
      startConnector();

      await pollUntil(
        () => remoteServer.debugSubscriptionsOf(_localId.peerId).isNotEmpty,
        reason: 'the auto-subscription must be registered first',
      );

      final received = <InboundCxpMessage>[];
      localServer.inbound.listen(received.add);
      remoteServer.broadcast(const NotifySelection(elements: [_element]));

      await pollUntil(
        () => received.any((m) => m.message is NotifySelection),
        reason: 'broadcast gossip must reach the linked peer',
      );
      expect(
        received.firstWhere((m) => m.message is NotifySelection).from.peerId,
        _remoteId.peerId,
      );
    });

    test('a custom initial subscription set replaces the default', () async {
      await discovery.start();
      const custom = <CxpSubscription>[
        CxpSubscription(messageKind: CxpMessageKind.notifySelection),
      ];
      startConnector(subscriptions: custom);

      await pollUntil(
        () => remoteServer.debugSubscriptionsOf(_localId.peerId).isNotEmpty,
        reason: 'the custom subscription must be registered',
      );
      expect(
        remoteServer.debugSubscriptionsOf(_localId.peerId),
        custom,
      );
    });

    test('updateSubscriptions re-announces on live links and narrows '
        'delivery', () async {
      await discovery.start();
      final connector = startConnector();

      await pollUntil(
        () => remoteServer.debugSubscriptionsOf(_localId.peerId).isNotEmpty,
        reason: 'the auto-subscription must be registered first',
      );

      connector.updateSubscriptions(const <CxpSubscription>[]);
      await pollUntil(
        () => remoteServer.debugSubscriptionsOf(_localId.peerId).isEmpty,
        reason: 'the narrowed (empty) set must replace the default',
      );

      final received = <InboundCxpMessage>[];
      localServer.inbound.listen(received.add);
      remoteServer.broadcast(const NotifySelection(elements: [_element]));

      // A directed marker bounds the absence check: sendTo bypasses
      // subscriptions and shares the broadcast's socket, so once the
      // marker arrives, the earlier broadcast would already have been
      // delivered if it had been sent.
      const marker = RequestHighlight(element: _element);
      expect(remoteServer.sendTo(_localId.peerId, marker), isTrue);
      await pollUntil(
        () => received.any((m) => m.message is RequestHighlight),
        reason: 'the directed marker must arrive',
      );
      expect(
        received.where((m) => m.message is NotifySelection),
        isEmpty,
        reason: 'gossip must not be delivered after narrowing to nothing',
      );
    });
  });
}
