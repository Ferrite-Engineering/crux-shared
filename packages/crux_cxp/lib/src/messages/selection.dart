// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/src/element_id.dart';
import 'package:crux_cxp/src/messages/cxp_message.dart';
import 'package:crux_cxp/src/stream_coordinate.dart';
import 'package:meta/meta.dart';

/// Peer announces its current selection.
///
/// The most common cross-probe primitive. Subscribers respond by
/// highlighting the corresponding element in their own UI. The
/// [displayName] is a human-friendly label (e.g. signal name with bit
/// range) — recipients MAY use it as a tooltip or status-line message
/// when the local element cannot be resolved.
///
/// The [metadata] map carries product-local hints the sender wants to
/// share — recipients SHOULD ignore unknown keys. Keys are conventionally
/// namespaced (`wavecrux.cursor_time_fs`, `<product>.<field>`).
///
/// [elements] **may be empty**: per CXP §9.3 an empty array is the wire
/// representation of a *cleared* selection — the sender's user deselected
/// everything. The field is still required to be present and to be an
/// array; a missing or non-array `elements` is a malformed payload. What a
/// receiver *does* with a cleared selection (drop the highlight, leave the
/// last one pinned) is a per-product UX decision this package does not make.
@immutable
class NotifySelection extends CxpMessage {
  /// Creates a NotifySelection message.
  const NotifySelection({
    required this.elements,
    this.displayName,
    this.coordinate,
    this.metadata = const <String, Object?>{},
  });

  /// Decodes a [NotifySelection] from its JSON payload.
  factory NotifySelection.fromJson(Map<String, Object?> json) {
    // `elements` is required to be *present* and to be an array (CXP §9.3,
    // "Required: yes") but MAY be empty — an empty array signals a cleared
    // selection. Rejecting the empty case, as this decoder did before
    // 0.4.4, left "the user deselected everything" with no legal wire
    // representation and answered a conforming peer `malformed_payload`.
    final rawElements = json['elements'];
    if (rawElements is! List) {
      throw const FormatException(
        'NotifySelection.fromJson: missing or non-array "elements"',
      );
    }
    final elements = elementIdListFromJson(rawElements);
    final displayName = json['display_name'];
    final rawMeta = json['metadata'];
    var metadata = const <String, Object?>{};
    if (rawMeta is Map<String, Object?>) {
      metadata = rawMeta;
    } else if (rawMeta is Map) {
      metadata = rawMeta.cast<String, Object?>();
    }
    return NotifySelection(
      elements: elements,
      displayName: displayName is String ? displayName : null,
      coordinate: CxpStreamCoordinate.tryFromJson(json['coordinate']),
      metadata: metadata,
    );
  }

  /// The selected element(s), in the sender's own order. A single-selection
  /// peer emits a list of length 1; multi-selection peers emit longer lists;
  /// an **empty** list means the selection was cleared (CXP §9.3).
  final List<ElementId> elements;

  /// Optional human-friendly label for the selection.
  final String? displayName;

  /// Optional semantic stream coordinate (CXP §9.9) locating one element of
  /// a decoded stream — *which* retirement, transaction or frame the
  /// selection is, not merely which signal. Null when the sender either does
  /// not deal in streams or cannot state the index honestly; see
  /// [CxpStreamCoordinate].
  final CxpStreamCoordinate? coordinate;

  /// Product-local metadata blob. Recipients MUST ignore unknown keys.
  final Map<String, Object?> metadata;

  @override
  String get kind => CxpMessageKind.notifySelection;

  @override
  List<ElementId> get referencedElements => elements;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'elements': elements.map((e) => e.toJson()).toList(growable: false),
    'display_name': ?displayName,
    'coordinate': ?coordinate?.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotifySelection &&
          _listEq(other.elements, elements) &&
          other.displayName == displayName &&
          other.coordinate == coordinate);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(elements), displayName, coordinate);

  @override
  String toString() =>
      'NotifySelection($elements, displayName=$displayName'
      '${coordinate == null ? '' : ', at=$coordinate'})';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
