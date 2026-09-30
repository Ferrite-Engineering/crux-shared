// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Sizing the keyboard-binding editor widgets need, supplied by the host so the
/// package stays free of any product's device-metrics system.
///
/// WaveCrux builds this from its `MobileMetrics`; other products fill it from
/// their own equivalents (or sensible Material defaults).
@immutable
class KeyBindingEditorMetrics {
  /// Creates a metrics bundle.
  const KeyBindingEditorMetrics({
    required this.touchTarget,
    required this.iconSize,
    required this.bodyFontSize,
    required this.labelFontSize,
    required this.monoFontSize,
  });

  /// Minimum hit-area edge (dp) for the per-row icon buttons.
  final double touchTarget;

  /// Icon size (dp) for the per-row buttons and the capture-field glyph.
  final double iconSize;

  /// Font size for the action label.
  final double bodyFontSize;

  /// Font size for the conflict warning and the capture prompt.
  final double labelFontSize;

  /// Font size for the monospace binding chip.
  final double monoFontSize;
}
