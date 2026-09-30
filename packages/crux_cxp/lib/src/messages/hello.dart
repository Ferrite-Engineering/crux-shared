// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Initial handshake message a peer sends after the TCP connection is open.
///
/// The recipient validates the [identity] and the protocol version (from
/// the enclosing envelope's `cxp_version` field), then replies with a
/// [HelloAck] carrying its own identity. A peer that receives an
/// incompatible `cxp_version` (major-version mismatch — see
/// `isCompatibleCxpVersion`) MUST respond with an `ErrorResponse` (code
/// `unsupported_version`) and close the connection; minor-version
/// differences are accepted.
///
/// Since wire 1.2 the payload MAY carry the [token] the recipient
/// published in its manifest; a recipient that requires one answers a
/// Hello without it with `unauthorized` and closes. See
/// `cxpProcessAuthToken` for what the token is and is not.
@immutable
class Hello extends CxpMessage {
  /// Creates a Hello message.
  const Hello({required this.identity, this.token});

  /// Decodes a [Hello] from its JSON payload.
  factory Hello.fromJson(Map<String, Object?> json) {
    final id = json['identity'];
    final token = json['token'];
    final tokenOrNull = token is String && token.isNotEmpty ? token : null;
    if (id is! Map<String, Object?>) {
      if (id is Map) {
        return Hello(
          identity: PeerIdentity.fromJson(id.cast()),
          token: tokenOrNull,
        );
      }
      throw const FormatException('Hello.fromJson: missing "identity"');
    }
    return Hello(identity: PeerIdentity.fromJson(id), token: tokenOrNull);
  }

  /// The connecting peer's identity.
  final PeerIdentity identity;

  /// The recipient's authentication token, as read from the recipient's
  /// manifest (`CxpPeerManifest.token`); null when the dialler has none to
  /// present. Additive in wire minor 1.2.
  final String? token;

  @override
  String get kind => CxpMessageKind.hello;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'token': ?token,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Hello && other.identity == identity && other.token == token);

  @override
  int get hashCode => Object.hash(identity, token);

  /// Deliberately omits [token]: this string reaches logs and event rows.
  @override
  String toString() => 'Hello(${identity.peerId})';
}

/// Reply to a [Hello] — the receiver echoes its own identity.
@immutable
class HelloAck extends CxpMessage {
  /// Creates a HelloAck message.
  const HelloAck({required this.identity, required this.inReplyTo});

  /// Decodes a [HelloAck] from its JSON payload.
  factory HelloAck.fromJson(Map<String, Object?> json) {
    final id = json['identity'];
    final replyTo = json['in_reply_to'];
    if (id is! Map<String, Object?> && id is! Map) {
      throw const FormatException('HelloAck.fromJson: missing "identity"');
    }
    if (replyTo is! String) {
      throw const FormatException('HelloAck.fromJson: missing "in_reply_to"');
    }
    final identityMap = id is Map<String, Object?>
        ? id
        : (id! as Map).cast<String, Object?>();
    return HelloAck(
      identity: PeerIdentity.fromJson(identityMap),
      inReplyTo: replyTo,
    );
  }

  /// The replying peer's identity.
  final PeerIdentity identity;

  /// The [CxpEnvelope.messageId] of the [Hello] this acknowledges.
  final String inReplyTo;

  @override
  String get kind => CxpMessageKind.helloAck;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'in_reply_to': inReplyTo,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HelloAck &&
          other.identity == identity &&
          other.inReplyTo == inReplyTo);

  @override
  int get hashCode => Object.hash(identity, inReplyTo);

  @override
  String toString() => 'HelloAck(${identity.peerId}, replyTo=$inReplyTo)';
}

/// Peer announces it is shutting down cleanly.
///
/// The recipient SHOULD remove the sender from its peer list immediately
/// rather than waiting for socket closure to detect the disconnection.
@immutable
class Goodbye extends CxpMessage {
  /// Creates a Goodbye message with the optional [reason].
  const Goodbye({this.reason});

  /// Decodes a [Goodbye] from its JSON payload.
  factory Goodbye.fromJson(Map<String, Object?> json) {
    final reason = json['reason'];
    return Goodbye(reason: reason is String ? reason : null);
  }

  /// Optional human-readable reason for the shutdown.
  final String? reason;

  @override
  String get kind => CxpMessageKind.goodbye;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'reason': ?reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Goodbye && other.reason == reason);

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Goodbye(${reason ?? ''})';
}
