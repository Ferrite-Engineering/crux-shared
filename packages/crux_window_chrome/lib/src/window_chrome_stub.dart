// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/window_bounds.dart';
import 'package:flutter/material.dart';

/// Web (no `dart:io`) stub of the window-chrome facade. Selected by the
/// conditional export in `window_chrome.dart` when `dart:io` is unavailable,
/// so neither `window_manager` nor `dart:io` reaches the web compilation.
///
/// Web has no desktop window frame, so every entry point is a no-op /
/// passthrough. These are never actually invoked on web anyway
/// (`useCustomWindowChrome` is false and hosts render no in-window title bar on
/// web), but they must exist so the facade compiles.

/// No-op: web cannot make the window frameless. [restore] is ignored — the
/// browser owns the viewport size.
Future<void> initWindowChrome({WindowBounds? restore}) async {}

/// No-op: web has no OS window to measure. Returns null so the caller skips
/// persisting geometry.
Future<WindowBounds?> readCurrentWindowBounds() async => null;

/// Passthrough: web has no OS window to track, so [onChanged] is never called.
Widget buildWindowGeometryPersister({
  required Widget child,
  required Future<void> Function(WindowBounds bounds) onChanged,
}) => child;

/// Passthrough: web has no window frame to draw.
Widget buildWindowFrame(Widget child) => child;

/// Passthrough: web never renders the desktop title bar; returns the bare menu.
Widget buildWindowTitleBar({
  required Widget menuBar,
  required Widget logo,
}) => menuBar;

/// Passthrough: web draws no custom chrome, so it renders the app [child]
/// directly (never invoked — `useCustomWindowChrome` is false on web).
Widget buildWindowChrome({
  required Widget menuBar,
  required Widget logo,
  required Widget child,
}) => child;
