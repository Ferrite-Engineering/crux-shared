// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:edacrux_cxp/src/cxp_time.dart';
import 'package:edacrux_cxp/src/element_id.dart';
import 'package:edacrux_cxp/src/messages/cxp_message.dart';
import 'package:edacrux_cxp/src/stream_coordinate.dart';
import 'package:meta/meta.dart';

/// Peer asks another to focus on a specific element.
///
/// Distinct from `NotifySelection` in directionality: NotifySelection is a
/// broadcast emitted by the holder of the selection; RequestHighlight is
/// an imperative directed at one peer ("please show me this"). The target
/// peer SHOULD jump its cursor / viewport / selection to the requested
/// element and reply with [RequestHighlightAck].
@immutable
class RequestHighlight extends CxpMessage {
  /// Creates a RequestHighlight.
  const RequestHighlight({
    required this.element,
    this.coordinate,
    this.time,
    this.metadata = const <String, Object?>{},
  });

  /// Decodes a [RequestHighlight] from its JSON payload.
  ///
  /// Throws a [FormatException] (answered `malformed_payload`) when `time` is
  /// present and not a time in the grammar of CXP §9.3.3.
  factory RequestHighlight.fromJson(Map<String, Object?> json) {
    final raw = json['element'];
    final ElementId element;
    if (raw is Map<String, Object?>) {
      element = ElementId.fromJson(raw);
    } else if (raw is Map) {
      element = ElementId.fromJson(raw.cast<String, Object?>());
    } else {
      throw const FormatException(
        'RequestHighlight.fromJson: missing "element"',
      );
    }
    final rawMeta = json['metadata'];
    var metadata = const <String, Object?>{};
    if (rawMeta is Map<String, Object?>) {
      metadata = rawMeta;
    } else if (rawMeta is Map) {
      metadata = rawMeta.cast<String, Object?>();
    }
    return RequestHighlight(
      element: element,
      coordinate: CxpStreamCoordinate.tryFromJson(json['coordinate']),
      time: CxpTime.fromJson(json['time']),
      metadata: metadata,
    );
  }

  /// The element the requester wants the target to focus on.
  final ElementId element;

  /// Optional semantic stream coordinate (CXP §9.9) saying *where within*
  /// [element] to land - which retirement, transaction or frame.
  ///
  /// [element] says what to open; this says where to land inside it. A
  /// receiver that honours the element but cannot resolve the coordinate
  /// MUST still honour the element and SHOULD say so in its ack's `reason`:
  /// landing at the top of the right artifact beats refusing it.
  final CxpStreamCoordinate? coordinate;

  /// Optional point in simulation time (CXP §9.3.3): for a signal-like
  /// [element] (`signal`, `net`, `port`, `instance`), asks the receiver to
  /// put its time cursor there and scroll it into view.
  ///
  /// A receiver that cannot place it (no time axis, no timescale for a time
  /// with a unit) still honours the element and SHOULD say so in its ack's
  /// `reason`. When the message also carries a [coordinate] the coordinate
  /// wins the cursor; when it also carries the `crux.time_ps` metadata key,
  /// a receiver that reads this field uses it and ignores the key.
  final CxpTime? time;

  /// Product-local metadata blob. Recipients MUST ignore unknown keys.
  /// Conventionally namespaced; the reserved [cxpDesignIdMetadataKey]
  /// (`crux.design_id`) carries the shared-design identifier so a receiver
  /// that cannot resolve the element locally can open the right artifact via
  /// its workspace manifest. Additive in wire minor 1.1.
  final Map<String, Object?> metadata;

  @override
  String get kind => CxpMessageKind.requestHighlight;

  @override
  List<ElementId> get referencedElements => <ElementId>[element];

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'element': element.toJson(),
    'coordinate': ?coordinate?.toJson(),
    'time': ?time?.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestHighlight &&
          other.element == element &&
          other.coordinate == coordinate &&
          other.time == time &&
          _metaEquals(other.metadata, metadata));

  @override
  int get hashCode => Object.hash(element, coordinate, time, metadata.length);

  @override
  String toString() =>
      'RequestHighlight($element'
      '${coordinate == null ? '' : ', at=$coordinate'}'
      '${time == null ? '' : ', time=${time!.toJson()}'}'
      '${metadata.isEmpty ? '' : ', meta=$metadata'})';
}

bool _metaEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Acknowledgment of a [RequestHighlight].
///
/// The target peer replies with this message after it has either honoured
/// the request ([honored] = true) or determined it cannot ([honored] =
/// false). When `honored` is false the [reason] field SHOULD describe
/// the failure (e.g. "element not found", "no compatible viewer open").
@immutable
class RequestHighlightAck extends CxpMessage {
  /// Creates a RequestHighlightAck.
  const RequestHighlightAck({
    required this.inReplyTo,
    required this.honored,
    this.reason,
  });

  /// Decodes a [RequestHighlightAck] from its JSON payload.
  factory RequestHighlightAck.fromJson(Map<String, Object?> json) {
    final inReplyTo = json['in_reply_to'];
    final honored = json['honored'];
    if (inReplyTo is! String) {
      throw const FormatException(
        'RequestHighlightAck.fromJson: missing "in_reply_to"',
      );
    }
    if (honored is! bool) {
      throw const FormatException(
        'RequestHighlightAck.fromJson: missing "honored"',
      );
    }
    final reason = json['reason'];
    return RequestHighlightAck(
      inReplyTo: inReplyTo,
      honored: honored,
      reason: reason is String ? reason : null,
    );
  }

  /// The [CxpEnvelope.messageId] of the request this acknowledges.
  final String inReplyTo;

  /// Whether the request was honoured by the recipient.
  final bool honored;

  /// Optional human-readable reason - typically set when [honored] is
  /// false.
  final String? reason;

  @override
  String get kind => CxpMessageKind.requestHighlightAck;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'in_reply_to': inReplyTo,
    'honored': honored,
    'reason': ?reason,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RequestHighlightAck &&
          other.inReplyTo == inReplyTo &&
          other.honored == honored &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(inReplyTo, honored, reason);

  @override
  String toString() =>
      'RequestHighlightAck(replyTo=$inReplyTo, honored=$honored, '
      'reason=$reason)';
}
