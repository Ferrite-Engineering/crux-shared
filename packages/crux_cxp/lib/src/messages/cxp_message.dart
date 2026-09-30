// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_cxp/src/element_id.dart';
import 'package:crux_cxp/src/peer_identity.dart';
import 'package:meta/meta.dart';

/// Protocol version this implementation speaks on the wire.
///
/// Peers exchange the [cxpProtocolVersion] in the Hello handshake and in
/// every envelope's `cxp_version` field. Compatibility policy:
///
/// - **Major mismatch** (or an unparseable version): the receiver sends
///   an `ErrorResponse` with code `unsupported_version` and closes the
///   connection. A client fails its pending handshake.
/// - **Minor mismatch**: accepted. Minor revisions are additive; unknown
///   payload fields are ignored (forward compatibility), so a 1.x peer
///   can always talk to a 1.y peer.
///
/// Use [isCompatibleCxpVersion] to apply the policy.
///
/// **1.1** (additive): adds the `request_open_artifact` /
/// `request_open_artifact_ack` message kinds and reserves the
/// `crux.design_id` metadata key. Both are additive — a 1.0 peer that
/// receives the new kind answers `unknown_kind` (no crash, connection stays
/// open) and ignores the unknown metadata key — so 1.0 and 1.1 peers
/// interoperate under the minor-compatibility rule.
///
/// **1.2** (additive on the wire, with one behavioural consequence): adds
/// an optional `token` to the peer manifest and to the `hello` payload, and
/// the `unauthorized` error code. A receiver MAY require the token it
/// published; the reference implementation does by default. The fields are
/// ignored by a 1.0/1.1 receiver, so a 1.2 dialler talks to an older peer
/// unchanged — but an older dialler, which sends no token, is refused by a
/// 1.2 receiver that requires one. That is the one place the minor rule
/// bends, and it bends on purpose: see `cxpProcessAuthToken` for what the
/// token closes, and `LocalCxpServer.requireAuthToken` to opt a receiver
/// out.
const String cxpProtocolVersion = '1.2';

/// True when [version]'s major component matches this implementation's
/// major version — the acceptance test of the version policy documented
/// on [cxpProtocolVersion].
///
/// A version with no `.` separator is compared whole, so `"1"` is
/// compatible with `"1.0"` and `"2"` is not.
bool isCompatibleCxpVersion(String version) {
  final major = version.split('.').first;
  final selfMajor = cxpProtocolVersion.split('.').first;
  return major == selfMajor;
}

/// String constants for CXP message kinds.
///
/// Using a class of constants (rather than an enum) keeps the wire format
/// open to product-defined extension kinds in the future without changing
/// an enum's exhaustive switch contract.
abstract final class CxpMessageKind {
  /// Initial handshake — peer announces itself.
  static const String hello = 'hello';

  /// Acknowledgment of a [hello].
  static const String helloAck = 'hello_ack';

  /// Peer announcing it is shutting down cleanly.
  static const String goodbye = 'goodbye';

  /// Subscribe to one or more message kinds with optional element filters.
  static const String subscribe = 'subscribe';

  /// Cancel a previous subscription.
  static const String unsubscribe = 'unsubscribe';

  /// Peer announces its current selection.
  static const String notifySelection = 'notify_selection';

  /// Peer asks another peer to focus on a specific element.
  static const String requestHighlight = 'request_highlight';

  /// Acknowledgment of a [requestHighlight].
  static const String requestHighlightAck = 'request_highlight_ack';

  /// Peer asks another peer to open a source-code location.
  static const String requestOpenSource = 'request_open_source';

  /// Acknowledgment of a [requestOpenSource].
  static const String requestOpenSourceAck = 'request_open_source_ack';

  /// Peer asks another peer to open a design artifact (by kind, resolved via
  /// the shared-workspace manifest). Additive in wire minor 1.1.
  static const String requestOpenArtifact = 'request_open_artifact';

  /// Acknowledgment of a [requestOpenArtifact].
  static const String requestOpenArtifactAck = 'request_open_artifact_ack';

  /// Error envelope returned in response to a malformed or unprocessable
  /// message.
  static const String errorResponse = 'error_response';
}

/// Reserved namespaced `metadata` key that carries the opaque shared-design
/// identifier across the wire.
///
/// Senders SHOULD attach it to [CxpMessageKind.notifySelection] and
/// [CxpMessageKind.requestHighlight] (both expose a `metadata` map) so a
/// receiver that cannot satisfy the reference locally can look the design up
/// in its shared-workspace manifest (`CxpWorkspaceStore`) and open the
/// artifact it consumes. The value is an opaque string the producer supplies;
/// the library never computes it. As ordinary metadata it is additive and
/// forward-compatible — a peer that does not understand the key ignores it
/// (CXP §6.1, the forward-compatibility rule:
/// <https://edacrux.app/cxp#sec-6-1>).
const String cxpDesignIdMetadataKey = 'crux.design_id';

/// Base type for every CXP wire message body.
///
/// A [CxpMessage] is the structured payload carried inside a [CxpEnvelope].
/// Concrete message subtypes (`Hello`, `NotifySelection`, …) supply the
/// payload's JSON shape and provide value semantics (==, hashCode).
@immutable
abstract class CxpMessage {
  /// Abstract base constructor.
  const CxpMessage();

