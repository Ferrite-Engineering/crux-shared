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

/// CXP is a same-machine protocol, and the manifest that names a peer's
/// address is a file any process running as the user can write. A
/// connector that dialled whatever `host` a manifest carried would stream
/// selection gossip — and hand a full-duplex link into its own dispatch
/// stream — to any address one small JSON file named. These cases pin the
/// rule that the connector dials loopback and nothing else, and refuses
/// before a socket exists rather than after a connect fails.
void main() {
  group('isCxpLoopbackHost', () {
    test('accepts the loopback literals and the name localhost', () {
      for (final host in <String>[
        '127.0.0.1',
        '127.0.0.2',
        '127.255.255.254',
        '::1',
        '[::1]',
        'localhost',
        'LOCALHOST',
        ' 127.0.0.1 ',
      ]) {
        expect(isCxpLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('refuses everything routable, unparseable, or empty', () {
      for (final host in <String>[
        '192.0.2.1', // TEST-NET-1: documentation range, never routed.
        '10.0.0.5',
        '0.0.0.0',
        '::',
        '2001:db8::1',
        'example.com',
        'localhost.attacker.example',
        '127.0.0.1.attacker.example',
        '',
        ' ',
      ]) {
        expect(isCxpLoopbackHost(host), isFalse, reason: '"$host"');
      }
    });
  });

  // CXP §10.5's closed set, checked before any socket opens. Each row is a
  // manifest `host` and the address a dialler connects to — the literal it
  // checked, trimmed and unbracketed — or null when it must refuse.
  group('the loopback set (CXP §10.5)', () {
    void check(List<(String, String?)> rows) {
      for (final (host, dial) in rows) {
        final label = jsonEncode(host);
        expect(cxpLoopbackDialAddress(host), dial, reason: label);
        expect(isCxpLoopbackHost(host), dial != null, reason: label);
      }
    }

    test('the corpus shared with the TypeScript implementation', () {
      check(_corpusHosts);
    });

    test('spellings only a platform address parser reads as loopback', () {
      check(_parserOnlyHosts);
    });

    test('RFC 3986 forms of ::1, and near misses', () {
      check(_rfc3986Hosts);
    });
  });

  group('CxpPeerConnector', () {
    late Directory sharedDir;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('crux_cxp_dial_');
    });

    tearDown(() async {
      await sharedDir.delete(recursive: true);
    });

    test(
      'a manifest naming a non-loopback host is refused without a socket, '
      'and the refusal is reported as a dial failure',
      () async {
        const remote = PeerIdentity(
          peerId: 'evil-dial-1',
          productName: 'evil',
          productVersion: '0.0.0',
        );
        final writer = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
        );
        addTearDown(writer.remove);
        await writer.write(identity: remote, host: '192.0.2.1', port: 54322);

        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final client = _RecordingClient();
        final connector = CxpPeerConnector(
          selfIdentity: const PeerIdentity(
            peerId: 'wavecrux-dial-1',
            productName: 'wavecrux',
            productVersion: '0.0.0',
          ),
          discovery: discovery,
          retryInterval: const Duration(milliseconds: 30),
          clientFactory: (_) => client,
        );
        addTearDown(connector.dispose);
        final failures = <CxpDialFailure>[];
        connector.dialFailures.listen(failures.add);
        await discovery.start();
        connector.start();

        await pollUntil(
          () => failures.length >= 2,
          reason: 'the refusal must be reported, and re-reported on retry',
        );
        expect(
          discovery.peers.map((m) => m.identity.peerId),
          [remote.peerId],
          reason: 'the manifest itself is still visible to discovery',
        );
        expect(
          client.connectCalls,
          isEmpty,
          reason: 'no socket may be opened towards a non-loopback host',
        );
        expect(
          connector.dialAttempts,
          0,
          reason: 'a refused dial is not an attempt',
        );
        final failure = connector.lastDialFailures[remote.peerId];
        expect(failure, isNotNull);
        expect(failure!.host, '192.0.2.1');
        expect(failure.error, isA<CxpDialRefusedException>());
        expect(
          (failure.error as CxpDialRefusedException).reason,
          contains('non-loopback'),
        );
        expect(
          failures.last.nextRetryAfterTicks,
          greaterThan(failures.first.nextRetryAfterTicks),
          reason: 'a refused peer backs off like any other failure',
        );
      },
    );

    test(
      'the connector dials the address it checked, not the manifest '
      'spelling, and refuses a parser-only spelling without a socket',
      () async {
        final hosts = <String, String>{
          'spelling-a-1': ' 127.0.0.1 ',
          'spelling-b-1': '[::1]',
          'spelling-c-1': 'LOCALHOST',
          'spelling-d-1': '0127.0.0.1',
        };
        for (final MapEntry(key: peerId, value: host) in hosts.entries) {
          final writer = CxpManifestWriter(
            manifestDirectory: sharedDir.path,
            heartbeatInterval: null,
          );
          addTearDown(writer.remove);
          await writer.write(
            identity: PeerIdentity(
              peerId: peerId,
              productName: peerId,
              productVersion: '0.0.0',
            ),
            host: host,
            port: 54322,
          );
        }

        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final dialled = <String>[];
        final connector = CxpPeerConnector(
          selfIdentity: const PeerIdentity(
            peerId: 'wavecrux-dial-3',
            productName: 'wavecrux',
            productVersion: '0.0.0',
          ),
          discovery: discovery,
          retryInterval: const Duration(milliseconds: 30),
          clientFactory: (_) => _RecordingClient(dialled),
        );
        addTearDown(connector.dispose);
        await discovery.start();
        connector.start();

        await pollUntil(
          () =>
              dialled.toSet().length == 3 &&
              connector.lastDialFailures.containsKey('spelling-d-1'),
          reason: 'three dials and one refusal',
        );
        expect(dialled.toSet(), {'127.0.0.1', '::1', 'localhost'});
        final refused = connector.lastDialFailures['spelling-d-1']!;
        expect(refused.error, isA<CxpDialRefusedException>());
        expect(refused.host, '0127.0.0.1', reason: 'reported as published');
      },
    );

    test('a loopback manifest is still dialled', () async {
      const remote = PeerIdentity(
        peerId: 'netcrux-dial-2',
        productName: 'netcrux',
        productVersion: '0.0.0',
      );
      final server = LocalCxpServer(selfIdentity: remote);
      await server.start();
      addTearDown(server.stop);
      final writer = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: null,
      );
      addTearDown(writer.remove);
      await writer.write(
        identity: remote,
        host: '127.0.0.1',
        port: server.boundPort!,
      );

      final discovery = CxpDiscovery(
        manifestDirectory: sharedDir.path,
        scanInterval: const Duration(milliseconds: 50),
      );
      addTearDown(discovery.stop);
      final connector = CxpPeerConnector(
        selfIdentity: const PeerIdentity(
          peerId: 'wavecrux-dial-2',
          productName: 'wavecrux',
          productVersion: '0.0.0',
        ),
        discovery: discovery,
        retryInterval: const Duration(milliseconds: 50),
      );
      addTearDown(connector.dispose);
      await discovery.start();
      connector.start();

      await pollUntil(
        () => connector.connectedPeers.any((p) => p.peerId == remote.peerId),
        reason: 'loopback must still connect',
      );
      expect(connector.dialAttempts, greaterThanOrEqualTo(1));
    });
  });
}

