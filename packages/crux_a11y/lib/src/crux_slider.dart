// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A [Slider] that stays accessible inside dialogs and pushed routes.
///
/// [Slider] always wraps its value indicator in an `OverlayPortal`, whatever
/// [Slider.showValueIndicator] says. When the slider sits in a pushed route the
/// overlay child is serialized as a semantics node that no parent claims, and
/// the desktop accessibility bridge rejects the whole update — from then on a
/// screen reader keeps describing the screen as it was before the dialog
/// opened (flutter/flutter#190357). Hosting the slider in its own [Overlay]
/// keeps the portal's child inside the slider's own semantics subtree, which
/// removes the orphan without changing how the slider looks, focuses or
/// announces.
///
/// The overlay is sized to the slider and does not clip, so the value
/// indicator still paints above the track. Everything else is passed straight
/// through to [Slider].
class CruxSlider extends StatelessWidget {
  /// Creates a slider that is safe to host in a dialog or pushed route.
  const CruxSlider({
    required this.value,
    required this.onChanged,
    super.key,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.semanticFormatterCallback,
    this.focusNode,
    this.autofocus = false,
  });

  /// See [Slider.value].
  final double value;

  /// See [Slider.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [Slider.onChangeStart].
  final ValueChanged<double>? onChangeStart;

  /// See [Slider.onChangeEnd].
  final ValueChanged<double>? onChangeEnd;

  /// See [Slider.min].
  final double min;

  /// See [Slider.max].
  final double max;

  /// See [Slider.divisions].
  final int? divisions;

  /// See [Slider.label].
  final String? label;

  /// See [Slider.activeColor].
  final Color? activeColor;

  /// See [Slider.inactiveColor].
  final Color? inactiveColor;

  /// See [Slider.thumbColor].
  final Color? thumbColor;

  /// See [Slider.semanticFormatterCallback].
  final SemanticFormatterCallback? semanticFormatterCallback;

  /// See [Slider.focusNode].
  final FocusNode? focusNode;

  /// See [Slider.autofocus].
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Overlay.wrap(
      alwaysSizeToContent: true,
      clipBehavior: Clip.none,
      child: Slider(
        value: value,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        thumbColor: thumbColor,
        semanticFormatterCallback: semanticFormatterCallback,
        focusNode: focusNode,
        autofocus: autofocus,
      ),
    );
  }
}
