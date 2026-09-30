// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/src/toolbar_button.dart';
import 'package:crux_toolbar/src/toolbar_metrics.dart';
import 'package:flutter/material.dart';

/// What a [CruxRunStopButton] is currently showing.
enum CruxRunState {
  /// Nothing is running; the button offers to start.
  idle,

  /// A run is in flight; the button offers to cancel and shows progress.
  running,

  /// A run just finished; the button briefly acknowledges before returning
  /// to [idle].
  finished,
}

/// A single control that morphs between Run and Cancel.
///
/// LintCrux and SimCrux each rendered Run and Cancel as two permanently-live
/// buttons side by side, so the toolbar never told the user whether a run was
/// in flight — and both were clickable when neither was valid. One button that
/// *is* the run state removes the ambiguity, and is what VS Code and IntelliJ
/// do.
///
/// While running it wears a ring: determinate when [progress] is supplied,
/// indeterminate otherwise.
class CruxRunStopButton extends StatelessWidget {
  /// Creates a run/stop control.
  const CruxRunStopButton({
    required this.state,
    required this.metrics,
    required this.runTooltip,
    required this.cancelTooltip,
    required this.onRun,
    required this.onCancel,
    this.progress,
    this.finishedTooltip,
    super.key,
  });

  /// The current run state.
  final CruxRunState state;

  /// Geometry tokens.
  final CruxToolbarMetrics metrics;

  /// Tooltip while idle, e.g. "Run All Engines".
  final String runTooltip;

  /// Tooltip while running, e.g. "Cancel Run".
  final String cancelTooltip;

  /// Tooltip in the brief finished state. Falls back to [runTooltip].
  final String? finishedTooltip;

  /// Starts a run. Null greys the button — there is nothing to run.
  final VoidCallback? onRun;

  /// Cancels the running run. Null greys the button.
  final VoidCallback? onCancel;

  /// Fraction complete in `[0, 1]`, or null for an indeterminate ring.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final button = switch (state) {
      CruxRunState.idle => CruxToolbarButton(
        icon: Icons.play_arrow,
        tooltip: runTooltip,
        onPressed: onRun,
        metrics: metrics,
      ),
      CruxRunState.running => CruxToolbarButton(
        icon: Icons.stop,
        tooltip: cancelTooltip,
        onPressed: onCancel,
        metrics: metrics,
      ),
      CruxRunState.finished => CruxToolbarButton(
        icon: Icons.check_circle_outline,
        tooltip: finishedTooltip ?? runTooltip,
        onPressed: onRun,
        metrics: metrics,
      ),
    };

    if (state != CruxRunState.running) {
      return state == CruxRunState.finished
          ? IconTheme.merge(
              data: IconThemeData(color: scheme.tertiary),
              child: button,
            )
          : button;
    }

    // The ring sits *behind* the stop glyph, inset so it traces the button's
    // edge rather than crowding the icon.
    return SizedBox(
      width: metrics.buttonSize,
      height: metrics.buttonSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: metrics.iconSize + 10,
            height: metrics.iconSize + 10,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          button,
        ],
      ),
    );
  }
}
