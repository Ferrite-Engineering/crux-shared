// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Whether this build draws its own frameless window chrome (a VS Code-style
/// custom title bar: app logo + inline menus + custom min/maximize/close
/// caption buttons) instead of the OS-drawn title bar.
///
/// True only on **Windows** and **Linux** desktop. macOS is excluded on
/// purpose: it keeps its native (hidden-text) title bar and the system menu
/// bar at the top of the screen, so an in-window title bar would be redundant
/// chrome. Web and mobile have no desktop window frame at all.
///
/// This single predicate is the source of truth shared by the three places
/// that must agree in each host: the `window_manager` init in `bootstrap()`,
/// the `VirtualWindowFrame` wrapper in the root `MaterialApp.builder`, and the
/// `WindowTitleBar` rendered by the host's `DesktopMenuBar`.
bool get useCustomWindowChrome =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Width (logical px) of the frameless window's drag-to-resize border along the
/// **left** edge of the content, or 0 where no such border exists.
///
/// `window_manager`'s `VirtualWindowFrame` overlays drag-to-resize strips on
/// the window edges. On **Linux** it enables *all* edges at the package default
/// `resizeEdgeSize` (8 dp), so an 8 dp strip sits over the left edge of the app
/// content. On **Windows** only the *top* edges are enabled (no left strip),
/// and macOS/web/mobile draw no custom chrome — all zero.
///
/// Content that places an interactive target flush against the window's left
/// edge must inset past this, or the resize strip swallows its pointer events.
/// The concrete case is a leading tab insertion slot in a tab bar: it sits at
/// x∈[0,8] and, without this inset, is an unreachable drop target on Linux
/// because the resize border occludes it.
///
/// Note: Linux also disables the resize edges while the window is maximized or
/// full-screen, so the inset is cosmetically redundant (a small leading gap) in
/// those states; tracking that transient state in every consumer is not worth
/// the plumbing, so the inset is kept constant.
double get windowChromeLeftResizeEdge =>
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) ? 8.0 : 0.0;