/// The `hosts` of the containment corpus the TypeScript implementation
/// (`host-core`) is cross-checked against, with §10.5's answers. The two
/// agree on every row but `[127.0.0.1]`: §10.5 admits square brackets
/// around the IPv6 literal only, as RFC 3986's IP-literal does, and
/// `host-core` also unbrackets an IPv4 one.
const List<(String, String?)> _corpusHosts = [
  ('127.0.0.1', '127.0.0.1'),
  ('127.0.0.2', '127.0.0.2'),
  ('127.255.255.254', '127.255.255.254'),
  ('::1', '::1'),
  ('[::1]', '::1'),
  ('localhost', 'localhost'),
  ('LOCALHOST', 'localhost'),
  (' 127.0.0.1 ', '127.0.0.1'),
  ('192.0.2.1', null),
  ('10.0.0.5', null),
  ('0.0.0.0', null),
  ('::', null),
  ('2001:db8::1', null),
  ('example.com', null),
  ('localhost.attacker.example', null),
  ('127.0.0.1.attacker.example', null),
  ('', null),
  (' ', null),
  ('::ffff:127.0.0.1', null),
  ('::127.0.0.1', null),
  ('127.1', null),
  ('0x7f.0.0.1', null),
  ('2130706433', null),
  ('127.0.0.256', null),
  ('127.0.0.1.', null),
  ('.127.0.0.1', null),
  ('127..0.1', null),
  ('128.0.0.1', null),
  ('126.255.255.255', null),
  ('255.255.255.255', null),
  ('\u0661\u0662\u0667.0.0.1', null),
  ('0:0:0:0:0:0:0:1', '0:0:0:0:0:0:0:1'),
  ('0::1', '0::1'),
  ('::0:1', '::0:1'),
  ('::2', null),
  ('::1%lo0%x', null),
  ('fe80::1%lo0', null),
  ('[::1', null),
  ('::1]', null),
  ('[ ::1 ]', null),
  ('[127.0.0.1]', null),
  ('::1/128', null),
  ('127.0.0.1:54322', null),
  ('[::1]:54322', null),
  ('Localhost', 'localhost'),
  ('localhost.', null),
  ('\tlocalhost\n', 'localhost'),
  ('\u00a0127.0.0.1', '127.0.0.1'),
  ('\ufeff127.0.0.1', '127.0.0.1'),
  ('\u0085127.0.0.1', '127.0.0.1'),
  ('\u2028localhost', 'localhost'),
];

