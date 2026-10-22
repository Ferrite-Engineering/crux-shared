// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The on-canvas annotation layer shared by WaveCrux and NetCrux.
///
/// `crux_annotations_core.dart` is the `dart:ui`-free subset of this barrel.
///
/// The shared half of an annotation: the anchor contract (data coordinates,
/// never pixels), the label placement and its persistence shape, the drift
/// status vocabulary and the decision table that assigns it, the callout
/// geometry and level of detail, and the widgets that draw and drag balloons,
/// numbered dots and leaders, plus the panel's group header. Anchor
/// resolution to the screen, the witness and its comparison, note creation and
/// every string stay with the product. The boundary is recorded in
/// `docs/adr/0006-annotations-anchor-in-data-coordinates.md`.
library;

export 'src/anchor.dart';
export 'src/drift_color.dart';
export 'src/geometry.dart';
export 'src/placement.dart';
export 'src/status.dart';
export 'src/widgets/balloon.dart';
export 'src/widgets/double_tap_region.dart';
export 'src/widgets/draggable.dart';
export 'src/widgets/group.dart';
export 'src/widgets/inline_editor.dart';
export 'src/widgets/leaders.dart';
export 'src/widgets/number_dot.dart';
