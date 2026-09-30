// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_window_chrome/src/widgets/window_caption_buttons.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// VS Code-style custom title bar for the frameless Windows/Linux window:
/// the app [logo] at the far left, the in-window menu bar inline next to it, a
/// draggable empty region, and the min/maximize/close caption buttons at the
/// right.
///
/// Rendered by each host's `DesktopMenuBar` in place of the bare menu strip
/// whenever the build draws its own chrome (`useCustomWindowChrome`). macOS
/// never uses this — it keeps the native title bar + system menu. The matching
/// frameless window + drop-shadow/resize frame are set up in the host's
/// `bootstrap()` and root `MaterialApp.builder` (see `initWindowChrome` /
/// `buildWindowFrame`).
///
/// The [logo] and the empty region are wrapped in [DragToMoveArea] so the user
/// can drag the window by them (and double-click to maximize/restore); the
/// menu bar itself stays interactive and is not draggable.
class WindowTitleBar extends StatelessWidget {
  /// Creates the custom title bar hosting [logo], [menuBar], and the caption
  /// buttons.
  const WindowTitleBar({
    required this.menuBar,
    required this.logo,
    super.key,
  });

  /// The in-window menu bar (File / View / …) rendered inline after the logo.
  final Widget menuBar;

  /// The host's app logo, rendered at the far left of the bar (draggable).
  /// Each product passes its own icon widget so the shared bar carries no
  /// per-product asset dependency.
  final Widget logo;

  /// Title-bar strip height — slim, matching the VS Code custom title bar and
  /// the compact menu metrics. Desktop chrome only (never a touch surface).
  static const double height = 36;

  /// Edge length of the square box the [logo] is laid out in. The logo is
  /// host-supplied, so the bar fixes its size rather than trusting it: the
  /// menu bar's width allowance is computed from [logoSlotWidth], and a logo
  /// wider than assumed would push the caption buttons off the right edge.
  static const double logoSize = 18;

  /// Horizontal padding either side of the [logo].
  static const double logoPadding = 8;

  /// Total width the logo occupies at the left of the bar.
  static const double logoSlotWidth = logoSize + 2 * logoPadding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The widest the menu bar may be: everything the fixed-width
            // logo and caption buttons leave over.
            final menuMaxWidth = math.max<double>(
              0,
              constraints.maxWidth - logoSlotWidth - WindowCaptionButtons.width,
            );
            return Row(
              children: [
                // App logo, far left. Draggable + double-click-to-maximize.
                DragToMoveArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: logoPadding,
                    ),
                    child: SizedBox.square(dimension: logoSize, child: logo),
                  ),
                ),
                // Inline menus — interactive, so NOT inside a DragToMoveArea.
                //
                // Bounded + horizontal scroll, not a bare child: the caption
                // buttons are a fixed width and the menu bar's natural width
                // is whatever the host's menu titles add up to, so on a
                // narrow window an unbounded menu bar leaves the Row nothing
                // it may shrink and it overflows — 127px past the right edge
                // at 390pt, which put the close button off-screen. Letting
                // the menus scroll keeps every menu reachable and keeps the
                // window controls where the OS expects them.
                //
                // The bound is an explicit maximum, not a flex share. A
                // Flexible here would split the free space in half with the
                // drag region below, and the half the menus did not use
                // would be left over after the caption buttons, so they sat
                // short of the right edge on any window wider than twice the
                // menus.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: menuMaxWidth),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // The bar is desktop chrome and the strip is 36pt tall; a
                    // visible scrollbar would eat a third of it.
                    child: menuBar,
                  ),
                ),
                // The only flex child, so it takes all the remaining width
                // and the caption buttons are always flush right. It is a
                // drag region right up to the buttons; collapsing it to zero
                // is what makes the menus start scrolling.
                const Expanded(
                  child: DragToMoveArea(child: SizedBox.expand()),
                ),
                const WindowCaptionButtons(),
              ],
            );
          },
        ),
      ),
    );
  }
}
