// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A transparent wrapper that fires [onContextMenu] on both right-click
/// (desktop) and long-press (touch platforms), unifying the two interaction
/// patterns. The suite-wide "long-press = right-click" affordance.
///
/// - **Desktop OS in a pointer-first layout:** [onContextMenu] fires on
///   secondary-button tap-up (right-click / two-finger tap on macOS).
///   Long-press is **not** enabled to avoid an unexpected 500 ms delay on
///   pointer devices.
/// - **All other contexts** (touch-first layouts, or any iOS / Android host
///   even when the window is desktop-sized — e.g. a large tablet in
///   landscape): [onContextMenu] fires on long-press start. Right-click
///   still works if an external mouse is connected.
///
/// The callback receives the global [Offset] so callers can position a
/// popup menu or custom overlay at the correct screen location.
///
/// The host platform is read from the inherited theme
/// (`Theme.of(context).platform`) so `MaterialApp` / `ThemeData` overrides
/// flow through to this check (used by widget tests). The host supplies
/// [isTouchLayout] from its own responsive-layout classification (e.g.
/// phone / phone-landscape / tablet device classes map to `true`); it
/// matters on web, where a touch device can report a desktop
/// `TargetPlatform` and only the layout classification knows the user is
/// on touch. It defaults to `false` (pointer-first).
class PlatformContextMenu extends StatelessWidget {
  /// Creates the wrapper. See the class docs for how [isTouchLayout]
  /// interacts with the host platform.
  const PlatformContextMenu({
    required this.child,
    required this.onContextMenu,
    this.isTouchLayout = false,
    super.key,
  });

  /// The widget whose area triggers the context menu.
  final Widget child;

  /// Called with the global screen position where the context menu should
  /// appear. On right-click this is the pointer-up location; on long-press
  /// this is the press start location.
  final void Function(Offset globalPosition) onContextMenu;

  /// Whether the host's responsive layout is currently touch-first.
  /// Enables the long-press trigger even on a desktop `TargetPlatform`.
  final bool isTouchLayout;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final enableLongPress = shouldEnableLongPressContextMenu(
      isTouchLayout: isTouchLayout,
      platform: platform,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (d) => onContextMenu(d.globalPosition),
      onLongPressStart: enableLongPress
          ? (d) => onContextMenu(d.globalPosition)
          : null,
      child: child,
    );
  }
}

/// Returns true when long-press should fire a context menu for a layout
/// classified as [isTouchLayout] running on the given [platform].
///
/// Enabled for:
/// - touch-first layouts (the host's phone / phone-landscape / tablet
///   classes), or
/// - any non-desktop host platform (iOS, Android) regardless of layout
///   class. This is what catches a large tablet in landscape, which the
///   host may classify as a desktop-sized layout but which has no
///   right-click without an external mouse.
bool shouldEnableLongPressContextMenu({
  required bool isTouchLayout,
  required TargetPlatform platform,
}) {
  if (isTouchLayout) return true;
  return platform != TargetPlatform.linux &&
      platform != TargetPlatform.macOS &&
      platform != TargetPlatform.windows;
}
