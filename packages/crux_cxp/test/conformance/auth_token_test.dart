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

  /// Wire 1.3 (§7.4): neither side sends the token. The dialler proves it
  /// holds the listener's token with an HMAC over a fresh nonce, and the
  /// listener proves the same back under another label. What this closes is
  /// §11.4 item 1 of the 1.2 spec: a process that binds a peer's well-known
  /// port after the peer exits, while the manifest still names it, used to
  /// receive the dialler's token and be accepted as the peer. Now it receives
  /// nothing it can use and is refused for proving nothing.
  group('mutual authentication (wire 1.3)', () {
    test('a proof is HMAC-SHA256 hex, bound to token, nonce and label', () {
      const token = '00112233445566778899aabbccddeeff';
      const nonce = 'ffeeddccbbaa99887766554433221100';
      final hello = cxpAuthProof(
        token: token,
        nonce: nonce,
        label: cxpHelloProofLabel,
      );
      expect(hello, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        cxpAuthProof(token: token, nonce: nonce, label: cxpHelloProofLabel),
        hello,
        reason: 'deterministic, so two implementations can agree',
      );
      expect(
        cxpAuthProof(token: token, nonce: nonce, label: cxpHelloAckProofLabel),
        isNot(hello),
        reason: "the labels keep one side's proof from serving as the other",
      );
      expect(
        cxpAuthProof(
          token: token,
          nonce: generateCxpAuthNonce(),
          label: cxpHelloProofLabel,
        ),
        isNot(hello),
      );
      expect(
        cxpAuthProof(
          token: generateCxpAuthToken(),
          nonce: nonce,
          label: cxpHelloProofLabel,
        ),
        isNot(hello),
      );
      // Vectors computed independently (Python: hmac.new(token_ascii,
      // b'<label>:' + nonce_ascii, sha256).hexdigest()), so a second
      // implementation has something to meet byte for byte.
      expect(
        hello,
        'ca07304b1af591bbca333487f9fd33919e2a352307993796bb75cc8b6050d158',
      );
      expect(
        cxpAuthProof(token: token, nonce: nonce, label: cxpHelloAckProofLabel),
        'c06c21cd14c009182a15dc23f36673f58b92ca7f0007af3d4667be326dba8cbb',
      );
    });

    test('cxpVersionHasMutualAuth reads the manifest version', () {
      expect(cxpVersionHasMutualAuth(null), isFalse);
      expect(cxpVersionHasMutualAuth(''), isFalse);
      expect(cxpVersionHasMutualAuth('1.2'), isFalse);
      expect(cxpVersionHasMutualAuth('1'), isFalse);
      expect(cxpVersionHasMutualAuth('1.3'), isTrue);
      expect(cxpVersionHasMutualAuth('1.10'), isTrue);
      expect(cxpVersionHasMutualAuth('2.0'), isTrue);
      expect(cxpVersionHasMutualAuth('0.9'), isFalse);
      expect(cxpVersionHasMutualAuth('x.3'), isFalse);
      expect(cxpVersionHasMutualAuth('1.x'), isFalse);
      expect(cxpVersionHasMutualAuth(cxpProtocolVersion), isTrue);
    });

    test('a 1.3 dialler and a 1.3 listener prove the token to each other '
        'without sending it', () async {
      final server = LocalCxpServer(selfIdentity: _serverId);
      await server.start();
      addTearDown(server.stop);
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: server.authToken,
        mutualAuth: true,
      );
      expect(client.isConnected, isTrue);
      await pollUntil(
        () => server.connectedPeers.any((x) => x.peerId == _dialerId.peerId),
        reason: 'the proved peer registers',
      );
    });

    test('a Hello proving the wrong token is unauthorized', () async {
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
          mutualAuth: true,
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

    test(
      'a lenient listener that cannot prove the token is refused by a 1.3 '
      'dialler, from the dialling side',
      () async {
        final server = LocalCxpServer(
          selfIdentity: _serverId,
          requireAuthToken: false,
        );
        await server.start();
        addTearDown(server.stop);
        final client = LocalCxpClient(selfIdentity: _dialerId);
        addTearDown(client.dispose);
        final events = <CxpConnectionEvent>[];
        client.events.listen(events.add);
        // The lenient server accepts the Hello whatever it proves, and so
        // answers without a proof — it does not hold the token the dialler
        // read. The dialler must not take that as a peer.
        await expectLater(
          client.connect(
            host: '127.0.0.1',
            port: server.boundPort!,
            token: generateCxpAuthToken(),
            mutualAuth: true,
          ),
          throwsA(
            isA<CxpHandshakeException>().having(
              (e) => e.code,
              'code',
              CxpErrorCode.unauthorized,
            ),
          ),
        );
        expect(client.isConnected, isFalse);
        expect(client.remotePeer, isNull);
        await pollUntil(
          () => events.any((e) => !e.connected),
          reason: 'the refusal surfaces as a disconnect event',
        );
      },
    );

    /// A process that bound the port a manifest names, as another user's
    /// process could after the real peer exits: it reads what arrives and
    /// answers a well-formed `hello_ack`, echoing back anything it was sent.
    Future<({ServerSocket socket, List<Map<String, Object?>> hellos})>
    squatter() async {
      final socket = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(socket.close);
      final hellos = <Map<String, Object?>>[];
      socket.listen((connection) {
        connection
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final envelope = CxpEnvelope.fromJson(
                (jsonDecode(line) as Map).cast<String, Object?>(),
              );
              if (envelope.kind != CxpMessageKind.hello) return;
              hellos.add(envelope.payload);
              // Echo whatever credential came in: under 1.2 that was the
              // token itself, and echoing it is exactly what a squatter
              // could do with it.
              final ack = CxpEnvelope(
                messageId: 'sq-1',
                from: _serverId.peerId,
                kind: CxpMessageKind.helloAck,
                payload: <String, Object?>{
                  'identity': _serverId.toJson(),
                  'in_reply_to': envelope.messageId,
                  'proof': ?envelope.payload['proof'] as String?,
                },
              );
              connection.write(ack.encodeLine());
            });
      });
      return (socket: socket, hellos: hellos);
    }

    test('a squatter on the port is refused by a 1.3 dialler and never sees '
        'the token', () async {
      final squat = await squatter();
      final token = generateCxpAuthToken();
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await expectLater(
        client.connect(
          host: '127.0.0.1',
          port: squat.socket.port,
          token: token,
          mutualAuth: true,
        ),
        throwsA(
          isA<CxpHandshakeException>().having(
            (e) => e.code,
            'code',
            CxpErrorCode.unauthorized,
          ),
        ),
      );
      expect(squat.hellos, hasLength(1));
      final hello = squat.hellos.single;
      expect(hello.containsKey('token'), isFalse);
      expect(hello['nonce'], isA<String>());
      expect(hello['proof'], isA<String>());
      expect(jsonEncode(hello), isNot(contains(token)));
    });

    test('the same squatter is accepted by a 1.2-style dial, which is why '
        'the manifest, not the socket, chooses the handshake', () async {
      final squat = await squatter();
      final client = LocalCxpClient(selfIdentity: _dialerId);
      addTearDown(client.dispose);
      await client.connect(
        host: '127.0.0.1',
        port: squat.socket.port,
        token: generateCxpAuthToken(),
      );
      expect(client.isConnected, isTrue);
      expect(squat.hellos.single['token'], isA<String>());
    });

    /// Reads the `hello_ack` a real server answers [helloPayload] with.
    Future<Map<String, Object?>> ackFor(
      LocalCxpServer server,
      Map<String, Object?> helloPayload,
    ) async {
      final socket = await Socket.connect('127.0.0.1', server.boundPort!);
      addTearDown(socket.destroy);
      final lines = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final first = lines.first;
      socket.write(
        CxpEnvelope(
          messageId: 'raw-1',
          from: _dialerId.peerId,
          kind: CxpMessageKind.hello,
          payload: helloPayload,
        ).encodeLine(),
      );
      final envelope = CxpEnvelope.fromJson(
        (jsonDecode(await first) as Map).cast<String, Object?>(),
      );
      expect(envelope.kind, CxpMessageKind.helloAck);
      return envelope.payload;
    }

    test(
      'a listener proves the token only to a dialler that proved it',
      () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);

        // 1.2 dialler: the token verbatim. Accepted, and owed no proof — it
        // checks none.
        final plain = await ackFor(server, <String, Object?>{
          'identity': _dialerId.toJson(),
          'token': server.authToken,
        });
        expect(plain.containsKey('proof'), isFalse);

        // 1.3 dialler: a proof, answered with the proof under the other label.
        final nonce = generateCxpAuthNonce();
        final proved = await ackFor(server, <String, Object?>{
          'identity': _dialerId.toJson(),
          'nonce': nonce,
          'proof': cxpAuthProof(
            token: server.authToken,
            nonce: nonce,
            label: cxpHelloProofLabel,
          ),
        });
        expect(
          proved['proof'],
          cxpAuthProof(
            token: server.authToken,
            nonce: nonce,
            label: cxpHelloAckProofLabel,
          ),
        );
      },
    );

    test('a lenient listener gives a token-less Hello no proof', () async {
      final server = LocalCxpServer(
        selfIdentity: _serverId,
        requireAuthToken: false,
      );
      await server.start();
      addTearDown(server.stop);
      final ack = await ackFor(server, <String, Object?>{
        'identity': _dialerId.toJson(),
      });
      expect(ack.containsKey('proof'), isFalse);
      final wrong = await ackFor(server, <String, Object?>{
        'identity': _dialerId.toJson(),
        'nonce': generateCxpAuthNonce(),
        'proof': 'not a proof',
      });
      expect(
        wrong.containsKey('proof'),
        isFalse,
        reason:
            'nothing derived from the secret for a dialler that proved '
            'nothing',
      );
    });

    group('through the manifest', () {
      late Directory sharedDir;

      setUp(() async {
        sharedDir = await Directory.systemTemp.createTemp('crux_cxp_mutual_');
      });

      tearDown(() async {
        await sharedDir.delete(recursive: true);
      });

      test('the writer publishes cxp_version and fromJson reads it', () async {
        final writer = CxpManifestWriter(
          manifestDirectory: sharedDir.path,
          heartbeatInterval: null,
        );
        addTearDown(writer.remove);
        await writer.write(identity: _serverId, host: '127.0.0.1', port: 65201);
        final path = p.join(sharedDir.path, '${_serverId.peerId}.json');
        final json = (jsonDecode(File(path).readAsStringSync()) as Map)
            .cast<String, Object?>();
        expect(json['cxp_version'], cxpProtocolVersion);
        final manifest = CxpPeerManifest.fromJson(
          json: json,
          manifestPath: path,
        );
        expect(manifest.cxpVersion, cxpProtocolVersion);
        expect(cxpVersionHasMutualAuth(manifest.cxpVersion), isTrue);
        expect(
          CxpPeerManifest.fromJson(json: manifest.toJson(), manifestPath: path),
          manifest,
        );
        expect(
          CxpPeerManifest.fromJson(
            json: <String, Object?>{...json}..remove('cxp_version'),
            manifestPath: path,
          ).cxpVersion,
          isNull,
          reason: 'a pre-1.3 manifest has none',
        );
      });

      /// A connector dialling whatever [port] a manifest names, written by
      /// hand with the given [token] and, when [cxpVersion] is set, that
      /// version.
      Future<CxpPeerConnector> dialManifest({
        required int port,
        required String token,
        String? cxpVersion,
      }) async {
        File(
          p.join(sharedDir.path, '${_serverId.peerId}.json'),
        ).writeAsStringSync(
          jsonEncode(<String, Object?>{
            'identity': _serverId.toJson(),
            'host': '127.0.0.1',
            'port': port,
            'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            'token': token,
            'cxp_version': ?cxpVersion,
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
        return connector;
      }

      test(
        'a 1.3 manifest naming a squatter: refused, token never sent',
        () async {
          final squat = await squatter();
          final token = generateCxpAuthToken();
          final connector = await dialManifest(
            port: squat.socket.port,
            token: token,
            cxpVersion: '1.3',
          );
          await pollUntil(
            () =>
                connector.lastDialFailures[_serverId.peerId]?.error
                    is CxpHandshakeException,
            reason: 'the squatter must be refused',
          );
          expect(connector.connectedPeers, isEmpty);
          expect(squat.hellos, isNotEmpty);
          for (final hello in squat.hellos) {
            expect(hello.containsKey('token'), isFalse);
          }
        },
      );

      test('a pre-1.3 manifest naming a real peer: the token is presented '
          'and the handshake completes, as 1.2 did', () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final connector = await dialManifest(
          port: server.boundPort!,
          token: server.authToken,
        );
        await pollUntil(
          () => connector.connectedPeers.any(
            (x) => x.peerId == _serverId.peerId,
          ),
          reason: 'a 1.3 dialler still reaches a 1.2 listener',
        );
      });

      test('a 1.3 manifest naming a real peer: proved both ways', () async {
        final server = LocalCxpServer(selfIdentity: _serverId);
        await server.start();
        addTearDown(server.stop);
        final connector = await dialManifest(
          port: server.boundPort!,
          token: server.authToken,
          cxpVersion: cxpProtocolVersion,
        );
        await pollUntil(
          () => connector.connectedPeers.any(
            (x) => x.peerId == _serverId.peerId,
          ),
          reason: 'the proof handshake completes against a real listener',
        );
        expect(connector.lastDialFailures, isEmpty);
      });
    });
  });
}
