// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

void main() {
  group('CxpManifestWriter + CxpDiscovery', () {
    late Directory tempDir;
    late CxpDiscovery discovery;
    late CxpManifestWriter writer;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('crux_cxp_disc_');
      discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        scanInterval: const Duration(milliseconds: 100),
        staleThreshold: const Duration(seconds: 30),
      );
      writer = CxpManifestWriter(manifestDirectory: tempDir.path);
    });

    tearDown(() async {
      await discovery.stop();
      await writer.remove();
      await tempDir.delete(recursive: true);
    });

    test('emits added event for a newly-written manifest', () async {
      await discovery.start();
      final addedFuture = discovery.events.firstWhere((e) => e.added);
      await writer.write(
        identity: const PeerIdentity(
          peerId: 'wavecrux-test-1',
          productName: 'wavecrux',
          productVersion: '0.0.0',
        ),
        host: '127.0.0.1',
        port: 64500,
      );
      final event = await addedFuture.timeout(const Duration(seconds: 3));
      expect(event.manifest.identity.peerId, 'wavecrux-test-1');
      expect(event.manifest.port, 64500);
    });

    test('emits removed event when manifest disappears', () async {
      final events = <CxpDiscoveryEvent>[];
      final sub = discovery.events.listen(events.add);

      await writer.write(
        identity: const PeerIdentity(
          peerId: 'wavecrux-test-2',
          productName: 'wavecrux',
          productVersion: '0.0.0',
        ),
        host: '127.0.0.1',
        port: 64501,
      );
      await discovery.start();
      await pollUntil(
        () => events.where((e) => e.added).isNotEmpty,
        reason: 'expected an "added" event for the pre-existing manifest',
      );

      await writer.remove();
      await pollUntil(
        () => events.where((e) => !e.added).isNotEmpty,
        reason: 'expected a "removed" event after the manifest vanished',
      );
      await sub.cancel();

      final removed = events.where((e) => !e.added).toList();
      expect(removed, isNotEmpty);
      expect(removed.first.manifest.identity.peerId, 'wavecrux-test-2');
    });

    test('deletes our OWN manifest once it passes staleThreshold', () async {
      const staleManifest = PeerIdentity(
        peerId: 'stale-peer',
        productName: 'wavecrux',
        productVersion: '0.0.0',
      );
      // Deletion is scoped to the manifest this process owns.
      discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        selfPeerId: staleManifest.peerId,
        scanInterval: const Duration(milliseconds: 100),
        staleThreshold: const Duration(seconds: 30),
      );
      final stalePath = p.join(tempDir.path, '${staleManifest.peerId}.json');
      // Write a manifest with started_at 1 hour ago.
      final old = DateTime.now().subtract(const Duration(hours: 1));
      final manifest = CxpPeerManifest(
        identity: staleManifest,
        host: '127.0.0.1',
        port: 64502,
        startedAt: old.toUtc(),
        manifestPath: stalePath,
      );
      await File(stalePath).writeAsString(
        '{"identity": ${_jsonOf(manifest.identity.toJson())}, '
        '"host": "127.0.0.1", "port": 64502, '
        '"started_at": ${old.millisecondsSinceEpoch}}',
      );

      await discovery.start();
      await pollUntil(
        () => !File(stalePath).existsSync(),
        reason: 'the scanner must delete the stale manifest',
      );
      expect(discovery.peers, isEmpty);
    });

    test(
      "prunes ANOTHER peer's stale manifest from view but leaves the "
      'file on disk',
      () async {
        // The sleep/wake regression: a laptop suspended past the stale
        // threshold wakes with every product's scan running before any
        // product's heartbeat. When each scan deleted the others' files,
        // all four apps wiped each other out and every connector tore down
        // every link. A foreign stale manifest must be treated as absent,
        // never removed — its owner's next heartbeat re-freshens it.
        const foreign = PeerIdentity(
          peerId: 'netcrux-asleep',
          productName: 'netcrux',
          productVersion: '0.0.0',
        );
        final path = p.join(tempDir.path, '${foreign.peerId}.json');
        final old = DateTime.now().subtract(const Duration(hours: 1));
        await File(path).writeAsString(
          '{"identity": ${_jsonOf(foreign.toJson())}, '
          '"host": "127.0.0.1", "port": 64599, '
          '"started_at": ${old.millisecondsSinceEpoch}}',
        );

        discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-awake',
          scanInterval: const Duration(milliseconds: 50),
          staleThreshold: const Duration(seconds: 30),
        );
        await discovery.start();

        expect(
          discovery.peers,
          isEmpty,
          reason: 'a stale peer must not be reported as reachable',
        );
        // start() completes a scan before it returns, so the deletion — if
        // the ownership check regressed — has already happened by here.
        expect(
          File(path).existsSync(),
          isTrue,
          reason: "another process's manifest must never be deleted",
        );

        // And the owner's heartbeat brings it straight back.
        await File(path).writeAsString(
          '{"identity": ${_jsonOf(foreign.toJson())}, '
          '"host": "127.0.0.1", "port": 64599, '
          '"started_at": ${DateTime.now().millisecondsSinceEpoch}}',
        );
        await pollUntil(
          () => discovery.peers.any((m) => m.identity.peerId == foreign.peerId),
          reason: 'a refreshed manifest must re-appear',
        );
      },
    );

    test(
      "reaps ANOTHER peer's manifest from disk once it is older than "
      'reapThreshold',
      () async {
        // R9: a dead session's manifest is pruned from view at
        // staleThreshold but only deleted from disk once it ages past the
        // much longer reapThreshold — long enough that a merely-asleep peer
        // would have re-freshened it on wake, so this never re-arms the
        // sleep/wake mass-delete regression, yet dead files stop piling up.
        const dead = PeerIdentity(
          peerId: 'netcrux-days-ago',
          productName: 'netcrux',
          productVersion: '0.0.0',
        );
        final path = p.join(tempDir.path, '${dead.peerId}.json');
        final old = DateTime.now().subtract(const Duration(hours: 1));
        await File(path).writeAsString(
          '{"identity": ${_jsonOf(dead.toJson())}, '
          '"host": "127.0.0.1", "port": 64600, '
          '"started_at": ${old.millisecondsSinceEpoch}}',
        );

        discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-awake',
          scanInterval: const Duration(milliseconds: 50),
          staleThreshold: const Duration(seconds: 30),
          // Well below the manifest's 1-hour age, so it is reapable.
          reapThreshold: const Duration(minutes: 1),
        );
        await discovery.start();

        await pollUntil(
          () => !File(path).existsSync(),
          reason: 'a foreign manifest older than reapThreshold must be deleted',
        );
        expect(discovery.peers, isEmpty);
      },
    );

    test(
      'the manifest heartbeat keeps a live peer discoverable; once it stops '
      'refreshing the peer goes stale and is pruned',
      () async {
        // §10.3 liveness obligation, end-to-end. The other discovery tests
        // hand-write started_at; this one drives the real CxpManifestWriter
        // heartbeat — the mechanism that discharges the obligation an
        // external implementer must also honour: a live peer refreshes its
        // manifest, and a peer that stops is pruned once it ages out.
        const livePeer = PeerIdentity(
          peerId: 'netcrux-live',
          productName: 'netcrux',
          productVersion: '0.0.0',
        );
        final path = p.join(tempDir.path, '${livePeer.peerId}.json');

        // The observer treats livePeer as FOREIGN, so a stale manifest is
        // pruned from view but never deleted.
        const staleThreshold = Duration(milliseconds: 300);
        discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          scanInterval: const Duration(milliseconds: 40),
          staleThreshold: staleThreshold,
        );
        // A heartbeat well inside the stale window: without it the manifest
        // would age past staleThreshold and be pruned.
        writer = CxpManifestWriter(
          manifestDirectory: tempDir.path,
          heartbeatInterval: const Duration(milliseconds: 50),
        );
        await writer.write(identity: livePeer, host: '127.0.0.1', port: 64777);
        await discovery.start();

        await pollUntil(
          () =>
              discovery.peers.any((m) => m.identity.peerId == livePeer.peerId),
          reason: 'the live peer must be discovered',
        );

        // Liveness: across several full stale windows the heartbeat keeps
        // started_at fresh, so the peer is never pruned.
        await Future<void>.delayed(staleThreshold * 3);
        expect(
          discovery.peers.any((m) => m.identity.peerId == livePeer.peerId),
          isTrue,
          reason:
              'the heartbeat must keep a live peer past the stale threshold',
        );

        // The peer freezes: it stops refreshing but leaves its manifest on
        // disk. remove() cancels the heartbeat (and deletes the file), so
        // drop back the lingering stale manifest a frozen process leaves.
        await writer.remove();
        final old = DateTime.now().toUtc().subtract(const Duration(hours: 1));
        await File(path).writeAsString(
          '{"identity": ${_jsonOf(livePeer.toJson())}, '
          '"host": "127.0.0.1", "port": 64777, '
          '"started_at": ${old.millisecondsSinceEpoch}}',
        );

        await pollUntil(
          () =>
              !discovery.peers.any((m) => m.identity.peerId == livePeer.peerId),
          reason: 'a peer that stops refreshing must be pruned once stale',
        );
        expect(
          File(path).existsSync(),
          isTrue,
          reason:
              "a foreign peer's stale manifest is pruned from view, not "
              'deleted',
        );
      },
    );

    test(
      'remove() waits out a heartbeat write in flight, so its rename cannot '
      'republish the manifest',
      () async {
        // A 1 ms heartbeat keeps a refresh in flight most of the time; across
        // the rounds remove() lands on one. Without the wait, that refresh
        // renames a fresh manifest into place after the delete.
        for (var round = 0; round < 40; round++) {
          final dir = Directory(p.join(tempDir.path, 'round_$round'));
          final w = CxpManifestWriter(
            manifestDirectory: dir.path,
            heartbeatInterval: const Duration(milliseconds: 1),
          );
          await w.write(
            identity: const PeerIdentity(
              peerId: 'racer-1',
              productName: 'Racer',
              productVersion: '0.0.0',
            ),
            host: '127.0.0.1',
            port: 1,
          );
          await Future<void>.delayed(const Duration(milliseconds: 3));
          await w.remove();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(
            dir.listSync().map((e) => p.basename(e.path)),
            isEmpty,
            reason: 'round $round',
          );
        }
      },
    );

    test('sweeps orphaned .json.tmp files left by a failed rename', () async {
      // writeAsString succeeded, rename did not. Nothing swept these:
      // the scan correctly skips non-.json files, so they accumulated for
      // the lifetime of the manifest directory.
      final orphan = File(p.join(tempDir.path, 'dead-peer.json.tmp'));
      await orphan.writeAsString('{"partial": true}');
      await orphan.setLastModified(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      // A temp file from a write in progress must survive.
      final fresh = File(p.join(tempDir.path, 'live-peer.json.tmp'));
      await fresh.writeAsString('{"partial": true}');

      discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        scanInterval: const Duration(milliseconds: 50),
        staleThreshold: const Duration(seconds: 30),
      );
      await discovery.start();

      await pollUntil(
        () => !orphan.existsSync(),
        reason: 'an orphaned temp file older than the cutoff must be swept',
      );
      expect(
        fresh.existsSync(),
        isTrue,
        reason: 'a temp file from a live write must not be swept',
      );
    });

    test('CxpPeerManifest round-trips through fromJson/toJson', () {
      const identity = PeerIdentity(
        peerId: 'p',
        productName: 'p',
        productVersion: '1',
      );
      final started = DateTime.utc(2026, 1, 1, 12);
      final manifest = CxpPeerManifest(
        identity: identity,
        host: '127.0.0.1',
        port: 1234,
        startedAt: started,
        manifestPath: '/tmp/p.json',
      );
      final recovered = CxpPeerManifest.fromJson(
        json: manifest.toJson(),
        manifestPath: '/tmp/p.json',
      );
      expect(recovered, equals(manifest));
    });
  });
}

String _jsonOf(Map<String, Object?> m) {
  final buffer = StringBuffer('{');
  var first = true;
  for (final entry in m.entries) {
    if (!first) buffer.write(', ');
    first = false;
    buffer
      ..write('"')
      ..write(entry.key)
      ..write('": ');
    final v = entry.value;
    if (v is String) {
      buffer
        ..write('"')
        ..write(v)
        ..write('"');
    } else if (v is List) {
      buffer.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) buffer.write(', ');
        final item = v[i];
        if (item is String) {
          buffer
            ..write('"')
            ..write(item)
            ..write('"');
        } else {
          buffer.write(item);
        }
      }
      buffer.write(']');
    } else {
      buffer.write(v);
    }
  }
  buffer.write('}');
  return buffer.toString();
}
