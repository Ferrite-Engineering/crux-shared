// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crux_cxp/src/line_framing.dart';
import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:crux_cxp/src/messages/decoder.dart';
import 'package:crux_cxp/src/messages/error_response.dart';
import 'package:crux_cxp/src/messages/hello.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Thrown by [CxpClient.connect] when the remote peer rejects the
/// handshake with an `ErrorResponse` (e.g. `unsupported_version`, or
/// `unauthorized` when the Hello did not carry the token the peer
/// published in its manifest) instead of a `HelloAck`.
@immutable
class CxpHandshakeException implements Exception {
  /// Creates a handshake exception.
  const CxpHandshakeException({required this.code, required this.message});

  /// Machine-readable error code (one of `CxpErrorCode`).
  final String code;

  /// Human-readable rejection detail from the remote peer.
  final String message;

  @override
  String toString() => 'CxpHandshakeException($code: $message)';
}

/// Lifecycle event emitted by a [CxpClient] as it connects to or
/// disconnects from a peer.
@immutable
class CxpConnectionEvent {
  /// Creates a connection event.
  const CxpConnectionEvent({required this.connected, this.peer, this.error});

  /// True if the client is now connected; false if it has disconnected.
  final bool connected;

  /// The remote peer's identity after a successful handshake. Null when
  /// [connected] is false or before the handshake completes.
  final PeerIdentity? peer;

  /// Connection error, if [connected] is false because of a failure
  /// rather than a clean disconnect.
  final Object? error;

  @override
  String toString() {
    final state = connected ? 'connected' : 'disconnected';
    return 'CxpConnectionEvent($state, peer=$peer, error=$error)';
  }
}

/// A decoded message received on a [CxpClient] socket.
@immutable
class CxpClientInbound {
  /// Creates a record of a decoded inbound message.
  const CxpClientInbound({required this.envelope, required this.message});

  /// The decoded envelope as received.
  final CxpEnvelope envelope;

  /// The concrete decoded message body.
  final CxpMessage message;
}

/// Abstract CXP client — connects to one peer at a time.
abstract class CxpClient {
  /// Connect to a peer at [host]:[port] and perform the Hello handshake.
  ///
  /// [token] is the peer's authentication token as read from its manifest
  /// (`CxpPeerManifest.token`); it is carried in the Hello. A peer that
  /// requires one and is not given it rejects the handshake with
  /// `unauthorized`. Null presents none.
  ///
  /// Completes once the [HelloAck] is received. Throws on socket failure
  /// or handshake rejection.
  Future<void> connect({
    required String host,
    required int port,
    String? token,
  });

  /// Disconnect from the peer, sending [Goodbye] if connected.
  Future<void> disconnect();

  /// Send a [message] to the connected peer. No-op when disconnected.
  void send(CxpMessage message);

  /// Stream of inbound messages from the connected peer.
  Stream<CxpClientInbound> get inbound;

  /// Stream of connection lifecycle events.
  Stream<CxpConnectionEvent> get events;

  /// True iff currently connected and handshake has completed.
  bool get isConnected;

  /// The local peer identity configured at construction.
  PeerIdentity get selfIdentity;

  /// The remote peer's identity after a successful handshake, or null
  /// when not yet connected.
  PeerIdentity? get remotePeer;
}

/// Concrete TCP/JSON client matching `LocalCxpServer`'s wire format.
class LocalCxpClient implements CxpClient {
  /// Creates a local client.
  LocalCxpClient({
    required this.selfIdentity,
    this.connectTimeout = const Duration(seconds: 10),
    this.handshakeTimeout = const Duration(seconds: 10),
    this.maxLineLength = defaultCxpMaxLineLength,
    this.maxPendingWriteBytes = defaultCxpMaxPendingWriteBytes,
  });

  @override
  final PeerIdentity selfIdentity;

  /// Upper bound on establishing the TCP connection. [connect] throws a
  /// [SocketException] when it elapses.
  final Duration connectTimeout;

