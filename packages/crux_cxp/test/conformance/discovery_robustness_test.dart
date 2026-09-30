// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'poll.dart';

/// A manifest directory is writable by every process running as the user
/// (CXP §11), so a scanner must survive anything it finds there. Every case
/// here pins the rule that one undecodable `.json` file costs exactly that
/// file: the peers around it are still discovered, the periodic scan keeps
/// running, and nothing escapes the timer callback.
///
/// The motivating failure was a `started_at` past what `DateTime`
/// represents. `DateTime.fromMillisecondsSinceEpoch` raises `RangeError` —
/// an `Error` — and the scan loop's `on FormatException` did not catch it,
/// so the loop aborted before it reached the add/remove emission: discovery
/// did not lose one peer, it froze, and the timer re-threw every tick.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crux_cxp_robust_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// A manifest for a peer whose pid is this process, so pid-liveness
  /// reaping treats it as alive and only the decoder decides its fate.
  Map<String, Object?> liveManifest(String peerId, {int port = 65100}) =>
      <String, Object?>{
        'identity': <String, Object?>{
          'peer_id': peerId,
          'product_name': 'netcrux',
          'product_version': '0.0.0',
          'capabilities': <String>[],
        },
        'host': '127.0.0.1',
        'port': port,
        'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      };

  File write(String name, String content) =>
      File(p.join(tempDir.path, name))..writeAsStringSync(content);

  /// The good peer's file name sorts after every bad file below on any
  /// filesystem that lists in name order, so an aborted loop would miss it;
  /// on filesystems that list in another order the pre-fix loop still never
  /// reached the emission that follows it. Either way the assertion is the
  /// same: the good peer is discovered.
  final goodPeerId = 'netcrux-$pid-1785006661556';

  group('CxpPeerManifest.fromJson is total over FormatException', () {
    Map<String, Object?> manifestWith(String key, Object? value) =>
        liveManifest('netcrux-$pid-1')..[key] = value;

    test('rejects a started_at past the DateTime range', () {
      for (final value in <int>[
        CxpPeerManifest.maxEpochMillis + 1,
        -CxpPeerManifest.maxEpochMillis - 1,
        1 << 62,
      ]) {
        expect(
          () => CxpPeerManifest.fromJson(
            json: manifestWith('started_at', value),
            manifestPath: 'x.json',
          ),
          throwsFormatException,
          reason:
              'started_at=$value must be a FormatException, not a '
              'RangeError',
        );
      }
    });

    test('accepts a started_at exactly at the bound', () {
      for (final value in <int>[
        CxpPeerManifest.maxEpochMillis,
        -CxpPeerManifest.maxEpochMillis,
      ]) {
        final m = CxpPeerManifest.fromJson(
          json: manifestWith('started_at', value),
          manifestPath: 'x.json',
        );
        expect(m.startedAt.millisecondsSinceEpoch, value);
      }
    });

    test('rejects a port outside the TCP range', () {
      for (final value in <int>[0, -1, 65536, 1 << 40]) {
        expect(
          () => CxpPeerManifest.fromJson(
            json: manifestWith('port', value),
            manifestPath: 'x.json',
          ),
          throwsFormatException,
          reason: 'port=$value',
        );
      }
    });
  });

  group('one undecodable manifest costs only itself', () {
    // Each entry is a file that the pre-fix scan either skipped correctly
    // (the FormatException shapes) or aborted on (the RangeError shape).
    // They run through one loop so the assertion is about the loop, not
    // about any one decoder path.
    final poison = <String, String>{
      'aaa-not-json.json': 'this is not json {',
      'aab-json-array.json': '[1, 2, 3]',
      'aac-json-scalar.json': '42',
      'aad-missing-identity.json':
          '{"host": "127.0.0.1", "port": 1, '
          '"started_at": 1}',
      'aae-started-at-string.json':
          '{"identity": {"peer_id": "p", '
          '"product_name": "x", "product_version": "1"}, "host": "127.0.0.1", '
          '"port": 1, "started_at": "yesterday"}',
      'aaf-started-at-out-of-range.json':
          '{"identity": {"peer_id": "p", '
          '"product_name": "x", "product_version": "1"}, "host": "127.0.0.1", '
          '"port": 1, "started_at": ${CxpPeerManifest.maxEpochMillis + 1}}',
      'aag-port-out-of-range.json':
          '{"identity": {"peer_id": "p", '
          '"product_name": "x", "product_version": "1"}, "host": "127.0.0.1", '
          '"port": 99999, "started_at": 1}',
      'aah-empty.json': '',
    };

    test(
      'peers written alongside every poison shape are still discovered',
      () async {
        poison.forEach(write);
        write('$goodPeerId.json', jsonEncode(liveManifest(goodPeerId)));

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        await discovery.start();

        // start() has completed one scan; the pre-fix loop aborted in it.
        expect(
          discovery.peers.map((m) => m.identity.peerId),
          [goodPeerId],
          reason: 'the one decodable manifest must be the one peer reported',
        );
      },
    );

    test(
      'the periodic scan survives poison: a peer that appears later is '
      'discovered, and one that leaves is dropped',
      () async {
        poison.forEach(write);
        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          selfPeerId: 'wavecrux-observer',
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final events = <CxpDiscoveryEvent>[];
        discovery.events.listen(events.add);
        await discovery.start();
        expect(discovery.peers, isEmpty);

        // Only a still-running timer can see this file.
        final good = write(
          '$goodPeerId.json',
          jsonEncode(liveManifest(goodPeerId)),
        );
        await pollUntil(
          () => discovery.peers.any((m) => m.identity.peerId == goodPeerId),
          reason: 'the timer must keep scanning past the poison files',
        );
        expect(
          events.where((e) => e.added).map((e) => e.manifest.identity.peerId),
          [goodPeerId],
        );

        good.deleteSync();
        await pollUntil(
          () => discovery.peers.isEmpty,
          reason: 'removal must still be noticed with poison present',
        );
        expect(events.where((e) => !e.added), hasLength(1));
      },
    );

    test('poison files are never deleted while young', () async {
      poison.forEach(write);
      final discovery = CxpDiscovery(
        manifestDirectory: tempDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
      await discovery.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      for (final name in poison.keys) {
        expect(
          File(p.join(tempDir.path, name)).existsSync(),
          isTrue,
          reason: '$name is younger than reapThreshold and must survive',
        );
      }
    });

    test(
      'an undecodable file older than reapThreshold is reaped, so it '
      'stops being re-rejected on every tick forever',
      () async {
        final ancient = write('aaa-ancient-garbage.json', '{not json');
        await ancient.setLastModified(
          DateTime.now().subtract(const Duration(days: 2)),
        );
        final fresh = write('aab-fresh-garbage.json', '{not json');

        final discovery = CxpDiscovery(
          manifestDirectory: tempDir.path,
          scanInterval: const Duration(milliseconds: 50),
          // The default reapThreshold is one day; the ancient file above is
          // two days old and the fresh one is seconds old.
        );
        addTearDown(discovery.stop);
        await discovery.start();

        await pollUntil(
          () => !ancient.existsSync(),
          reason: 'garbage older than reapThreshold must be deleted',
        );
        expect(fresh.existsSync(), isTrue);
      },
    );
  });
}
