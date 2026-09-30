// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// The minimize / maximize-restore / close buttons drawn at the right edge of
/// the window title bar when the app provides its own frameless chrome on
/// Windows/Linux.
///
/// Uses `window_manager`'s themed [WindowCaptionButton]s (which already match
/// the Windows caption-button hover/press feedback and pick light/dark glyphs
/// from [Brightness]) and tracks the maximized state via [WindowListener] so
/// the middle button swaps between the maximize and restore glyphs as the user
/// maximizes / restores by any means (button, double-click, OS shortcut).
///
/// All `window_manager` calls are guarded so the widget builds without a live
/// platform channel (widget tests, unsupported hosts): the listener simply
/// never fires and the button actions are no-ops there.
class WindowCaptionButtons extends StatefulWidget {
  /// Creates the min/maximize/close caption buttons.
  const WindowCaptionButtons({super.key});

  /// Width of one caption button: `window_manager`'s own 46 px minimum, the
  /// Windows caption-button width. Each button is held to exactly this, so
  /// [width] is true by construction rather than an estimate.
  static const double buttonWidth = 46;

  /// Total width of the three caption buttons. The title bar sizes the menu
  /// bar's allowance from it, so it must never under-state the real width.
  static const double width = buttonWidth * 3;

  @override
  State<WindowCaptionButtons> createState() => _WindowCaptionButtonsState();
}

class _WindowCaptionButtonsState extends State<WindowCaptionButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _isMaximized = maximized);
    } on Object {
      // No window_manager platform channel available (tests / unsupported
      // host): keep the default (restore-glyph-hidden) state.
    }
  }

  @override
  void onWindowMaximize() => unawaited(_syncMaximized());

  @override
  void onWindowUnmaximize() => unawaited(_syncMaximized());

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fixedWidth(
          WindowCaptionButton.minimize(
            brightness: brightness,
            onPressed: () => unawaited(windowManager.minimize()),
          ),
        ),
        _fixedWidth(
          _isMaximized
              ? WindowCaptionButton.unmaximize(
                  brightness: brightness,
                  onPressed: () => unawaited(windowManager.unmaximize()),
                )
              : WindowCaptionButton.maximize(
                  brightness: brightness,
                  onPressed: () => unawaited(windowManager.maximize()),
                ),
        ),
        _fixedWidth(
          WindowCaptionButton.close(
            brightness: brightness,
            onPressed: () => unawaited(windowManager.close()),
          ),
        ),
      ],
    );
  }

  static Widget _fixedWidth(Widget button) => SizedBox(
    width: WindowCaptionButtons.buttonWidth,
    child: button,
  );
}
