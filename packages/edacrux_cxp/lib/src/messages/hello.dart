// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:edacrux_cxp/src/messages/cxp_message.dart';
import 'package:edacrux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Initial handshake message a peer sends after the TCP connection is open.
///
/// The recipient validates the [identity] and the protocol version (from
/// the enclosing envelope's `cxp_version` field), then replies with a
/// [HelloAck] carrying its own identity. A peer that receives an
/// incompatible `cxp_version` (major-version mismatch - see
/// `isCompatibleCxpVersion`) MUST respond with an `ErrorResponse` (code
/// `unsupported_version`) and close the connection; minor-version
/// differences are accepted.
///
/// Since wire 1.2 the payload MAY carry the [token] the recipient
/// published in its manifest; a recipient that requires one answers a
/// Hello without it with `unauthorized` and closes. See
/// `cxpProcessAuthToken` for what the token is and is not.
///
/// Since wire 1.3 a dialler MAY instead present a [nonce] and a [proof]
/// that it holds the token, without sending it (see `cxpAuthProof`), and
/// the recipient then proves in its [HelloAck] that it holds the token too.
/// A dialler presents one or the other, never both.
@immutable
class Hello extends CxpMessage {
  /// Creates a Hello message.
  const Hello({required this.identity, this.token, this.nonce, this.proof});

  /// Decodes a [Hello] from its JSON payload.
  ///
  /// A `token`, `nonce` or `proof` that is absent or not a non-empty string
  /// reads as absent. A nonce without a proof, or a proof without a nonce,
  /// is no proof at all and both read as absent: a receiver never has to
  /// reason about half a credential.
  factory Hello.fromJson(Map<String, Object?> json) {
    final id = json['identity'];
    final token = _nonEmptyString(json['token']);
    var nonce = _nonEmptyString(json['nonce']);
    var proof = _nonEmptyString(json['proof']);
    if (nonce == null || proof == null) {
      nonce = null;
      proof = null;
    }
    if (id is! Map<String, Object?>) {
      if (id is Map) {
        return Hello(
          identity: PeerIdentity.fromJson(id.cast()),
          token: token,
          nonce: nonce,
          proof: proof,
        );
      }
      throw const FormatException('Hello.fromJson: missing "identity"');
    }
    return Hello(
      identity: PeerIdentity.fromJson(id),
      token: token,
      nonce: nonce,
      proof: proof,
    );
  }

  /// The connecting peer's identity.
  final PeerIdentity identity;

  /// The recipient's authentication token, as read from the recipient's
  /// manifest (`CxpPeerManifest.token`); null when the dialler has none to
  /// present, or presents a [proof] instead. Additive in wire minor 1.2.
  final String? token;

  /// The dialler's fresh nonce for this handshake, paired with [proof].
  /// Additive in wire minor 1.3.
  final String? nonce;

  /// `cxpAuthProof(token, nonce, cxpHelloProofLabel)`: the dialler's proof
  /// that it holds the recipient's token, sent in place of the token.
  /// Additive in wire minor 1.3.
  final String? proof;

  @override
  String get kind => CxpMessageKind.hello;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'token': ?token,
    'nonce': ?nonce,
    'proof': ?proof,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Hello &&
          other.identity == identity &&
          other.token == token &&
          other.nonce == nonce &&
          other.proof == proof);

  @override
  int get hashCode => Object.hash(identity, token, nonce, proof);

  /// Deliberately omits [token], [nonce] and [proof]: this string reaches
  /// logs and event rows, and a credential belongs in none of them.
  @override
  String toString() => 'Hello(${identity.peerId})';
}

/// Reply to a [Hello] - the receiver echoes its own identity.
///
/// Since wire 1.3 the reply to a [Hello] that presented a proof carries the
/// receiver's own [proof] that it holds the token its manifest publishes;
/// the dialler verifies it before treating the handshake as complete.
@immutable
class HelloAck extends CxpMessage {
  /// Creates a HelloAck message.
  const HelloAck({
    required this.identity,
    required this.inReplyTo,
    this.proof,
  });

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
      proof: _nonEmptyString(json['proof']),
    );
  }

  /// The replying peer's identity.
  final PeerIdentity identity;

  /// The [CxpEnvelope.messageId] of the [Hello] this acknowledges.
  final String inReplyTo;

  /// `cxpAuthProof(token, hello.nonce, cxpHelloAckProofLabel)`: the
  /// receiver's proof that it holds the token its manifest publishes. Set
  /// only in reply to a [Hello] whose own proof verified; absent otherwise.
  /// Additive in wire minor 1.3.
  final String? proof;

  @override
  String get kind => CxpMessageKind.helloAck;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'identity': identity.toJson(),
    'in_reply_to': inReplyTo,
    'proof': ?proof,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HelloAck &&
          other.identity == identity &&
          other.inReplyTo == inReplyTo &&
          other.proof == proof);

  @override
  int get hashCode => Object.hash(identity, inReplyTo, proof);

  /// Deliberately omits [proof]: this string reaches logs and event rows.
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

String? _nonEmptyString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
