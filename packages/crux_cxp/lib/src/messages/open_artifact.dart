// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:meta/meta.dart';

/// Peer asks another to open a *design artifact* — a produced file (a
/// waveform, a netlist, a source) belonging to a shared design — by its
/// [artifactKind], resolving the concrete file through the shared-workspace
/// manifest keyed on [designId].
///
/// This is the companion to `RequestOpenSource` (CXP §9.10). Where
/// `request_open_source` names an exact file+line, `request_open_artifact`
/// names a *design* and the *kind* of artifact the sender wants opened, and
/// lets the receiver resolve the path from the workspace manifest it shares
/// with the producer (see `CxpWorkspaceStore`). The optional [path] is a hint
/// the sender MAY include when it already knows the concrete file (e.g. it
/// produced the artifact itself); a receiver SHOULD prefer its own
/// workspace-manifest resolution and treat [path] only as a fallback, since
/// the sender's path may not exist on the receiver's machine layout.
///
/// The recipient SHOULD open the resolved artifact in the appropriate viewer
/// and reply with [RequestOpenArtifactAck]. A receiver that cannot resolve or
/// open the artifact SHOULD ack with `honored: false` and a reason rather
/// than ignoring the request.
///
/// Note the two levels of "kind": the *envelope* discriminator ([kind]) is
/// always `request_open_artifact`, while the *payload* `kind` field
/// ([artifactKind]) names the artifact type.
@immutable
class RequestOpenArtifact extends CxpMessage {
  /// Creates a RequestOpenArtifact.
  const RequestOpenArtifact({
    required this.designId,
    required this.artifactKind,
    this.path,
  });

  /// Decodes a [RequestOpenArtifact] from its JSON payload.
  factory RequestOpenArtifact.fromJson(Map<String, Object?> json) {
    final designId = json['design_id'];
    final artifactKind = json['kind'];
    if (designId is! String) {
      throw const FormatException(
        'RequestOpenArtifact.fromJson: missing "design_id"',
      );
    }
    if (artifactKind is! String) {
      throw const FormatException(
        'RequestOpenArtifact.fromJson: missing "kind"',
      );
    }
    final path = json['path'];
    return RequestOpenArtifact(
      designId: designId,
      artifactKind: artifactKind,
      path: path is String ? path : null,
    );
  }

  /// Opaque design identifier, supplied by the producer and carried on the
  /// wire (also as `crux.design_id` metadata on selection/highlight). The
  /// library never computes it.
  final String designId;

  /// The artifact kind the sender wants opened — e.g. `waveform`, `netlist`,
  /// `source`. An open string set, matching `WorkspaceArtifact.kind`. Encoded
  /// as the payload's `kind` field (distinct from the envelope [kind]).
  final String artifactKind;

  /// Optional concrete-path hint. Receivers SHOULD prefer their own
  /// workspace-manifest resolution and use this only as a fallback.
  final String? path;

  @override
  String get kind => CxpMessageKind.requestOpenArtifact;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'design_id': designId,
    'kind': artifactKind,
    'path': ?path,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestOpenArtifact &&
          other.designId == designId &&
          other.artifactKind == artifactKind &&
          other.path == path);

  @override
  int get hashCode => Object.hash(designId, artifactKind, path);

  @override
  String toString() =>
      'RequestOpenArtifact(designId=$designId, kind=$artifactKind, '
      'path=$path)';
}

/// Acknowledgment of a [RequestOpenArtifact].
@immutable
class RequestOpenArtifactAck extends CxpMessage {
  /// Creates a RequestOpenArtifactAck.
  const RequestOpenArtifactAck({
    required this.inReplyTo,
    required this.honored,
    this.reason,
  });

  /// Decodes a [RequestOpenArtifactAck] from its JSON payload.
  factory RequestOpenArtifactAck.fromJson(Map<String, Object?> json) {
    final inReplyTo = json['in_reply_to'];
    final honored = json['honored'];
    if (inReplyTo is! String) {
      throw const FormatException(
        'RequestOpenArtifactAck.fromJson: missing "in_reply_to"',
      );
    }
    if (honored is! bool) {
      throw const FormatException(
        'RequestOpenArtifactAck.fromJson: missing "honored"',
      );
    }
    final reason = json['reason'];
    return RequestOpenArtifactAck(
      inReplyTo: inReplyTo,
      honored: honored,
      reason: reason is String ? reason : null,
    );
  }

  /// The [CxpEnvelope.messageId] of the request this acknowledges.
  final String inReplyTo;

  /// Whether the request was honoured.
  final bool honored;

  /// Optional human-readable reason — typically set when [honored] is false.
  final String? reason;

  @override
  String get kind => CxpMessageKind.requestOpenArtifactAck;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'in_reply_to': inReplyTo,
    'honored': honored,
    'reason': ?reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestOpenArtifactAck &&
          other.inReplyTo == inReplyTo &&
          other.honored == honored &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(inReplyTo, honored, reason);

  @override
  String toString() =>
      'RequestOpenArtifactAck(replyTo=$inReplyTo, honored=$honored, '
      'reason=$reason)';
}
