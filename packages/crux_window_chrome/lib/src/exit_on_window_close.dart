// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Makes closing the window an exit *request* to the app, as the Flutter
/// engine itself does, instead of tearing the window down underneath Dart.
///
/// On Linux the engine turns the window's `delete-event` into
/// `System.requestAppExit`, which reaches every `AppLifecycleListener`: the
/// unclean-shutdown detector removes its session marker there, and a product
/// can veto the exit. `window_manager` disconnects that handler when it
/// registers and installs its own, which lets GTK destroy the window and quit
/// with no Dart running. The title-bar close, the desktop's close and Alt+F4
/// all took that path, so every window close on Linux left the marker behind
/// and was counted as a crash at the next launch.
///
/// This holds the window open on close and asks the engine to exit through
/// [ServicesBinding.exitApplication] with [AppExitType.cancelable]. The engine
/// runs the same request the close used to send, and quits only if nobody
/// cancels it.
///
/// Called from `initWindowChrome` on Linux only. On Windows the engine's
/// lifecycle manager sees `WM_CLOSE` before `window_manager` does; on macOS
/// the native frame's close reaches `applicationShouldTerminate`. Both already
/// ask the app, which the 1.1.0 smoke test confirmed on Windows.
///
/// The parameters are seams for tests; production passes none.
Future<void> routeWindowCloseThroughExitRequest({
  // Matches window_manager's own `setPreventClose(bool)` signature.
  // ignore: avoid_positional_boolean_parameters
  Future<void> Function(bool prevent)? setPreventClose,
  void Function(WindowListener listener)? addListener,
  Future<AppExitResponse> Function()? requestExit,
  Future<void> Function()? forceClose,
}) async {
  await (setPreventClose ?? windowManager.setPreventClose)(true);
  (addListener ?? windowManager.addListener)(
    ExitRequestOnWindowClose(
      requestExit:
          requestExit ??
          () => ServicesBinding.instance.exitApplication(
            AppExitType.cancelable,
          ),
      forceClose: forceClose ?? windowManager.destroy,
    ),
  );
}

/// The [WindowListener] [routeWindowCloseThroughExitRequest] installs: every
/// close becomes one cancelable exit request. A second close while a request
/// is still being answered is ignored, so a double click on the close button
/// is one question to the app, not two. If the request itself fails, the
/// window is closed anyway through [forceClose]: a close button that does
/// nothing is worse than a marker left behind.
class ExitRequestOnWindowClose with WindowListener {
  /// A listener that calls [requestExit] on each window close.
  ExitRequestOnWindowClose({
    required this.requestExit,
    required this.forceClose,
  });

  /// Asks the engine to exit; it quits once every listener agrees.
  final Future<AppExitResponse> Function() requestExit;

  /// Closes the window without asking, used only when [requestExit] fails.
  final Future<void> Function() forceClose;

  bool _pending = false;

  @override
  void onWindowClose() {
    if (_pending) return;
    _pending = true;
    unawaited(_ask());
  }

  Future<void> _ask() async {
    try {
      await requestExit();
    } on Object {
      await forceClose();
    } finally {
      _pending = false;
    }
  }
}
