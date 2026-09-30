// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:crux_theme/crux_theme.dart' show CruxChromeColors;
import 'package:crux_toolbar/src/toolbar_metrics.dart';
import 'package:flutter/material.dart';

/// Builds the tooltip text for a toolbar button: the label, plus the user's
/// *current* binding for the action when it has one.
///
/// The accelerator is resolved at render time rather than written into the
/// label. Baking it into the string — as `"Zoom In (W)"` did in five WaveCrux
/// ARB keys across five locales — makes the tooltip a lie the moment the user
/// rebinds the action, which the suite's keymap editor lets them do.
String cruxToolbarTooltip(String label, ShortcutActivator? activator) {
  final shortcut = formatShortcutLabel(activator);
  return shortcut.isEmpty ? label : '$label  ($shortcut)';
}

/// A compact icon button sized for a `CruxToolbar`.
///
/// Hit box and glyph size come from [metrics], so the whole suite is one
/// density decision rather than four.
class CruxToolbarButton extends StatelessWidget {
  /// Creates a toolbar button.
  const CruxToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.metrics,
    this.isSelected = false,
    this.tintWhenSelected = true,
    this.badgeCount = 0,
    this.tooltipOnHoverOnly = false,
    super.key,
  });

  /// The glyph to render.
  final IconData icon;

  /// Tooltip text — build it with [cruxToolbarTooltip] so the live binding
  /// shows.
  final String tooltip;

  /// Tap handler. Null renders the button greyed out.
  final VoidCallback? onPressed;

  /// Geometry tokens.
  final CruxToolbarMetrics metrics;

  /// Whether the button is in its "on" state.
  final bool isSelected;

  /// Whether the selected state tints the glyph: with the theme's
  /// `toolbar.iconActive` chrome token when it sets one
  /// ([CruxChromeColors.toolbarIconActive]), otherwise with the primary
  /// colour.
  final bool tintWhenSelected;

  /// A count rendered as a `Badge`. Zero hides it.
  final int badgeCount;

  /// Shows the tooltip on hover only, never on long-press.
  ///
  /// `Tooltip` registers its own long-press recognizer, which sits deeper in
  /// the tree than any ancestor's and therefore wins the gesture arena. That
  /// is fine for an ordinary button, but it swallows the long-press that opens
  /// a `CruxToolbarSplitButton`'s sibling menu. Setting this builds the
  /// tooltip manually with `TooltipTriggerMode.manual`, which keeps hover
  /// (the desktop affordance) and frees the long-press for the menu (the
  /// touch affordance) — each platform keeps the gesture that matters to it.
  final bool tooltipOnHoverOnly;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeTint =
        CruxChromeColors.of(context)?.toolbarIconActive ?? scheme.primary;
    final iconButton = IconButton(
      icon: Icon(
        icon,
        size: metrics.iconSize,
        color: isSelected && tintWhenSelected ? activeTint : null,
      ),
      tooltip: tooltipOnHoverOnly ? null : tooltip,
      isSelected: isSelected,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
    final button = SizedBox(
      width: metrics.buttonSize,
      height: metrics.buttonSize,
      child: tooltipOnHoverOnly
          ? Tooltip(
              message: tooltip,
              triggerMode: TooltipTriggerMode.manual,
              child: iconButton,
            )
          : iconButton,
    );
    if (badgeCount <= 0) return button;
    // The bubble is an overlay, NOT a wrapper: wrapping the button in
    // `Badge.count` put the (hit-testable) bubble over the button's corner,
    // where it swallowed taps — clicking the count did nothing and shrank
    // the clickable area. The Stack keeps the IconButton as the sole hit
    // target and paints a compact, pointer-transparent bubble above it.
    // `Badge.count` still clamps its own label at 999+.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        PositionedDirectional(
          top: 2,
          end: 2,
          child: IgnorePointer(
            child: Badge.count(
              count: badgeCount,
              largeSize: 12,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              textStyle: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The vertical rule between two logical groups of toolbar buttons.
class CruxToolbarDivider extends StatelessWidget {
  /// Creates a divider.
  const CruxToolbarDivider({required this.metrics, super.key});

  /// Geometry tokens.
  final CruxToolbarMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: metrics.dividerWidth,
      child: Center(
        child: Container(
          width: 1,
          height: metrics.dividerHeight,
          color: scheme.outlineVariant,
        ),
      ),
    );
  }
}
