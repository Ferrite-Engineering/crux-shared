// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp/src/cxp_host_stub.dart' as web_host;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

/// Regression suite for a cross-discovery defect: two running Crux products
/// on the same machine never saw each other as CXP peers. Three
/// each-sufficient root causes, each pinned here:
///
/// 1. **Per-app manifest dirs** — every product resolved its manifest
///    directory under its own (bundle-id-scoped) application-support
///    container, so no product ever scanned another's manifests.
///    [sharedCxpManifestDirectory] is the bundle-independent replacement.
/// 2. **No dialer** — discovery surfaced manifests but nothing opened a
///    socket, so `LocalCxpServer.connectedPeers` (which cross-probe UIs
///    gate on) stayed empty forever. [CxpPeerConnector] dials every
///    discovered peer.
/// 3. **No heartbeat** — manifests were written once and stale-pruned by
///    peers after `staleThreshold` (5 min in production), so even a
///    shared directory degraded to "no peers" minutes after launch.
///    [CxpManifestWriter] now refreshes `started_at` periodically.
void main() {
  group('sharedCxpManifestDirectory', () {
    test('macOS resolves under ~/Library/Application Support', () {
      final dir = sharedCxpManifestDirectory(
        environment: {'HOME': '/Users/alice'},
        operatingSystem: 'macos',
      );
      expect(
        dir,
        '/Users/alice/Library/Application Support/crux/cxp/peers',
      );
    });

    test('linux honors XDG_DATA_HOME', () {
      final dir = sharedCxpManifestDirectory(
        environment: {'HOME': '/home/alice', 'XDG_DATA_HOME': '/data/xdg'},
        operatingSystem: 'linux',
      );
      expect(dir, '/data/xdg/crux/cxp/peers');
    });

    test('linux falls back to ~/.local/share without XDG_DATA_HOME', () {
      final dir = sharedCxpManifestDirectory(
        environment: {'HOME': '/home/alice'},
        operatingSystem: 'linux',
      );
      expect(dir, '/home/alice/.local/share/crux/cxp/peers');
    });

    test('windows resolves under APPDATA', () {
      final dir = sharedCxpManifestDirectory(
        environment: {'APPDATA': r'C:\Users\alice\AppData\Roaming'},
        operatingSystem: 'windows',
      );
      // path.join with a Windows-style base on any host: the suffix is
      // joined with the host separator, so just assert the components.
      expect(dir, contains(r'C:\Users\alice\AppData\Roaming'));
      expect(dir, contains('crux'));
      expect(dir, contains('cxp'));
      expect(dir, endsWith('peers'));
    });

    test('is bundle-independent: two products resolve the SAME directory', () {
      // The defect: getApplicationSupportDirectory() gave each product a
      // different container. The shared resolver depends only on the user
      // environment, so any two products on one machine agree.
      final env = {'HOME': '/Users/bob'};
      final a = sharedCxpManifestDirectory(
        environment: env,
        operatingSystem: 'macos',
      );
      final b = sharedCxpManifestDirectory(
        environment: env,
        operatingSystem: 'macos',
      );
      expect(a, b);
    });

    test('throws StateError when the home variable is missing', () {
      expect(
        () => sharedCxpManifestDirectory(
          environment: const {},
          operatingSystem: 'macos',
        ),
        throwsStateError,
      );
    });

    test('the host a browser gets has nothing to resolve from', () {
      // The conditional export picks this stub wherever `dart:io` is missing,
      // and the resolver turns its nulls into the StateError above.
      // `test/web/cxp_manifest_directory_web_test.dart` runs that path in
      // Chrome; this pins the stub's own answers on the VM, where it is
      // otherwise never loaded.
      expect(web_host.cxpHostEnvironment(), isNull);
      expect(web_host.cxpHostOperatingSystem(), isNull);
    });
  });

  group('CxpManifestWriter heartbeat', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crux_cxp_hb_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'refreshes started_at so a live peer survives past staleThreshold',
      () async {
        const staleThreshold = Duration(milliseconds: 200);
        final writer = CxpManifestWriter(
          manifestDirectory: tempDir.path,
          heartbeatInterval: const Duration(milliseconds: 50),
        );
        addTearDown(writer.remove);
        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          scanInterval: const Duration(milliseconds: 50),
          // Far shorter than the observed window: without the heartbeat
          // the manifest is pruned (and deleted) after ~200ms.
          staleThreshold: staleThreshold,
        );
        addTearDown(discovery.stop);

        await writer.write(
          // Real live pid so pid-liveness pruning treats this as an
          // alive peer; TTL still governs the no-heartbeat pruning under test.
          identity: PeerIdentity(
            peerId: 'wavecrux-$pid-1',
            productName: 'wavecrux',
            productVersion: '0.0.0',
          ),
          host: '127.0.0.1',
          port: 64510,
        );
        await discovery.start();
        expect(discovery.peers, hasLength(1));
        final removals = <CxpDiscoveryEvent>[];
        discovery.events.listen((event) {
          if (!event.added) removals.add(event);
        });

        // Observe the manifest's own started_at until wall time has
        // advanced several stale-thresholds past the initial write —
        // the refreshes are the clock, so no fixed sleep is needed.
        final manifestFile = File(
          p.join(tempDir.path, 'wavecrux-$pid-1.json'),
        );
        DateTime startedAt() => DateTime.fromMillisecondsSinceEpoch(
          (jsonDecode(manifestFile.readAsStringSync())
                  as Map<String, Object?>)['started_at']!
              as int,
          isUtc: true,
        );
        final initial = startedAt();
        await pollUntil(
          () => startedAt().isAfter(initial.add(staleThreshold * 3)),
          reason: 'the heartbeat must keep refreshing started_at',
        );
        expect(
          discovery.peers,
          hasLength(1),
          reason: 'heartbeat must keep a live peer past staleThreshold',
        );
        expect(
          removals,
          isEmpty,
          reason: 'a heartbeating peer must never be pruned',
        );

        // remove() stops the heartbeat and deletes the manifest — the
        // peer disappears from discovery.
        await writer.remove();
        await pollUntil(
          () => discovery.peers.isEmpty,
          reason: 'a removed manifest must drop the peer',
        );
      },
    );

    test(
      'without a heartbeat a stale manifest is pruned and deleted',
      () async {
        final writer = CxpManifestWriter(
          manifestDirectory: tempDir.path,
          heartbeatInterval: null,
        );
        addTearDown(writer.remove);
        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          // Deletion is owner-scoped; this discovery owns the manifest
          // under test, so the file goes away as well as the view entry.
          selfPeerId: 'wavecrux-$pid-2',
          scanInterval: const Duration(milliseconds: 50),
          staleThreshold: const Duration(milliseconds: 150),
        );
        addTearDown(discovery.stop);

        await writer.write(
          // Live pid: alive to liveness pruning, so the TTL is what prunes it.
          identity: PeerIdentity(
            peerId: 'wavecrux-$pid-2',
            productName: 'wavecrux',
            productVersion: '0.0.0',
          ),
          host: '127.0.0.1',
          port: 64511,
        );
        await discovery.start();
        expect(discovery.peers, hasLength(1));

        await pollUntil(
          () =>
              discovery.peers.isEmpty &&
              Directory(tempDir.path)
                  .listSync()
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.json'))
                  .isEmpty,
          reason: 'stale manifests must be pruned and deleted',
        );
      },
    );
  });

  group('two in-process servers — mutual discovery AND connection', () {
    late Directory sharedDir;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('crux_cxp_pair_');
    });

    tearDown(() async {
      await sharedDir.delete(recursive: true);
    });

    test(
      'distinct identities publishing into ONE shared directory discover '
      'each other and both servers see a connected peer',
      () async {
        // ── peer A ("wavecrux") ────────────────────────────────────────
        final idA = PeerIdentity(
          peerId: 'wavecrux-$pid-1',
          productName: 'wavecrux',
          productVersion: '0.3.0',
        );
        final serverA = LocalCxpServer(selfIdentity: idA);
        await serverA.start();
        addTearDown(serverA.stop);
        final writerA = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: const Duration(milliseconds: 100),
        );
        addTearDown(writerA.remove);
        await writerA.write(
          identity: idA,
          host: '127.0.0.1',
          port: serverA.boundPort!,
        );
        final discoveryA = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discoveryA.stop);
        final connectorA = CxpPeerConnector(
          selfIdentity: idA,
          discovery: discoveryA,
          retryInterval: const Duration(milliseconds: 100),
        );
        addTearDown(connectorA.stop);
        await discoveryA.start();
        connectorA.start();

        // ── peer B ("simcrux") ─────────────────────────────────────────
        final idB = PeerIdentity(
          peerId: 'simcrux-$pid-2',
          productName: 'simcrux',
          productVersion: '0.1.0',
        );
        final serverB = LocalCxpServer(selfIdentity: idB);
        await serverB.start();
        addTearDown(serverB.stop);
        final writerB = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: const Duration(milliseconds: 100),
        );
        addTearDown(writerB.remove);
        await writerB.write(
          identity: idB,
          host: '127.0.0.1',
          port: serverB.boundPort!,
        );
        final discoveryB = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discoveryB.stop);
        final connectorB = CxpPeerConnector(
          selfIdentity: idB,
          discovery: discoveryB,
          retryInterval: const Duration(milliseconds: 100),
        );
        addTearDown(connectorB.stop);
        await discoveryB.start();
        connectorB.start();

        // ── mutual discovery (manifest level) ──────────────────────────
        await pollUntil(
          () =>
              discoveryA.peers.any((m) => m.identity.peerId == idB.peerId) &&
              discoveryB.peers.any((m) => m.identity.peerId == idA.peerId),
          reason: 'both discoveries must surface the other peer manifest',
        );

        // ── mutual connection (socket level) ───────────────────────────
        // The symmetric connectors dial each other, so each SERVER gains
        // an inbound Hello — the exact signal every product's cross-probe
        // UI gates on. This is the assertion that fails on pre-fix code
        // (nothing dialed, connectedPeers stayed empty forever).
        await pollUntil(
          () =>
              serverA.connectedPeers.any((p) => p.peerId == idB.peerId) &&
              serverB.connectedPeers.any((p) => p.peerId == idA.peerId),
          reason:
              'both servers must see the other peer CONNECTED '
              '(inbound Hello via the peer connector)',
        );

        // The connector never dials its own manifest.
        expect(
          connectorA.connectedPeers.map((p) => p.peerId),
          isNot(contains(idA.peerId)),
        );

        // ── teardown propagates ────────────────────────────────────────
        // Peer B stops: manifest removed → A's discovery drops it and A's
        // connector tears down the link.
        await connectorB.stop();
        await writerB.remove();
        await serverB.stop();
        await pollUntil(
          () => !discoveryA.peers.any((m) => m.identity.peerId == idB.peerId),
          reason: 'A must drop B after B removes its manifest',
        );
      },
    );

    test(
      'end-to-end product traffic: sendTo reaches the peer handler, the '
      'ack returns, and notify_selection gossip flows — with no '
      'hand-rolled test clients',
      () async {
        // Both peers run the full production stack: server + manifest
        // writer + discovery + connector routed into the server. Every
        // assertion below observes only the two servers' inbound
        // streams — exactly what a real product's request handler
        // subscribes to. This is the round trip that presence-level
        // assertions cannot see: sockets can be connected while every
        // product-level frame is dropped (unlistened connector client)
        // and every broadcast is filtered out (no Subscribe ever sent).
        Future<
          ({
            LocalCxpServer server,
            CxpPeerConnector connector,
            List<InboundCxpMessage> inbound,
          })
        >
        startProduct(PeerIdentity id) async {
          final server = LocalCxpServer(selfIdentity: id);
          await server.start();
          addTearDown(server.stop);
          final writer = CxpManifestWriter(
            manifestDirectory: sharedDir.path,
            heartbeatInterval: const Duration(milliseconds: 100),
          );
          addTearDown(writer.remove);
          await writer.write(
            identity: id,
            host: '127.0.0.1',
            port: server.boundPort!,
          );
          final discovery = CxpDiscovery(
            manifestDirectory: sharedDir.path,
            scanInterval: const Duration(milliseconds: 50),
          );
          addTearDown(discovery.stop);
          final connector = CxpPeerConnector(
            selfIdentity: id,
            discovery: discovery,
            server: server,
            retryInterval: const Duration(milliseconds: 100),
          );
          addTearDown(connector.stop);
          await discovery.start();
          connector.start();
          final inbound = <InboundCxpMessage>[];
          server.inbound.listen(inbound.add);
          return (server: server, connector: connector, inbound: inbound);
        }

        const idA = PeerIdentity(
          peerId: 'wavecrux-e2e-1',
          productName: 'wavecrux',
          productVersion: '0.3.0',
        );
        const idB = PeerIdentity(
          peerId: 'netcrux-e2e-2',
          productName: 'netcrux',
          productVersion: '0.2.0',
        );
        final a = await startProduct(idA);
        final b = await startProduct(idB);

        await pollUntil(
          () =>
              a.server.connectedPeers.any((p) => p.peerId == idB.peerId) &&
              b.server.connectedPeers.any((p) => p.peerId == idA.peerId),
          reason: 'both products must see each other connected',
        );
        // connectedPeers reports reachability (a link suffices), but a
        // one-shot broadcast below needs the peer's auto-Subscribe to
        // have registered on the sending server first — wait for the
        // subscription, not just the socket.
        await pollUntil(
          () =>
              a.server.debugSubscriptionsOf(idB.peerId).isNotEmpty &&
              b.server.debugSubscriptionsOf(idA.peerId).isNotEmpty,
          reason: "both connectors' auto-subscriptions must register",
        );

        // B answers highlight requests over its server — the same
        // single subscription a real product registers.
        const element = ElementId(
          kind: ElementKind.signal,
          path: 'top.core.alu.result',
        );
        b.server.inbound.listen((message) {
          if (message.message is RequestHighlight) {
            b.server.sendTo(
              message.from.peerId,
              RequestHighlightAck(
                inReplyTo: message.envelope.messageId,
                honored: true,
              ),
            );
          }
        });

        // A → B directed request.
        final delivered = a.server.sendTo(
          idB.peerId,
          const RequestHighlight(element: element),
        );
        expect(delivered, isTrue);
        await pollUntil(
          () => b.inbound.any((m) => m.message is RequestHighlight),
          reason: "the request must reach B's product-level handler",
        );
        final request = b.inbound.firstWhere(
          (m) => m.message is RequestHighlight,
        );
        expect(request.from.peerId, idA.peerId);
        expect(
          (request.message as RequestHighlight).element,
          element,
        );

        // B → A ack for that exact request.
        await pollUntil(
          () => a.inbound.any((m) => m.message is RequestHighlightAck),
          reason: "B's ack must arrive back at A",
        );
        final ack =
            a.inbound
                    .firstWhere((m) => m.message is RequestHighlightAck)
                    .message
                as RequestHighlightAck;
        expect(ack.inReplyTo, request.envelope.messageId);
        expect(ack.honored, isTrue);

        // B → everyone gossip; A must receive it without any
        // product-side Subscribe wiring.
        b.server.broadcast(
          const NotifySelection(
            elements: [element],
            displayName: 'result',
          ),
        );
        await pollUntil(
          () => a.inbound.any((m) => m.message is NotifySelection),
          reason: 'notify_selection gossip must reach A',
        );
        expect(
          a.inbound.firstWhere((m) => m.message is NotifySelection).from.peerId,
          idB.peerId,
        );
      },
    );

    test('connector retries until the peer server starts listening', () async {
      final idA = PeerIdentity(
        peerId: 'lintcrux-$pid-1',
        productName: 'lintcrux',
        productVersion: '0.1.0',
      );
      final idB = PeerIdentity(
        peerId: 'netcrux-$pid-2',
        productName: 'netcrux',
        productVersion: '0.1.0',
      );

      // Reserve a port for B, then close it so the first dial fails.
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final portB = probe.port;
      await probe.close();

      // B's manifest exists BEFORE its server listens (launch race).
      final writerB = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: null,
      );
      addTearDown(writerB.remove);
      await writerB.write(identity: idB, host: '127.0.0.1', port: portB);

      final discoveryA = CxpDiscovery(
        manifestDirectory: sharedDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discoveryA.stop);
      final connectorA = CxpPeerConnector(
        selfIdentity: idA,
        discovery: discoveryA,
        retryInterval: const Duration(milliseconds: 100),
      );
      addTearDown(connectorA.stop);
      await discoveryA.start();
      connectorA.start();

      // Let the connector observably fail at least twice, then bring B
      // up — dial attempts, not elapsed time, are the retry evidence.
      await pollUntil(
        () => connectorA.dialAttempts >= 2,
        reason: 'the connector must keep retrying while B is down',
      );
      expect(connectorA.connectedPeers, isEmpty);

      final serverB = LocalCxpServer(selfIdentity: idB, port: portB);
      await serverB.start();
      addTearDown(serverB.stop);

      await pollUntil(
        () => serverB.connectedPeers.any((p) => p.peerId == idA.peerId),
        reason: 'retry loop must connect once the peer starts listening',
      );
    });

    test(
      'a redial reads the manifest again: a new port and token under the '
      'same peer id are the ones dialled',
      () async {
        // CXP §7.4: "A token belongs to one manifest. A dialler refused with
        // a token it read earlier finds the current one by reading the
        // manifest again." Discovery reports only additions and removals,
        // so a manifest rewritten under the same peer id is not an event.
        final idA = PeerIdentity(
          peerId: 'lintcrux-$pid-5',
          productName: 'lintcrux',
          productVersion: '0.1.0',
        );
        final idB = PeerIdentity(
          peerId: 'netcrux-$pid-6',
          productName: 'netcrux',
          productVersion: '0.1.0',
        );

        // B first publishes a port nothing listens on, and a token that is
        // not its server's.
        final probe = await ServerSocket.bind('127.0.0.1', 0);
        final deadPort = probe.port;
        await probe.close();
        final stale = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
          authToken: generateCxpAuthToken(),
        );
        await stale.write(identity: idB, host: '127.0.0.1', port: deadPort);

        final discoveryA = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discoveryA.stop);
        final connectorA = CxpPeerConnector(
          selfIdentity: idA,
          discovery: discoveryA,
          retryInterval: const Duration(milliseconds: 50),
          maxRetryBackoffTicks: 1,
        );
        addTearDown(connectorA.stop);
        await discoveryA.start();
        connectorA.start();
        await pollUntil(
          () => connectorA.dialAttempts >= 2,
          reason: 'the stale manifest is dialled and fails',
        );

        // B's server comes up on a different port with its own token, and
        // the manifest is rewritten in place — same peer id, same file.
        final token = generateCxpAuthToken();
        final serverB = LocalCxpServer(selfIdentity: idB, authToken: token);
        await serverB.start();
        addTearDown(serverB.stop);
        final fresh = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
          authToken: token,
        );
        addTearDown(fresh.remove);
        await fresh.write(
          identity: idB,
          host: '127.0.0.1',
          port: serverB.boundPort!,
        );

        await pollUntil(
          () => serverB.connectedPeers.any((p) => p.peerId == idA.peerId),
          reason: 'the redial must use the current port and token',
        );
      },
    );
  });
}