  /// Upper bound on the Hello→HelloAck exchange after the socket is up.
  /// [connect] throws a [TimeoutException] (and tears the socket down)
  /// when it elapses, so a peer that accepts but never answers cannot
  /// leave the client wedged in a half-open state.
  final Duration handshakeTimeout;

  /// Upper bound on one newline-delimited frame; the connection is
  /// dropped when exceeded. See [CappedLineSplitter].
  final int maxLineLength;

  /// Upper bound on un-flushed outbound bytes buffered for the peer. A
  /// peer that stops reading past this cap fails the connection rather
  /// than growing this process's heap. See
  /// [defaultCxpMaxPendingWriteBytes].
  final int maxPendingWriteBytes;

  Socket? _socket;
  var _pendingWriteBytes = 0;

  /// Serializes outbound writes so no two `write`/`flush`/`close` calls
  /// on the socket ever overlap. See [_writeEnvelope].
  Future<void> _writeChain = Future<void>.value();
  StreamSubscription<String>? _lineSub;
  PeerIdentity? _remotePeer;
  Completer<void>? _handshake;
  final StreamController<CxpClientInbound> _inbound =
      StreamController<CxpClientInbound>.broadcast();
  final StreamController<CxpConnectionEvent> _events =
      StreamController<CxpConnectionEvent>.broadcast();
  var _disposed = false;

  @override
  bool get isConnected => _socket != null && _remotePeer != null;

  @override
  PeerIdentity? get remotePeer => _remotePeer;

  @override
  Stream<CxpClientInbound> get inbound => _inbound.stream;

  @override
  Stream<CxpConnectionEvent> get events => _events.stream;

  @override
  Future<void> connect({
    required String host,
    required int port,
    String? token,
  }) async {
    if (_disposed) throw StateError('LocalCxpClient already disposed.');
    if (_socket != null) {
      throw StateError('LocalCxpClient is already connected.');
    }
    final socket = await Socket.connect(host, port, timeout: connectTimeout);
    _socket = socket;
    _pendingWriteBytes = 0;
    // Writes are asynchronous; a failed write to a dead peer arrives
    // here, not at the write call site. Without this the SocketException
    // escaped to Zone.handleUncaughtError and the client kept reporting
    // itself connected. Guarded on socket identity so a `done` from a
    // previous socket cannot tear down a newer connection.
    unawaited(
      socket.done.then<void>(
        (_) {
          if (identical(_socket, socket)) _handleDisconnect();
        },
        onError: (Object e) {
          if (identical(_socket, socket)) _failHandshake(e);
        },
      ),
    );
    final handshake = Completer<void>();
    _handshake = handshake;
    _lineSub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(CappedLineSplitter(maxLineLength: maxLineLength))
        .listen(
          _onLine,
          onError: _failHandshake,
          onDone: _handleDisconnect,
          cancelOnError: false,
        );

    final hello = Hello(identity: selfIdentity, token: token);
    _writeEnvelope(
      CxpEnvelope(
        messageId: _newMessageId(),
        from: selfIdentity.peerId,
        kind: hello.kind,
        payload: hello.toJson(),
      ),
    );

    try {
      await handshake.future.timeout(handshakeTimeout);
    } on TimeoutException catch (e) {
      // The peer accepted the socket but never completed the handshake.
      // Tear down so a later connect() starts from a clean state.
      _failHandshake(e);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      const bye = Goodbye(reason: 'client_disconnect');
      _writeEnvelope(
        CxpEnvelope(
          messageId: _newMessageId(),
          from: selfIdentity.peerId,
          kind: bye.kind,
          payload: bye.toJson(),
        ),
      );
    } on Object {
      // Best effort.
    }
    await _lineSub?.cancel();
    _lineSub = null;
    // Drain the serialized write chain so the Goodbye actually reaches
    // the peer, and so `close()` is not called while a flush holds the
    // sink bound (which would throw StateError and leak the socket).
    try {
      await _writeChain;
    } on Object {
      // Write failures are handled inside the chain.
    }
    try {
      await socket.close();
    } on Object {
      // Already closed.
    }
    _socket = null;
    final remote = _remotePeer;
    _remotePeer = null;
    if (!_events.isClosed) {
      _events.add(CxpConnectionEvent(connected: false, peer: remote));
    }
  }

