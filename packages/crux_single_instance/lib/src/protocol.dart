// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The greeting a launching process opens with, and the version of the
/// exchange below.
const String kSingleInstanceProtocol = 'crux-single-instance/1';

/// The running instance's answer when it took the link.
const String kSingleInstanceAccepted = 'ok';

/// The running instance's answer to anything else.
const String kSingleInstanceRefused = 'refused';

/// The longest handshake line, in bytes, before the newline. Only the line
/// carrying the link may be longer, by the policy's bound.
const int kSingleInstanceMaxHandshakeLine = 160;

/// A fresh 128-bit value from `Random.secure()`, as 32 lowercase hex digits.
/// Used for the token and for both nonces.
String generateSingleInstanceSecret() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

final RegExp _secretPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _proofPattern = RegExp(r'^[0-9a-f]{64}$');

/// Whether [value] has the shape [generateSingleInstanceSecret] produces.
bool isSingleInstanceSecret(String value) => _secretPattern.hasMatch(value);

/// Whether [value] has the shape of a proof.
bool isSingleInstanceProof(String value) => _proofPattern.hasMatch(value);

/// The running instance's proof that it holds [token]:
/// `HMAC-SHA256(token, "server:" + clientNonce + ":" + serverNonce)`.
String singleInstanceServerProof({
  required String token,
  required String clientNonce,
  required String serverNonce,
}) => _hmac(token, 'server:$clientNonce:$serverNonce');

/// The launching process's proof that it holds [token], bound to the [link]
/// it delivers:
/// `HMAC-SHA256(token, "client:" + clientNonce + ":" + serverNonce + ":" +
/// link)`.
String singleInstanceClientProof({
  required String token,
  required String clientNonce,
  required String serverNonce,
  required String link,
}) => _hmac(token, 'client:$clientNonce:$serverNonce:$link');

String _hmac(String key, String message) =>
    Hmac(sha256, utf8.encode(key)).convert(utf8.encode(message)).toString();

/// Whether [a] equals [b], compared in time that does not depend on where the
/// two first differ.
bool singleInstanceConstantTimeEquals(String a, String b) {
  final x = a.codeUnits;
  final y = b.codeUnits;
  var difference = x.length ^ y.length;
  final overlap = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < overlap; i++) {
    difference |= x[i] ^ y[i];
  }
  return difference == 0;
}

/// Thrown by [BoundedLineReader] when a line is longer than allowed, is not
/// UTF-8, or the stream ends first.
class SingleInstanceProtocolException implements Exception {
  /// Creates an exception with [message].
  const SingleInstanceProtocolException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'SingleInstanceProtocolException: $message';
}

/// Reads newline-terminated UTF-8 lines from a byte stream, refusing any line
/// longer than the bound given for it. Nothing is buffered beyond
/// [maxBuffered] bytes, so a peer that never sends a newline costs a fixed
/// amount of memory.
class BoundedLineReader {
  /// Reads from [bytes], holding at most [maxBuffered] unread bytes.
  BoundedLineReader(Stream<Uint8List> bytes, {required this.maxBuffered}) {
    _subscription = bytes.listen(
      _onData,
      onError: (Object e) => _fail(SingleInstanceProtocolException('$e')),
      onDone: () => _fail(
        const SingleInstanceProtocolException('connection closed'),
      ),
      cancelOnError: true,
    );
  }

  /// The most unread bytes held before the peer is refused.
  final int maxBuffered;

  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _pending = <int>[];
  Completer<String>? _waiting;
  int _limit = 0;
  SingleInstanceProtocolException? _error;

  /// The next line, without its newline, at most [maxBytes] long.
  Future<String> next(int maxBytes) {
    if (_waiting != null) throw StateError('a read is already pending');
    final error = _error;
    if (error != null) return Future.error(error);
    final completer = _waiting = Completer<String>();
    _limit = maxBytes;
    _drain();
    return completer.future;
  }

  /// Stops reading.
  Future<void> cancel() => _subscription.cancel();

  void _onData(Uint8List chunk) {
    _pending.addAll(chunk);
    _drain();
  }

  void _drain() {
    final waiting = _waiting;
    if (waiting == null) {
      // Nobody is reading yet: hold what came, up to the bound.
      if (_pending.length > maxBuffered) {
        _fail(const SingleInstanceProtocolException('too much data'));
      }
      return;
    }
    final newline = _pending.indexOf(0x0A);
    if (newline < 0) {
      if (_pending.length > _limit) {
        _fail(const SingleInstanceProtocolException('line too long'));
      }
      return;
    }
    if (newline > _limit) {
      _fail(const SingleInstanceProtocolException('line too long'));
      return;
    }
    final line = _pending.sublist(0, newline);
    _pending.removeRange(0, newline + 1);
    _waiting = null;
    try {
      waiting.complete(utf8.decode(line));
    } on FormatException {
      _error = const SingleInstanceProtocolException('not UTF-8');
      waiting.completeError(_error!);
    }
  }

  void _fail(SingleInstanceProtocolException error) {
    _error ??= error;
    _pending.clear();
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
    unawaited(_subscription.cancel());
  }
}
