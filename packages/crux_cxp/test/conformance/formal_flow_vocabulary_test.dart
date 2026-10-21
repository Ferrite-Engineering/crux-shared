// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:test/test.dart';

import 'poll.dart';

const PeerIdentity _serverIdentity = PeerIdentity(
  peerId: 'netcrux-vocab-server',
  productName: 'netcrux',
  productVersion: '0.0.0-test',
);

const PeerIdentity _clientIdentity = PeerIdentity(
  peerId: 'simcrux-vocab-client',
  productName: 'simcrux',
  productVersion: '0.0.0-test',
);

Future<({LocalCxpServer server, LocalCxpClient client})> _connectPair({
  PeerIdentity client = _clientIdentity,
}) async {
  final server = LocalCxpServer(selfIdentity: _serverIdentity);
  await server.start();
  final c = LocalCxpClient(selfIdentity: client);
  await c.connect(
    host: '127.0.0.1',
    port: server.boundPort!,
    token: server.authToken,
  );
  addTearDown(() async {
    await c.dispose();
    await server.stop();
  });
  return (server: server, client: c);
}

/// The vocabulary of CXP 1.3 Working Draft rev. 9 on a real socket: the
/// `property`, `timing_path` and `cell` element kinds, the
/// `formal.trace_step` binding, the `formal.*` and `crux.mapping` metadata
/// keys, and the identity's `active_document`.
void main() {
  group('rev. 9 element kinds cross the wire intact', () {
    test('a request_highlight for a property keeps its coordinate and '
        'metadata', () async {
      final pair = await _connectPair();
      final inbound = <InboundCxpMessage>[];
      pair.server.inbound.listen(inbound.add);

      final request = RequestHighlight(
        element: const ElementId(
          kind: ElementKind.property,
          path: 'rtl/fifo.sv:45:15',
        ),
        coordinate: CxpStreamCoordinate(
          streamId: CxpStreamCoordinate.formalTraceStepStreamId,
          sequenceIndex: 6,
          attributes: const <String, String>{
            CxpStreamCoordinate.formalVerdictAttribute: 'fail',
            CxpStreamCoordinate.formalDepthConfiguredAttribute: '12',
          },
        ),
        metadata: const <String, Object?>{
          cxpFormalPropertyKindMetadataKey: 'assert',
          cxpFormalPropertyLabelMetadataKey: 'no_overflow',
        },
      );
      pair.client.send(request);

      await pollUntil(
        () => inbound.any((m) => m.message is RequestHighlight),
        reason: 'the request must dispatch',
      );
      final received = inbound
          .map((m) => m.message)
          .whereType<RequestHighlight>()
          .single;
      expect(received, request);
      expect(received.element.kind.known, KnownElementKind.property);
      expect(received.coordinate!.sequenceIndex, 6);
    });

    test('a timing path selection reaches a subscriber that filters on '
        'signal, with its signals in the order sent', () async {
      final pair = await _connectPair();
      pair.client.send(
        Subscribe(
          subscriptions: [
            CxpSubscription(
              messageKind: CxpMessageKind.notifySelection,
              elementKinds: <ElementKind>{ElementKind.signal},
            ),
          ],
        ),
      );
      await pollUntil(
        () =>
            pair.server.debugSubscriptionsOf(_clientIdentity.peerId).isNotEmpty,
        reason: 'the subscription must register before broadcasting',
      );

      const selection = NotifySelection(
        elements: <ElementId>[
          ElementId(kind: ElementKind.timingPath, path: 'run_a/1'),
          ElementId(kind: ElementKind.signal, path: 'top.u_div.cnt_q[3]'),
          ElementId(kind: ElementKind.signal, path: 'top.u_div.cnt_q[23]'),
          ElementId(kind: ElementKind.source, path: 'div.v:21'),
        ],
        metadata: <String, Object?>{cxpMappingMetadataKey: 'register'},
      );
      final received = pair.client.inbound.first;
      pair.server.broadcast(selection);

      final message =
          (await received.timeout(const Duration(seconds: 3))).message
              as NotifySelection;
      expect(message, selection);
      expect(
        message.elements
            .where((e) => e.kind == ElementKind.signal)
            .map((e) => e.path),
        <String>['top.u_div.cnt_q[3]', 'top.u_div.cnt_q[23]'],
        reason:
            'a receiver that ignores timing_path still has the registers '
            '(CXP §12 item 22)',
      );
      expect(message.metadata[cxpMappingMetadataKey], 'register');
    });

    test('a cell reference round-trips as a known kind', () {
      const cell = ElementId(
        kind: ElementKind.cell,
        path: 'top._1234_',
      );
      final back = ElementId.fromJson(cell.toJson());
      expect(back, cell);
      expect(back.kind.known, KnownElementKind.cell);
    });

    test('crux.mapping values are the registered four, strongest first', () {
      expect(cxpMappingMetadataKey, 'crux.mapping');
      expect(cxpMappingValues, <String>[
        'register',
        'statement',
        'span',
        'unmapped',
      ]);
      expect(cxpFormalEqyGoldScopeMetadataKey, 'formal.eqy.gold_scope');
      expect(cxpFormalEqyGateScopeMetadataKey, 'formal.eqy.gate_scope');
    });
  });

  group('active_document', () {
    test('a hello carries only the file name, never the directory', () async {
      final pair = await _connectPair(
        client: const PeerIdentity(
          peerId: 'wavecrux-vocab-doc',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
          activeDocument: '/home/user/secret-project/alu.vcd',
        ),
      );
      await pollUntil(
        () => pair.server.connectedPeers.isNotEmpty,
        reason: 'the handshake must complete',
      );
      final peer = pair.server.connectedPeers.single;
      expect(peer.activeDocument, 'alu.vcd');
    });

    test('a received value is reduced to display text', () {
      final identity = PeerIdentity.fromJson(<String, Object?>{
        'peer_id': 'x',
        'product_name': 'wavecrux',
        'product_version': '1',
        'active_document':
            r'C:\work\a'
            '\u202Eb\u0007c.vcd${'x' * 300}',
      });
      final document = identity.activeDocument!;
      expect(document.startsWith('abc.vcd'), isTrue);
      expect(document.runes.length, kCxpActiveDocumentMaxLength);
      expect(document.contains(r'\'), isFalse);
      expect(document.contains('\u202E'), isFalse);
    });

    test('a value that is not a string, or empty once reduced, is absent', () {
      for (final raw in <Object?>[42, '', '   ', '/', '\u0000\u0001']) {
        final identity = PeerIdentity.fromJson(<String, Object?>{
          'peer_id': 'x',
          'product_name': 'wavecrux',
          'product_version': '1',
          'active_document': raw,
        });
        expect(identity.activeDocument, isNull, reason: '$raw');
        expect(identity.toJson().containsKey('active_document'), isFalse);
      }
    });

    test('the identity of an older peer, with no field, is unchanged', () {
      const json = <String, Object?>{
        'peer_id': 'x',
        'product_name': 'wavecrux',
        'product_version': '1',
        'capabilities': <String>['cxp.accepts:signal'],
      };
      final identity = PeerIdentity.fromJson(json);
      expect(identity.activeDocument, isNull);
      expect(identity.toJson(), json);
    });

    test('the manifest is rewritten at once and discovery reports the '
        'change without a presence event', () async {
      final dir = await Directory.systemTemp.createTemp('crux_cxp_vocab_');
      addTearDown(() => dir.delete(recursive: true));
      final writer = CxpManifestWriter(
        manifestDirectory: dir.path,
        heartbeatInterval: null,
      );
      final discovery = CxpDiscovery(
        manifestDirectory: dir.path,
        scanInterval: const Duration(milliseconds: 50),
        staleThreshold: const Duration(seconds: 30),
      );
      addTearDown(() async {
        await discovery.stop();
        await writer.remove();
      });
      const identity = PeerIdentity(
        peerId: 'wavecrux-vocab-manifest',
        productName: 'wavecrux',
        productVersion: '0.0.0-test',
      );
      await writer.write(identity: identity, host: '127.0.0.1', port: 64600);
      await discovery.start();
      expect(discovery.peers.single.identity.activeDocument, isNull);

      final presence = <CxpDiscoveryEvent>[];
      discovery.events.listen(presence.add);
      final changed = discovery.identityChanges.first;
      await writer.updateIdentity(identity.withActiveDocument('alu.vcd'));

      final manifest = await changed.timeout(const Duration(seconds: 3));
      expect(manifest.identity.activeDocument, 'alu.vcd');
      expect(discovery.peers.single.identity.activeDocument, 'alu.vcd');
      expect(presence, isEmpty, reason: 'the peer neither came nor went');
    });

    test('updateIdentity refuses another peer id and is a no-op before '
        'write', () async {
      final dir = await Directory.systemTemp.createTemp('crux_cxp_vocab_');
      addTearDown(() => dir.delete(recursive: true));
      final writer = CxpManifestWriter(
        manifestDirectory: dir.path,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      const identity = PeerIdentity(
        peerId: 'wavecrux-vocab-a',
        productName: 'wavecrux',
        productVersion: '0.0.0-test',
      );
      await writer.updateIdentity(identity);
      expect(dir.listSync(), isEmpty);
      await writer.write(identity: identity, host: '127.0.0.1', port: 64601);
      await expectLater(
        writer.updateIdentity(
          const PeerIdentity(
            peerId: 'wavecrux-vocab-b',
            productName: 'wavecrux',
            productVersion: '0.0.0-test',
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