/// The same corpus's spellings that a platform address parser reads as
/// loopback — leading zeros, a five-digit group, zone identifiers, an
/// embedded NUL. §10.5 names them as outside the set.
const List<(String, String?)> _parserOnlyHosts = [
  ('0127.0.0.1', null),
  ('127.000.000.001', null),
  ('0000127.0.0.1', null),
  ('127.0.0.01', null),
  ('::00001', null),
  ('::1%lo0', null),
  ('::1%25lo0', null),
  ('::1%', null),
  ('::1%/x', null),
  ('127.0.0.1\x00', null),
  ('127.0.0.1\x00.attacker.example', null),
];

/// Further forms the RFC 3986 `IPv6address` production admits for `::1`,
/// and near misses around it and around the IPv4 and `localhost` rules.
const List<(String, String?)> _rfc3986Hosts = [
  ('::0.0.0.1', '::0.0.0.1'),
  ('0:0:0:0:0:0:0.0.0.1', '0:0:0:0:0:0:0.0.0.1'),
  (
    '0000:0000:0000:0000:0000:0000:0000:0001',
    '0000:0000:0000:0000:0000:0000:0000:0001',
  ),
  ('::0001', '::0001'),
  ('0:0::1', '0:0::1'),
  ('0:0:0:0:0:0::1', '0:0:0:0:0:0::1'),
  ('0:0:0:0:0:0:0::', null),
  ('::0:0:0:0:0:1', '::0:0:0:0:0:1'),
  ('::0:0:0:0:0:0:1', '::0:0:0:0:0:0:1'),
  ('0:0:0:0:0:0:0:0:1', null),
  ('0:0:0:0:0:0:0::1', null),
  (':::1', null),
  ('::1::', null),
  ('0::0::1', null),
  (':0:0:0:0:0:0:0:1', null),
  ('0:0:0:0:0:0:0:1:', null),
  ('::1:', null),
  ('::g', null),
  ('::1.0', null),
  ('::0.0.0.01', null),
  ('::0.0.0.256', null),
  ('::00000.0.0.1', null),
  ('[0:0:0:0:0:0:0:1]', '0:0:0:0:0:0:0:1'),
  ('[::0.0.0.1]', '::0.0.0.1'),
  ('[localhost]', null),
  ('[[::1]]', null),
  ('[]', null),
  ('::FFFF:127.0.0.1', null),
  ('::ffff:7f00:1', null),
  ('0:0:0:0:0:ffff:127.0.0.1', null),
  ('::1 ', '::1'),
  ('\u00a0::1', '::1'),
  ('1.2.3.4', null),
  ('127.0.0.0', '127.0.0.0'),
  ('127.255.255.255', '127.255.255.255'),
  ('127.0.0.1\n', '127.0.0.1'),
  ('localhost\x00', null),
  ('LocalHost', 'localhost'),
  ('\u212a', null),
  ('localhosT', 'localhost'),
  ('127.0.0.1/8', null),
  ('127.0.0.1%lo0', null),
  ('+127.0.0.1', null),
  ('127.0.0.+1', null),
  ('12\u00b7', null),
  ('::1:0', null),
  ('1::', null),
  ('::1.2.3.4.5', null),
  ('0:0:0:0:0:0:0.0.1', null),
];

/// A client that records every connect request and never opens a socket.
class _RecordingClient implements CxpClient {
  _RecordingClient([List<String>? hosts]) : hosts = hosts ?? <String>[];

  final List<({String host, int port})> connectCalls = [];

  /// Every host this client was asked to connect to, shareable across
  /// clients.
  final List<String> hosts;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? token,
  }) async {
    connectCalls.add((host: host, port: port));
    hosts.add(host);
    throw const SocketException('recording client never connects');
  }

  @override
  Future<void> disconnect() async {}

  @override
  void send(CxpMessage message) {}

  @override
  Stream<CxpClientInbound> get inbound => const Stream.empty();

  @override
  Stream<CxpConnectionEvent> get events => const Stream.empty();

  @override
  bool get isConnected => false;

  @override
  PeerIdentity get selfIdentity => const PeerIdentity(
    peerId: 'recording',
    productName: 'test',
    productVersion: '0',
  );

  @override
  PeerIdentity? get remotePeer => null;
}
