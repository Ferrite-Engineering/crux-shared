// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Where a callout's label sits relative to its anchor, and whether it is
/// folded to a numbered dot.
///
/// ### Two coordinate spaces, deliberately separate
///
/// The anchor is data coordinates and survives pan, zoom and reordering. The
/// label offset is **logical pixels from the anchor's projected point**, so
/// the label stays beside what it describes at any zoom without ever being
/// expressed in data space. Dragging a label changes this; only an explicit
/// re-anchor changes the anchor. Conflating the two is the classic failure of
/// annotation systems: the label either drifts away from what it describes, or
/// cannot be moved out of the way.
///
/// ### Persistence shape
///
/// Three record keys beside the product's own: [labelDxKey] and [labelDyKey]
/// (each omitted at its default) and [collapsedKey] (omitted when false). The
/// shape is the one WaveCrux's documents already carry, so a record written by
/// either product reads in the other's codec.
@immutable
final class CruxCalloutPlacement {
  /// Creates a placement. The defaults place the label slightly above its
  /// anchor, expanded.
  const CruxCalloutPlacement({
    this.labelDx = 0,
    this.labelDy = defaultLabelDy,
    this.collapsed = false,
  });

  /// Reads a placement from an annotation record.
  ///
  /// Tolerant: a missing or malformed value reads as its default and never
  /// throws, because one bad note must not fail a whole session load. A
  /// non-finite offset reads as the default too, since it would place the
  /// label nowhere.
  factory CruxCalloutPlacement.fromJson(Map<Object?, Object?> json) {
    double read(String key, double fallback) {
      final value = json[key];
      if (value is! num) return fallback;
      final asDouble = value.toDouble();
      return asDouble.isFinite ? asDouble : fallback;
    }

    return CruxCalloutPlacement(
      labelDx: read(labelDxKey, 0),
      labelDy: read(labelDyKey, defaultLabelDy),
      collapsed: json[collapsedKey] == true,
    );
  }

  /// The default vertical offset: the label sits above its anchor.
  static const double defaultLabelDy = -32;

  /// Record key of [labelDx].
  static const String labelDxKey = 'labelDx';

  /// Record key of [labelDy].
  static const String labelDyKey = 'labelDy';

  /// Record key of [collapsed].
  static const String collapsedKey = 'collapsed';

  /// Horizontal offset of the label from the anchor's projected point, in
  /// logical pixels.
  final double labelDx;

  /// Vertical offset of the label from the anchor's projected point, in
  /// logical pixels.
  final double labelDy;

  /// Whether the canvas draws a numbered dot instead of the expanded label. A
  /// fold, not a hide: the note is still listed and still navigable.
  final bool collapsed;

  /// Whether every field is at its default, so writing it adds nothing.
  bool get isDefault => labelDx == 0 && labelDy == defaultLabelDy && !collapsed;

  /// Writes the non-default fields into [record], and removes the keys of
  /// default ones, so the record's bytes match what WaveCrux has always
  /// written.
  void writeInto(Map<String, Object?> record) {
    if (labelDx != 0) {
      record[labelDxKey] = labelDx;
    } else {
      record.remove(labelDxKey);
    }
    if (labelDy != defaultLabelDy) {
      record[labelDyKey] = labelDy;
    } else {
      record.remove(labelDyKey);
    }
    if (collapsed) {
      record[collapsedKey] = true;
    } else {
      record.remove(collapsedKey);
    }
  }

  /// The placement with the label moved by ([dx], [dy]) logical pixels. The
  /// anchor does not move; that is the point.
  CruxCalloutPlacement nudged(double dx, double dy) => CruxCalloutPlacement(
    labelDx: labelDx + dx,
    labelDy: labelDy + dy,
    collapsed: collapsed,
  );

  /// Returns a copy with selected fields replaced.
  CruxCalloutPlacement copyWith({
    double? labelDx,
    double? labelDy,
    bool? collapsed,
  }) => CruxCalloutPlacement(
    labelDx: labelDx ?? this.labelDx,
    labelDy: labelDy ?? this.labelDy,
    collapsed: collapsed ?? this.collapsed,
  );

  @override
  bool operator ==(Object other) =>
      other is CruxCalloutPlacement &&
      other.labelDx == labelDx &&
      other.labelDy == labelDy &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(labelDx, labelDy, collapsed);

  @override
  String toString() {
    final fold = collapsed ? ', collapsed' : '';
    return 'CruxCalloutPlacement($labelDx, $labelDy$fold)';
  }
}
