// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A CXP peer written from the specification alone: raw sockets, raw JSON,
/// and the §7.4 proofs computed here rather than by the package under test.
///
/// It publishes a manifest into [directory] the way a running app does,
/// listens on a loopback port, and answers the way the specification says a
/// listener answers. What it received is in [received], decoded, so a test
/// can compare the bytes the client put on the wire with the examples in the
/// specification.
class FakePeer {
  FakePeer._({
    required this.directory,
    required this.productName,
    required this.capabilities,
    required this.token,
    required this.peerId,
    required this.onRequest,
    required this.proveBack,
    required this.manifestHost,
    required this.manifestVersion,
  });

  /// Starts a peer and publishes its manifest.
  ///
  /// [onRequest] decides the answer to each `request_highlight` and
  /// `request_open_source`: a map is the payload of the ack to send, null
  /// sends nothing (so the sender times out). [proveBack] false makes the
  /// peer answer the handshake without the §7.4 proof, as a process that
  /// merely bound the port would. [manifestHost] is what the manifest
  /// advertises; [manifestVersion] the `cxp_version` it announces.
  static Future<FakePeer> start({
    required Directory directory,
    String productName = 'wavecrux',
    Set<String> capabilities = const <String>{},
    String token = 'a-token-of-at-least-sixteen-bytes',
    Map<String, Object?>? Function(
      String kind,
      Map<String, Object?> payload,
    )?
    onRequest,
    bool proveBack = true,
    String manifestHost = '127.0.0.1',
    String? manifestVersion = '1.3',
  }) async {
    final peer = FakePeer._(
      directory: directory,
      productName: productName,
      capabilities: capabilities,
      token: token,
      peerId: '$productName-${DateTime.now().microsecondsSinceEpoch}',
      onRequest:
          onRequest ?? (kind, payload) => <String, Object?>{'honored': true},
      proveBack: proveBack,
      manifestHost: manifestHost,
      manifestVersion: manifestVersion,
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    peer._server = server;
    server.listen(peer._accept);
    await peer.writeManifest();
    return peer;
  }

  /// The manifest directory the peer publishes into.
  final Directory directory;

  /// The product name in the peer's identity.
  final String productName;

  /// The capabilities in the peer's identity.
  final Set<String> capabilities;

  /// The token the manifest publishes.
  final String token;

  /// The peer's `peer_id`.
  final String peerId;

  /// Decides the answer to a request; see [start].
  final Map<String, Object?>? Function(
    String kind,
    Map<String, Object?> payload,
  )
  onRequest;

  /// Whether the peer proves it holds the token; see [start].
  final bool proveBack;

  /// The host the manifest advertises.
  final String manifestHost;

  /// The `cxp_version` the manifest announces, or null for none.
  final String? manifestVersion;

  late final ServerSocket _server;
  final List<_Connection> _connections = <_Connection>[];

  /// Every envelope received after the handshake, in order.
  final List<Map<String, Object?>> received = <Map<String, Object?>>[];

  /// Every `hello` payload received.
  final List<Map<String, Object?>> hellos = <Map<String, Object?>>[];

  /// How many `goodbye` envelopes arrived.
  int goodbyes = 0;

  /// The port the peer listens on.
  int get port => _server.port;

  /// Whether a client has completed the handshake and is connected.
  bool get hasClient => _connections.any((c) => c.handshaken && !c.closed);

  /// Received envelopes of [kind].
  List<Map<String, Object?>> receivedOf(String kind) => <Map<String, Object?>>[
    for (final envelope in received)
      if (envelope['kind'] == kind) envelope,
  ];

  /// The identity this peer announces.
  Map<String, Object?> get identity => <String, Object?>{
    'peer_id': peerId,
    'product_name': productName,
    'product_version': '1.2.3',
    'capabilities': capabilities.toList(),
  };

  /// (Re)writes the manifest, atomically, as a running peer does.
  Future<void> writeManifest() async {
    final file = File('${directory.path}/$peerId.json');
    final scratch = File('${file.path}.tmp');
    await scratch.writeAsString(
      jsonEncode(<String, Object?>{
        'identity': identity,
        'host': manifestHost,
        'port': port,
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'token': token,
        'cxp_version': ?manifestVersion,
      }),
    );
    await scratch.rename(file.path);
  }

  /// Sends an envelope of [kind] with [payload] to the connected client.
  void send(String kind, Map<String, Object?> payload) {
    for (final connection in _connections) {
      if (connection.handshaken && !connection.closed) {
        connection.write(<String, Object?>{
          'cxp_version': '1.3',
          'message_id': 'peer-${DateTime.now().microsecondsSinceEpoch}',
          'from': peerId,
          'kind': kind,
          'payload': payload,
        });
      }
    }
  }

  /// Drops every connection without a goodbye, as a crashed app does.
  Future<void> dropClients() async {
    for (final connection in List<_Connection>.of(_connections)) {
      connection.socket.destroy();
    }
  }

  /// Stops listening, closes every connection and removes the manifest.
  Future<void> stop() async {
    await _server.close();
    for (final connection in List<_Connection>.of(_connections)) {
      connection.socket.destroy();
    }
    final file = File('${directory.path}/$peerId.json');
    if (file.existsSync()) file.deleteSync();
  }

  void _accept(Socket socket) {
    final connection = _Connection(this, socket);
    _connections.add(connection);
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          connection.onLine,
          onDone: () => connection.closed = true,
          onError: (Object _) => connection.closed = true,
          cancelOnError: true,
        );
  }

