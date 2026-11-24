// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:edacrux_cxp/edacrux_cxp.dart';
import 'package:edacrux_cxp/src/messages/cxp_message.dart'
    show elementIdListFromJson;

/// The payload decoders of `request_highlight` and `notify_selection` as
/// they were in `edacrux_cxp` 0.1.0 (CXP 1.3 rev. 10), before the `time`
/// field: the bodies of `RequestHighlight.fromJson` and
/// `NotifySelection.fromJson` copied unchanged, returning records so they
/// cannot pick up the current classes' fields.
///
/// They stand in for a peer built before revision 11. Kept frozen on
/// purpose: a test that decodes a revision 11 payload with them shows what
/// such a peer does with a `time` it has never heard of.
({
  ElementId element,
  CxpStreamCoordinate? coordinate,
  Map<String, Object?> metadata,
})
rev10RequestHighlight(Map<String, Object?> json) {
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
  return (
    element: element,
    coordinate: CxpStreamCoordinate.tryFromJson(json['coordinate']),
    metadata: metadata,
  );
}

/// See [rev10RequestHighlight].
({
  List<ElementId> elements,
  String? displayName,
  CxpStreamCoordinate? coordinate,
  Map<String, Object?> metadata,
})
rev10NotifySelection(Map<String, Object?> json) {
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
  return (
    elements: elements,
    displayName: displayName is String ? displayName : null,
    coordinate: CxpStreamCoordinate.tryFromJson(json['coordinate']),
    metadata: metadata,
  );
}
