// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite VS Code-style frameless window chrome for the EDACrux suite.
///
/// The desktop products (WaveCrux, NetCrux, LintCrux, SimCrux) draw their own
/// title bar on **Windows and Linux** instead of the OS-drawn one: an app logo
/// at the far left, a left-aligned in-window menu bar with native Alt
/// access-key mnemonics, and custom min/maximize/close caption buttons. macOS
/// keeps its native title bar + top-of-screen system menu; web and mobile have
/// no window frame.
///
/// The mechanism is entirely runtime `window_manager` (`TitleBarStyle.hidden`
/// removes the OS decorations) plus Flutter-drawn widgets — the native runners
/// install **no** GTK header bar. This package owns the reusable half:
///
/// - `useCustomWindowChrome` / `windowChromeLeftResizeEdge` — the platform
///   predicate every host branches on, and the left resize-edge inset.
/// - `initWindowChrome` / `buildWindowFrame` / `buildWindowGeometryPersister` /
///   `readCurrentWindowBounds` — the `bootstrap()` and root-builder wiring,
///   web-guarded by a conditional-import facade.
/// - `buildWindowTitleBar` — the VS Code title bar; the host passes its own
///   `logo` widget and the in-window `menuBar`.
/// - `MnemonicMenuBar` / `MnemonicMenuEntry` — the left-aligned Material menu
///   bar with Alt-access-key underline + latch behaviour.
/// - `WindowBounds` — the persisted window geometry model.
/// - `requestUserAttention` / `WindowAttentionRequester` — the portable
///   request-attention primitive (dock bounce / taskbar flash / Wayland
///   urgency) the CXP inbound hook calls; never steals focus, gracefully
///   no-ops where unavailable, and swappable behind a user setting.
///
/// Each host keeps its own `DesktopMenuBar` (it is coupled to that product's
/// action catalog): on macOS it renders a native `PlatformMenuBar`; on
/// Windows/Linux it feeds a `MnemonicMenuBar` into `buildWindowTitleBar`.
library;

export 'src/widgets/mnemonic_menu_bar.dart'
    show MnemonicMenuBar, MnemonicMenuEntry;
export 'src/window_attention.dart';
export 'src/window_bounds.dart';
export 'src/window_chrome.dart';
export 'src/window_chrome_platform.dart';