  @override
  void send(CxpMessage message) {
    if (!isConnected) return;
    _writeEnvelope(
      CxpEnvelope(
        messageId: _newMessageId(),
        from: selfIdentity.peerId,
        kind: message.kind,
        payload: message.toJson(),
      ),
    );
  }

  /// Release the streams owned by this client. After [dispose] further
  /// calls to [connect] throw.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _inbound.close();
    await _events.close();
  }

  /// Fire-and-forget write with outbound backpressure accounting.
  ///
  /// `socket.write` is an `IOSink` write: it never throws synchronously,
  /// so the try/catch that used to wrap it was dead code — a write to a
  /// dead peer surfaces on `socket.done` (wired in [connect]) or on the
  /// flush below, not at the call site. A frame stays counted from queue
  /// to flush, and a peer that lets the backlog exceed
  /// [maxPendingWriteBytes] fails the connection instead of growing this
  /// process's heap without bound.
  ///
  /// Writes are serialized through [_writeChain]: `IOSink.flush` marks the
  /// sink bound for its duration, so an overlapping `write` or `close`
  /// throws `StateError`.
  void _writeEnvelope(CxpEnvelope envelope) {
    final socket = _socket;
    if (socket == null) return;
    final line = envelope.encodeLine();
    final bytes = line.length;
    if (_pendingWriteBytes + bytes > maxPendingWriteBytes) {
      _failHandshake(
        const SocketException(
          'Outbound CXP write buffer exceeded maxPendingWriteBytes; the '
          'peer is not reading.',
        ),
      );
      return;
    }
    _pendingWriteBytes += bytes;
    _writeChain = _writeChain
        .then((_) async {
          // Once this socket is no longer the live one, everything still
          // queued behind it is dropped: writing to a dead socket trips a
          // dart:io assertion rather than failing gracefully.
          if (!identical(_socket, socket)) return;
          try {
            socket.write(line);
            await socket.flush();
          } on Object catch (e) {
            if (identical(_socket, socket)) _failHandshake(e);
          }
        })
        .whenComplete(() => _pendingWriteBytes -= bytes);
  }

  void _onLine(String line) {
    if (line.isEmpty) return;
    CxpEnvelope envelope;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?>) {
        envelope = CxpEnvelope.fromJson(decoded);
      } else if (decoded is Map) {
        envelope = CxpEnvelope.fromJson(decoded.cast<String, Object?>());
      } else {
        _failHandshake(
          const FormatException('Peer sent a frame that is not a JSON object.'),
        );
        return;
      }
    } on FormatException catch (e) {
      // A frame that is not an envelope ends the connection, as it does on
      // the server (see `_PeerConnection._rejectFrame`). The client used to
      // drop such a frame and read on; the peer on the other end of an
      // outbound link is whatever answered the port a manifest named, and a
      // link stays a full-duplex channel into this process's dispatch
      // stream, so the same containment applies to what comes back.
      _failHandshake(
        FormatException(
          'Peer sent a frame that is not an envelope: '
          '${e.message}',
        ),
      );
      return;
    }
    if (!isCompatibleCxpVersion(envelope.cxpVersion)) {
      // Major-version mismatch: fatal during the handshake; dropped
      // afterwards (the peer already passed a compatible handshake, so a
      // stray incompatible frame is the anomaly, not the connection).
      final handshake = _handshake;
      if (handshake != null && !handshake.isCompleted) {
        _failHandshake(
          CxpHandshakeException(
            code: CxpErrorCode.unsupportedVersion,
            message: 'Peer speaks cxp_version "${envelope.cxpVersion}".',
          ),
        );
      }
      return;
    }

    final CxpMessage? body;
    try {
      body = decodeCxpMessage(envelope.kind, envelope.payload);
    } on FormatException catch (e) {
      if (envelope.kind == CxpMessageKind.errorResponse) {
        // §9.8: an error_response is never answered with one, or two peers
        // could answer each other forever. One that does not decode is
        // still a refusal when it arrives in place of the HelloAck (§7.4),
        // and is otherwise dropped.
        _failPendingHandshake(envelope.payload, e.message);
        return;
      }
      // Known kind, undecodable payload — report to the peer instead of
      // letting the exception escape the read loop.
      _sendError(
        code: CxpErrorCode.malformedPayload,
        message: e.message,
        inReplyTo: envelope.messageId,
      );
      return;
    }
    if (body == null) {
      // §6.1: an unrecognised kind is answered, and the connection served
      // on, in the dialling role as in the listening one. Dropping it
      // silently left the sender unable to tell "not understood" from
      // "not delivered".
      _sendError(
        code: CxpErrorCode.unknownKind,
        message: 'Unknown message kind "${envelope.kind}".',
        inReplyTo: envelope.messageId,
      );
      return;
    }

    if (body is ErrorResponse) {
      // A rejection during the handshake (unsupported version, malformed
      // Hello) must fail connect() — otherwise the completer never
      // completes and the caller's connection attempt wedges.
      final handshake = _handshake;
      if (handshake != null && !handshake.isCompleted) {
        _failHandshake(
          CxpHandshakeException(code: body.code, message: body.message),
        );
        return;
      }
    }

    if (body is HelloAck) {
      _remotePeer = body.identity;
      if (!_events.isClosed) {
        _events.add(
          CxpConnectionEvent(connected: true, peer: body.identity),
        );
      }
      final handshake = _handshake;
      if (handshake != null && !handshake.isCompleted) {
        handshake.complete();
      }
      return;
    }

    if (!_inbound.isClosed) {
      _inbound.add(CxpClientInbound(envelope: envelope, message: body));
    }
  }

  /// Answers the peer with an [ErrorResponse] correlated to [inReplyTo].
  void _sendError({
    required String code,
    required String message,
    required String inReplyTo,
  }) {
    _writeEnvelope(
      CxpEnvelope(
        messageId: _newMessageId(),
        from: selfIdentity.peerId,
        kind: CxpMessageKind.errorResponse,
        payload: ErrorResponse(
          code: code,
          message: message,
          inReplyTo: inReplyTo,
        ).toJson(),
      ),
    );
  }

  /// Fails a handshake still waiting for its HelloAck because the peer
  /// sent an error_response whose [payload] does not decode — keeping its
  /// `code` and `message` where they are strings, and reading a missing
  /// code as `internal_error` (§6.1). No-op once the handshake is done.
  void _failPendingHandshake(Map<String, Object?> payload, String detail) {
    final handshake = _handshake;
    if (handshake == null || handshake.isCompleted) return;
    final code = payload['code'];
    final message = payload['message'];
    _failHandshake(
      CxpHandshakeException(
        code: code is String ? code : CxpErrorCode.internalError,
        message: message is String
            ? message
            : 'The peer answered the hello with an error_response that '
                  'does not decode: $detail',
      ),
    );
  }

  void _failHandshake(Object error) {
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(error);
    }
    // Release the read loop and the socket: leaving them behind wedges a
    // later connect() ("already connected") and leaks the file
    // descriptor.
    final sub = _lineSub;
    _lineSub = null;
    if (sub != null) unawaited(sub.cancel());
    _socket?.destroy();
    _socket = null;
    _remotePeer = null;
    if (!_events.isClosed) {
      _events.add(CxpConnectionEvent(connected: false, error: error));
    }
  }

  void _handleDisconnect() {
    if (_socket == null) return;
    final remote = _remotePeer;
    final sub = _lineSub;
    _lineSub = null;
    if (sub != null) unawaited(sub.cancel());
    _socket?.destroy();
    _socket = null;
    _remotePeer = null;
    if (!_events.isClosed) {
      _events.add(CxpConnectionEvent(connected: false, peer: remote));
    }
    final handshake = _handshake;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(
        StateError('Peer closed connection before HelloAck.'),
      );
    }
  }
}

int _clientMessageCounter = 0;

String _newMessageId() {
  _clientMessageCounter++;
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return 'c-$stamp-$_clientMessageCounter';
}