  /// Wire-format `kind` discriminator (one of [CxpMessageKind]).
  String get kind;

  /// The [ElementId]s this message refers to, in payload order.
  ///
  /// Element-bearing messages (`NotifySelection`, `RequestHighlight`)
  /// override this; messages that carry no element references return the
  /// empty list. Subscription filters (`CxpSubscription.elementKinds` /
  /// `pathPrefix`) are evaluated against this list.
  List<ElementId> get referencedElements => const <ElementId>[];

  /// Encode the message payload as a JSON-compatible map.
  Map<String, Object?> toJson();
}

/// Wire envelope wrapping a [CxpMessage] with routing metadata.
///
/// Every message exchanged on a CXP socket carries an envelope so the
/// recipient knows the protocol version, message ID (for correlation in
/// acks and error responses), the kind discriminator, and the sender's
/// peer ID. Payloads with unknown [kind] are rejected with an
/// `ErrorResponse`; payloads with unknown extra fields are silently
/// accepted (forward compatibility).
@immutable
class CxpEnvelope {
  /// Creates an envelope.
  const CxpEnvelope({
    required this.messageId,
    required this.from,
    required this.kind,
    required this.payload,
    this.cxpVersion = cxpProtocolVersion,
  });

  /// Decode an envelope from its JSON form. Throws [FormatException] on
  /// missing required fields. Unknown extra fields are ignored.
  factory CxpEnvelope.fromJson(Map<String, Object?> json) {
    final cxpVersion = json['cxp_version'];
    final messageId = json['message_id'];
    final from = json['from'];
    final kind = json['kind'];
    final payload = json['payload'];
    if (cxpVersion is! String) {
      throw const FormatException(
        'CxpEnvelope.fromJson: missing "cxp_version"',
      );
    }
    if (messageId is! String) {
      throw const FormatException('CxpEnvelope.fromJson: missing "message_id"');
    }
    if (from is! String) {
      throw const FormatException('CxpEnvelope.fromJson: missing "from"');
    }
    if (kind is! String) {
      throw const FormatException('CxpEnvelope.fromJson: missing "kind"');
    }
    if (payload is! Map<String, Object?>) {
      // Coerce a Map<dynamic, dynamic> from json.decode into the strict shape.
      if (payload is Map) {
        return CxpEnvelope(
          cxpVersion: cxpVersion,
          messageId: messageId,
          from: from,
          kind: kind,
          payload: payload.cast<String, Object?>(),
        );
      }
      throw const FormatException('CxpEnvelope.fromJson: missing "payload"');
    }
    return CxpEnvelope(
      cxpVersion: cxpVersion,
      messageId: messageId,
      from: from,
      kind: kind,
      payload: payload,
    );
  }

  /// Protocol version the sender speaks (matches [cxpProtocolVersion] for
  /// v1.0 peers).
  final String cxpVersion;

  /// Monotonic identifier the sender assigned to this message.
  ///
  /// Used to correlate acknowledgments and error responses back to the
  /// request that produced them.
  final String messageId;

  /// Sender's peer ID (matches the [PeerIdentity.peerId] from Hello).
  final String from;

  /// Message kind discriminator (one of [CxpMessageKind]).
  final String kind;

  /// Structured payload — the JSON form of one of the [CxpMessage]
  /// subtypes.
  final Map<String, Object?> payload;

  /// Encode the envelope as JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'cxp_version': cxpVersion,
    'message_id': messageId,
    'from': from,
    'kind': kind,
    'payload': payload,
  };

  /// Encode the envelope as a single line of JSON terminated by `\n`.
  ///
  /// The line-delimited form is the v1 wire format on TCP sockets.
  String encodeLine() => '${jsonEncode(toJson())}\n';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpEnvelope &&
          other.cxpVersion == cxpVersion &&
          other.messageId == messageId &&
          other.from == from &&
          other.kind == kind &&
          _mapEquals(other.payload, payload));

  @override
  int get hashCode => Object.hash(
    cxpVersion,
    messageId,
    from,
    kind,
    _mapHash(payload),
  );

  @override
  String toString() =>
      'CxpEnvelope(messageId=$messageId, from=$from, kind=$kind)';
}

/// Convenience helpers used by the message implementations and tests.
List<ElementId> elementIdListFromJson(Object? raw) {
  if (raw is! List) return const <ElementId>[];
  final result = <ElementId>[];
  for (final entry in raw) {
    if (entry is Map<String, Object?>) {
      result.add(ElementId.fromJson(entry));
    } else if (entry is Map) {
      result.add(ElementId.fromJson(entry.cast<String, Object?>()));
    }
  }
  return result;
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    final av = entry.value;
    final bv = b[entry.key];
    if (av is Map<String, Object?> && bv is Map<String, Object?>) {
      if (!_mapEquals(av, bv)) return false;
    } else if (av is List && bv is List) {
      if (!_listEquals(av, bv)) return false;
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final av = a[i];
    final bv = b[i];
    if (av is Map<String, Object?> && bv is Map<String, Object?>) {
      if (!_mapEquals(av, bv)) return false;
    } else if (av is List && bv is List) {
      if (!_listEquals(av, bv)) return false;
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}

int _mapHash(Map<String, Object?> m) => Object.hashAllUnordered(
  m.entries.map((e) => Object.hash(e.key, e.value?.toString())),
);
