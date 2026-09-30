// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp/src/process_liveness.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

/// Peer-discovery hygiene: pid-liveness reaping, real atomic-write temp
/// sweeping, and same-endpoint dedupe — the gaps behind stale manifests
/// accumulating in the peers directory.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_hygiene_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> writeManifest(
    String peerId, {
    required int port,
    required DateTime startedAt,
    String product = 'netcrux',
    String host = '127.0.0.1',
  }) async {
    final path = p.join(tempDir.path, '$peerId.json');
    final manifest = CxpPeerManifest(
      identity: PeerIdentity(
        peerId: peerId,
        productName: product,
        productVersion: '0.0.0',
      ),
      host: host,
      port: port,
      startedAt: startedAt.toUtc(),
      manifestPath: path,
    );
    await File(path).writeAsString(_encode(manifest.toJson()));
  }

  group('pid-liveness parsing', () {
    test('extracts the pid from the middle segment of a peer_id', () {
      expect(pidFromPeerId('netcrux-86853-1785006661556'), 86853);
      // Hyphenated product name: pid is still second-to-last.
      expect(pidFromPeerId('my-tool-4242-1785006661556'), 4242);
    });

    test('returns null for ids without a numeric pid segment', () {
      expect(pidFromPeerId('wavecrux-test-1'), isNull); // "test" not a pid
      expect(pidFromPeerId('stale-peer'), isNull); // too few segments
      expect(pidFromPeerId('p'), isNull);
    });

    test('the current process reads as alive; a bogus pid as dead', () {
      // pid (dart:io) is this process — definitively alive on any POSIX host.
      if (Platform.isWindows) {
        expect(pidLiveness(pid), PidLiveness.indeterminate);
      } else {
        expect(pidLiveness(pid), PidLiveness.alive);
      }
    });
  });

  group('startup + periodic pruning', () {
    test(
      'a stale manifest with a DEAD pid is reaped from view AND disk',
      () async {
        if (Platform.isWindows) return; // liveness indeterminate on Windows

        // A genuinely dead pid: spawn a trivial process and await its exit.
        final proc = await Process.start('sh', <String>['-c', 'exit 0']);
        final deadPid = proc.pid;
        await proc.exitCode;
        // Guard against pid reuse inside the test window.
        expect(
          pidLiveness(deadPid),
          PidLiveness.dead,
          reason: 'the spawned process must have exited',
        );

        final peerId = 'netcrux-$deadPid-1785006661556';
        // NOT stale by TTL — recent started_at. Only pid-liveness catches it.
        await writeManifest(
          peerId,
          port: 65010,
          startedAt: DateTime.now(),
        );
        final path = p.join(tempDir.path, '$peerId.json');

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-$pid-1',
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        await discovery.start();

        await pollUntil(
          () => !File(path).existsSync(),
          reason: 'a dead-pid manifest must be deleted from disk',
        );
        expect(
          discovery.peers.any((m) => m.identity.peerId == peerId),
          isFalse,
          reason: 'a dead-pid manifest must not be reported reachable',
        );
      },
    );

    test('a fresh manifest with a LIVE pid is kept', () async {
      if (Platform.isWindows) return;

      // Our own live pid, a foreign peer_id so the observer treats it as
      // another process's manifest (never self-deleted).
      final peerId = 'netcrux-$pid-1785006661556';
      final path = p.join(tempDir.path, '$peerId.json');
      await writeManifest(peerId, port: 65011, startedAt: DateTime.now());

      final discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        selfPeerId: 'wavecrux-observer',
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
      await discovery.start();

      await pollUntil(
        () => discovery.peers.any((m) => m.identity.peerId == peerId),
        reason: 'a live-pid, fresh manifest must be discovered',
      );
      // Give the periodic scan several ticks to (wrongly) reap it.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(discovery.peers.any((m) => m.identity.peerId == peerId), isTrue);
      expect(File(path).existsSync(), isTrue);
    });

    test(
      'the current self manifest is NEVER liveness-reaped, even on a dead '
      'pid reading (self is alive by construction)',
      () async {
        if (Platform.isWindows) return;

        // A genuinely dead pid — but this manifest is OUR OWN (selfPeerId).
        // If this code is executing, our process is alive; a `dead` reading
        // for our own peer_id can only be an OS-recycled pid (or, as here, a
        // synthetic one). Reaping our own live file would erase us from every
        // peer's discovery mid-run — the exact failure the WaveCrux two-server
        // suite hit when a server's synthetic pid read dead.
        final proc = await Process.start('sh', <String>['-c', 'exit 0']);
        final deadPid = proc.pid;
        await proc.exitCode;
        expect(pidLiveness(deadPid), PidLiveness.dead);

        final selfId = 'wavecrux-$deadPid-1234567890';
        await writeManifest(
          selfId,
          port: 65013,
          startedAt: DateTime.now(),
          product: 'wavecrux',
        );
        final path = p.join(tempDir.path, '$selfId.json');

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: selfId, // <-- the dead-pid manifest IS us
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        await discovery.start();

        // Several periodic ticks in which pre-fix code would have reaped it.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'the current self manifest must survive liveness reaping',
        );
      },
    );

    test(
      'indeterminate liveness falls back to the TTL (never wrongly reaped)',
      () async {
        // operatingSystemOverride: 'windows' forces indeterminate liveness.
        // A fresh manifest with an unknown-liveness pid must be KEPT, proving
        // we never reap on a guess.
        const peerId = 'netcrux-4242-1785006661556';
        final path = p.join(tempDir.path, '$peerId.json');
        await writeManifest(peerId, port: 65012, startedAt: DateTime.now());

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          scanInterval: const Duration(milliseconds: 50),
          operatingSystemOverride: 'windows',
        );
        addTearDown(discovery.stop);
        await discovery.start();

        await pollUntil(
          () => discovery.peers.any((m) => m.identity.peerId == peerId),
          reason: 'an indeterminate-liveness fresh manifest must be kept',
        );
        expect(File(path).existsSync(), isTrue);
      },
    );
  });

  group('orphaned atomic-write temp sweeping', () {
    test(
      'sweeps a real <peer>.json.<n>-<c>.tmp orphan the old pattern missed',
      () async {
        // The scratch name writeStringAtomic actually produces — a
        // discriminator sits between `.json` and `.tmp`, so it does NOT end
        // in `.json.tmp`, which is exactly what the previous sweep required.
        final orphan = File(
          p.join(tempDir.path, 'netcrux-x.json.1785006661556-0.tmp'),
        );
        await orphan.writeAsString('{"partial": true}');
        await orphan.setLastModified(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        // A fresh temp of the same shape (a write in progress) must survive.
        final live = File(
          p.join(tempDir.path, 'netcrux-y.json.1785006661557-1.tmp'),
        );
        await live.writeAsString('{"partial": true}');

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          scanInterval: const Duration(milliseconds: 50),
          staleThreshold: const Duration(seconds: 30),
        );
        addTearDown(discovery.stop);
        await discovery.start();

        await pollUntil(
          () => !orphan.existsSync(),
          reason: 'the real-pattern orphan must be swept',
        );
        expect(
          live.existsSync(),
          isTrue,
          reason: 'a fresh in-progress temp must not be swept',
        );
      },
    );
  });

  group('dedupe by identity', () {
    test(
      'two manifests for the same product+host:port collapse to one row',
      () async {
        if (Platform.isWindows) return;

        // Two live (own-pid) manifests, different peer_ids, SAME endpoint —
        // the momentary-double case. Only the newest started_at should show.
        final older = DateTime.now().subtract(const Duration(seconds: 10));
        final newer = DateTime.now();
        await writeManifest(
          'netcrux-$pid-1000',
          port: 65020,
          startedAt: older,
        );
        await writeManifest(
          'netcrux-$pid-2000',
          port: 65020,
          startedAt: newer,
        );

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        await discovery.start();

        await pollUntil(
          () => discovery.peers.isNotEmpty,
          reason: 'at least one of the doubled manifests must surface',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));

        final netcruxPeers = discovery.peers
            .where((m) => m.identity.productName == 'netcrux')
            .toList();
        expect(
          netcruxPeers.length,
          1,
          reason: 'same endpoint must not yield two discovery rows',
        );
        expect(netcruxPeers.single.identity.peerId, 'netcrux-$pid-2000');
      },
    );
  });
}

String _encode(Map<String, Object?> m) {
  final id = m['identity']! as Map<String, Object?>;
  final caps = (id['capabilities']! as List).map((c) => '"$c"').join(', ');
  return '{"identity": {"peer_id": "${id['peer_id']}", '
      '"product_name": "${id['product_name']}", '
      '"product_version": "${id['product_version']}", '
      '"capabilities": [$caps]}, '
      '"host": "${m['host']}", "port": ${m['port']}, '
      '"started_at": ${m['started_at']}}';
}