  /// `HMAC-SHA256(key = token, message = "<label>:<nonce>")`, hex, per §7.4.
  String proof(String label, String nonce) => Hmac(
    sha256,
    utf8.encode(token),
  ).convert(utf8.encode('$label:$nonce')).toString();
}

class _Connection {
  _Connection(this.peer, this.socket);

  final FakePeer peer;
  final Socket socket;
  bool handshaken = false;
  bool closed = false;

  void write(Map<String, Object?> envelope) {
    if (closed) return;
    socket.write('${jsonEncode(envelope)}\n');
  }

  void onLine(String line) {
    final envelope = (jsonDecode(line) as Map).cast<String, Object?>();
    final kind = envelope['kind']! as String;
    final payload = (envelope['payload']! as Map).cast<String, Object?>();
    if (!handshaken) {
      if (kind != 'hello') {
        socket.destroy();
        return;
      }
      peer.hellos.add(payload);
      final nonce = payload['nonce'];
      final presentedProof = payload['proof'];
      final presentedToken = payload['token'];
      var authorised = false;
      var ack = <String, Object?>{
        'identity': peer.identity,
        'in_reply_to': envelope['message_id'],
      };
      if (nonce is String && presentedProof is String) {
        authorised = presentedProof == peer.proof('cxp-hello', nonce);
        if (authorised && peer.proveBack) {
          ack = <String, Object?>{
            ...ack,
            'proof': peer.proof('cxp-hello-ack', nonce),
          };
        }
      } else if (presentedToken is String) {
        authorised = presentedToken == peer.token;
      }
      if (!authorised) {
        write(<String, Object?>{
          'cxp_version': '1.3',
          'message_id': 'peer-err',
          'from': peer.peerId,
          'kind': 'error_response',
          'payload': <String, Object?>{
            'code': 'unauthorized',
            'message': 'bad proof',
            'in_reply_to': envelope['message_id'],
          },
        });
        socket.destroy();
        return;
      }
      handshaken = true;
      write(<String, Object?>{
        'cxp_version': '1.3',
        'message_id': 'peer-ack',
        'from': peer.peerId,
        'kind': 'hello_ack',
        'payload': ack,
      });
      return;
    }
    peer.received.add(envelope);
    if (kind == 'goodbye') {
      peer.goodbyes++;
      return;
    }
    if (kind == 'request_highlight' || kind == 'request_open_source') {
      final answer = peer.onRequest(kind, payload);
      if (answer == null) return;
      write(<String, Object?>{
        'cxp_version': '1.3',
        'message_id': 'peer-${DateTime.now().microsecondsSinceEpoch}',
        'from': peer.peerId,
        'kind': '${kind}_ack',
        'payload': <String, Object?>{
          'in_reply_to': envelope['message_id'],
          ...answer,
        },
      });
    }
  }
}
