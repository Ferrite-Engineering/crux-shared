// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Facade over the `window_manager`-backed custom window chrome.
///
/// `window_manager` transitively imports `dart:io`, which would break the
/// Flutter **web** build if imported into any web-compiled library. This
/// facade uses a conditional import so:
///
/// - on platforms with `dart:io` (desktop + mobile) the real implementation
///   (`window_chrome_io.dart`) is used; and
/// - on web the no-op stub (`window_chrome_stub.dart`) is used, so neither
///   `window_manager` nor `dart:io` reaches the web compilation.
///
/// Runtime platform gating (only Windows/Linux actually draw custom chrome)
/// stays in `useCustomWindowChrome` — callers guard with it before invoking
/// `initWindowChrome` / `buildWindowFrame`, while `buildWindowTitleBar` is only
/// ever reached on a Windows/Linux desktop (see each host's `DesktopMenuBar`).
library;

export 'window_chrome_stub.dart' if (dart.library.io) 'window_chrome_io.dart';
