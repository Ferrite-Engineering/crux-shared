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

const PeerIdentity _serverId = PeerIdentity(
  peerId: 'wavecrux-auth-1',
  productName: 'wavecrux',
  productVersion: '0.0.0',
);

const PeerIdentity _dialerId = PeerIdentity(
  peerId: 'netcrux-auth-2',
  productName: 'netcrux',
  productVersion: '0.0.0',
);

/// The peer-authentication rule of wire 1.2: a server requires the token
/// it published in its manifest, a dialler presents the token it read
/// there, and nothing else about the handshake changes.
///
/// What this closes is stated on `cxpProcessAuthToken`: every product
/// binds a fixed loopback port, loopback is reachable by processes the
/// spec's trust model never included (another local user, a sandboxed
/// app, a container), and the manifest lives in the user's private
/// directory — so presenting the token proves exactly the file access the
/// spec already assumes. The cases here pin both halves: a dialler without
/// the token is refused before it becomes a peer, and the shared stack
/// carries the token end to end with no per-product wiring.
void main() {
  group('the process token', () {
    test('is 32 lowercase hex digits and stable', () {
      expect(cxpProcessAuthToken, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(cxpProcessAuthToken, same(cxpProcessAuthToken));
    });

    test('generateCxpAuthToken mints a fresh value each time', () {
      final a = generateCxpAuthToken();
      final b = generateCxpAuthToken();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(b));
      expect(a, isNot(cxpProcessAuthToken));
    });

    test('cxpAuthTokensMatch', () {
      const token = 'abc123';
      expect(cxpAuthTokensMatch(token, token), isTrue);
      expect(cxpAuthTokensMatch(null, token), isFalse);
      expect(cxpAuthTokensMatch('', token), isFalse);
      expect(cxpAuthTokensMatch('abc124', token), isFalse);
      expect(cxpAuthTokensMatch('abc12', token), isFalse);
      expect(cxpAuthTokensMatch('abc1234', token), isFalse);
      expect(cxpAuthTokensMatch('ABC123', token), isFalse);
    });
  });

  group('LocalCxpServer requires its token', () {
    test(
      'a Hello without the token is answered unauthorized, closed, and '
      'never becomes a peer',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final presence = <PeerPresenceEvent>[];
        server.presence.listen(presence.add);

        final client = LocalCxpClient(selfIdentity: _dialerId);
        addTearDown(client.dispose);
        final events = <CxpConnectionEvent>[];
        client.events.listen(events.add);
        await expectLater(
          client.connect(host: '127.0.0.1', port: server.boundPort!),
          throwsA(
            isA<CxpHandshakeException>().having(
              (e) => e.code,
              'code',
              CxpErrorCode.unauthorized,
            ),
          ),
        );
        expect(client.isConnected, isFalse);
        expect(server.connectedPeers, isEmpty);
        expect(presence, isEmpty, reason: 'no presence for a refused Hello');
        // The broadcast controller delivers asynchronously, after the
        // handshake future has already thrown.
        await pollUntil(
          () => events.any((e) => !e.connected),
          reason: 'the refusal must surface as a disconnect event',
        );
        expect(
          events.last.error.toString(),
          isNot(contains(server.authToken)),
          reason: 'the refusal must not disclose the token',
        );
      },
    );

    test('a Hello with the wrong token is refused the same way', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await expectLater(
        client.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: generateCxpAuthToken(),
        ),
        throwsA(
          isA<CxpHandshakeException>().having(
            (e) => e.code,
            'code',
            CxpErrorCode.unauthorized,
          ),
        ),
      );
      expect(server.connectedPeers, isEmpty);
    });

    test('a Hello with the token completes the handshake', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
      );
      expect(client.isConnected, isTrue);
      expect(client.remotePeer?.peerId, _serverId.peerId);
      await pollUntil(
        () => server.connectedPeers.any((x) => x.peerId == _dialerId.peerId),
        reason: 'the authenticated peer registers',
      );
    });

    test('an explicit token replaces the process token', () async {
      final token = generateCxpAuthToken();
      final server = LocalCxpServer(selfIdentity: _serverId, authToken: token);
      await server.start();
      addTearDown(server.stop);
      expect(server.authToken, token);

      final withProcessToken = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(withProcessToken.dispose);
      await expectLater(
        withProcessToken.connect(
          host: '127.0.0.1',
          port: server.boundPort!,
          token: cxpProcessAuthToken,
        ),
        throwsA(isA<CxpHandshakeException>()),
      );

      final withExplicit = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(withExplicit.dispose);
      await withExplicit.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: token,
      );
      expect(withExplicit.isConnected, isTrue);
    });

    test(
      'requireAuthToken: false accepts a Hello without one (pre-1.2 peers)',
      () async {
        final server = LocalCxpServer(
          selfIdentity: _serverId,
          requireAuthToken: false,
        );
        await server.start();
        addTearDown(server.stop);
        final client = LocalCxpClient(selfIdentity: _dialerId);
        addTearDown(client.dispose);
        await client.connect(host: '127.0.0.1', port: server.boundPort!);
        expect(client.isConnected, isTrue);
      },
    );

    test('a refused client is reusable against a peer that accepts', () async {
      final strict = LocalCxpServer(selfIdentity: _serverId);
      await strict.start();
      addTearDown(strict.stop);
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await expectLater(
        client.connect(host: '127.0.0.1', port: strict.boundPort!),
        throwsA(isA<CxpHandshakeException>()),
      );
      await client.connect(
        host: '127.0.0.1',
        port: strict.boundPort!,
        token: strict.authToken,
      );
      expect(client.isConnected, isTrue);
    });
  });

  group('the token travels through the manifest', () {
    late Directory sharedDir;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('crux_cxp_auth_');
    });

    tearDown(() async {
      await sharedDir.delete(recursive: true);
    });

    test(
      'CxpManifestWriter publishes its token and fromJson reads it',
      () async {
        final token = generateCxpAuthToken();
        final writer = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
          authToken: token,
        );
        addTearDown(writer.remove);
        await writer.write(identity: _serverId, host: '127.0.0.1', port: 65200);
        final path = p.join(sharedDir.path, '${_serverId.peerId}.json');
        final json = (jsonDecode(File(path).readAsStringSync()) as Map)
            .cast<String, Object?>();
        expect(json['token'], token);
        final manifest = CxpPeerManifest.fromJson(
          json: json,
          manifestPath: path,
        );
        expect(manifest.token, token);
        expect(manifest.toString(), isNot(contains(token)));
        expect(
          CxpPeerManifest.fromJson(json: manifest.toJson(), manifestPath: path),
          manifest,
        );
      },
    );

    test('the writer defaults to the process token, as the server does', () {
      final writer = CxpManifestWriter(manifestDirectory: sharedDir.path);
      final server = LocalCxpServer(selfIdentity: _serverId);
      expect(writer.authToken, cxpProcessAuthToken);
      expect(server.authToken, cxpProcessAuthToken);
    });

    test('a pre-1.2 manifest without a token decodes with token: null', () {
      final manifest = CxpPeerManifest.fromJson(
        json: <String, Object?>{
          'identity': _serverId.toJson(),
          'host': '127.0.0.1',
          'port': 1,
          'started_at': 0,
        },
        manifestPath: 'x.json',
      );
      expect(manifest.token, isNull);
      expect(manifest.toJson().containsKey('token'), isFalse);
      expect(
        CxpPeerManifest.fromJson(
          json: <String, Object?>{...manifest.toJson(), 'token': ''},
          manifestPath: 'x.json',
        ).token,
        isNull,
        reason: 'an empty token is no token',
      );
    });

    Future<
      ({
        LocalCxpServer server,
        CxpPeerConnector connector,
        CxpManifestWriter writer,
      })
    >
    startPeer(
      PeerIdentity id, {
      String? serverToken,
      String? publishedToken,
    }) async {
      final server = LocalCxpServer(selfIdentity: id, authToken: serverToken);
      await server.start();
      addTearDown(server.stop);
      final writer = CxpManifestWriter(
        manifestDirectory: sharedDir.path,
        heartbeatInterval: const Duration(milliseconds: 100),
        authToken: publishedToken ?? server.authToken,
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
        retryInterval: const Duration(milliseconds: 50),
        maxRetryBackoffTicks: 1,
      );
      addTearDown(connector.dispose);
      await discovery.start();
      connector.start();
      return (server: server, connector: connector, writer: writer);
    }

    test(
      'two peers with distinct explicit tokens connect both ways with no '
      'wiring beyond the manifest',
      () async {
        final a = await startPeer(
          _serverId,
          serverToken: generateCxpAuthToken(),
        );
        final b = await startPeer(
          _dialerId,
          serverToken: generateCxpAuthToken(),
        );
        expect(a.server.authToken, isNot(b.server.authToken));
        await pollUntil(
          () =>
              a.server.connectedPeers.any(
                (x) => x.peerId == _dialerId.peerId,
              ) &&
              b.server.connectedPeers.any((x) => x.peerId == _serverId.peerId),
          reason:
              'each connector must present the token from the other '
              'manifest and be accepted',
        );
        expect(a.connector.lastDialFailures, isEmpty);
        expect(b.connector.lastDialFailures, isEmpty);
      },
    );

    test(
      'a manifest publishing the wrong token is refused, and the refusal '
      'is a recorded dial failure',
      () async {
        // A publishes a token its server does not hold — a stale manifest,
        // or a file somebody else wrote. B dials A with it and is refused.
        // A is observed only through B, so it is started and not held.
        await startPeer(
          _serverId,
          serverToken: generateCxpAuthToken(),
          publishedToken: generateCxpAuthToken(),
        );
        final b = await startPeer(
          _dialerId,
          serverToken: generateCxpAuthToken(),
        );
        await pollUntil(
          () => b.connector.lastDialFailures.containsKey(_serverId.peerId),
          reason: "B's dial to A must fail",
        );
        final failure = b.connector.lastDialFailures[_serverId.peerId]!;
        expect(
          failure.error,
          isA<CxpHandshakeException>().having(
            (e) => e.code,
            'code',
            CxpErrorCode.unauthorized,
          ),
        );
        // The refusal is B's link to A never connecting. A's server may still
        // list B: its connectedPeers includes the links A's own connector
        // dialled, and A's dial to B succeeds (below) — asserting A's list
        // was a race between the two dials.
        expect(
          b.connector.connectedPeers.map((x) => x.peerId),
          isNot(contains(_serverId.peerId)),
        );
        // A's own dial to B carries B's correct token and succeeds, so B's
        // server sees A — the asymmetric case the connector already handles.
        await pollUntil(
          () =>
              b.server.connectedPeers.any((x) => x.peerId == _serverId.peerId),
          reason: "A's dial to B is unaffected",
        );
      },
    );

    test(
      'a pre-1.2 manifest (no token) is refused by a strict server and '
      'accepted by one with requireAuthToken: false',
      () async {
        final strict = LocalCxpServer(selfIdentity: _serverId);
        await strict.start();
        addTearDown(strict.stop);
        // Hand-written, as a 1.1 peer would publish it: no token field.
        File(
          p.join(sharedDir.path, '${_serverId.peerId}.json'),
        ).writeAsStringSync(
          jsonEncode(<String, Object?>{
            'identity': _serverId.toJson(),
            'host': '127.0.0.1',
            'port': strict.boundPort,
            'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          }),
        );
        final discovery = CxpDiscovery(
          manifestDirectory: sharedDir.path,
          scanInterval: const Duration(milliseconds: 50),
        );
        addTearDown(discovery.stop);
        final connector = CxpPeerConnector(
          selfIdentity: _dialerId,
          discovery: discovery,
          retryInterval: const Duration(milliseconds: 50),
          maxRetryBackoffTicks: 1,
        );
        addTearDown(connector.dispose);
        await discovery.start();
        connector.start();
        await pollUntil(
          () =>
              connector.lastDialFailures[_serverId.peerId]?.error
                  is CxpHandshakeException,
          reason: 'a token-less dial must be refused by a strict server',
        );

        // The same manifest against a lenient server on the same port.
        final port = strict.boundPort!;
        await strict.stop();
        final lenient = LocalCxpServer(
          selfIdentity: _serverId,
          port: port,
          requireAuthToken: false,
        );
        await lenient.start();
        addTearDown(lenient.stop);
        await pollUntil(
          () => lenient.connectedPeers.any((x) => x.peerId == _dialerId.peerId),
          reason: 'a lenient server accepts the pre-1.2 dialler',
        );
      },
    );
  });
}
