// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Hands the foreground from this app to another one, and takes it when it
/// is handed over.
///
/// The seam a directed cross-probe uses: the user clicked *Cross-probe to*
/// a product in this app, so this app (the active one) lets the target come
/// forward, and the target brings its window forward when the request
/// arrives. Unlike `requestUserAttention`, taking the foreground does raise
/// the window, which is why it is only ever done on a hand-off the user's
/// own click made, never on a broadcast.
///
/// Per platform the native side is expected to do:
///
/// - **macOS**: [yieldForegroundTo] yields activation to the running
///   application with that process identifier
///   (`NSApp.yieldActivation(to:)` on macOS 14 and later; earlier releases
///   need no yield) and answers an empty token. [takeForeground] activates
///   the app and orders its main window front.
/// - **Windows**: [yieldForegroundTo] calls `AllowSetForegroundWindow` for
///   the process and answers an empty token. [takeForeground] restores a
///   minimised window and calls `SetForegroundWindow`.
/// - **Linux**: on Wayland, [yieldForegroundTo] requests an `xdg-activation`
///   token from the compositor (GTK's `gdk_app_launch_context` startup
///   notification id) and answers it; [takeForeground] presents the window
///   with that token (`gtk_window_present` after setting the startup id, or
///   `xdg_activation_v1_activate`). On X11 the token may be empty and
///   [takeForeground] presents the window (`_NET_ACTIVE_WINDOW`). Where the
///   desktop supports neither, [yieldForegroundTo] answers null.
///
/// A deliberate swappable seam (method channel, no-op and test fakes behind
/// a settable global), like `WindowAttentionRequester`.
abstract interface class WindowForegroundHandoff {
  /// Lets the process [processId] bring its window forward. Returns the
  /// activation token to send it (empty when the platform needs none), or
  /// null when no hand-off could be made. Never throws.
  Future<String?> yieldForegroundTo(int processId);

  /// Brings this app's window forward with [activationToken], the token the
  /// sender's [yieldForegroundTo] answered. True when the window came
  /// forward; false when the platform refused or could not. Never throws.
  Future<bool> takeForeground(String activationToken);
}

/// A [WindowForegroundHandoff] that does nothing: it never yields and never
/// takes the foreground. The safe default anywhere a hand-off is
/// unavailable.
class NoopWindowForegroundHandoff implements WindowForegroundHandoff {
  /// Creates a no-op hand-off.
  const NoopWindowForegroundHandoff();

  @override
  Future<String?> yieldForegroundTo(int processId) async => null;

  @override
  Future<bool> takeForeground(String activationToken) async => false;
}

/// The platform channel the default hand-off invokes.
///
/// A host wires the native side (its macOS `AppDelegate`, the Windows or
/// Linux runner) to two methods on this channel:
///
/// - `yieldForeground`, argument `{'pid': int}`, answers a `String` (the
///   activation token, empty when none is needed) or null when no hand-off
///   was made;
/// - `takeForeground`, argument `{'token': String}`, answers a `bool`, true
///   when the window came forward.
///
/// Exposed for tests.
@visibleForTesting
const MethodChannel windowForegroundChannel = MethodChannel(
  'crux_window_chrome/foreground',
);

/// The default hand-off: forwards to the host's native handler over
/// [windowForegroundChannel], degrading to "no hand-off" when no handler is
/// registered or the native side fails.
///
/// Degrading is load-bearing: an app that has not wired the native side,
/// or runs where there is none, keeps the behaviour it had before (the
/// target asks for attention), and an app's widget tests, which have no
/// platform handler, do not fail when a cross-probe is sent.
class MethodChannelWindowForegroundHandoff implements WindowForegroundHandoff {
  /// Creates the platform-channel hand-off.
  const MethodChannelWindowForegroundHandoff();

  @override
  Future<String?> yieldForegroundTo(int processId) async {
    if (processId <= 0) return null;
    try {
      return await windowForegroundChannel.invokeMethod<String>(
        'yieldForeground',
        <String, Object?>{'pid': processId},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> takeForeground(String activationToken) async {
    try {
      final raised = await windowForegroundChannel.invokeMethod<bool>(
        'takeForeground',
        <String, Object?>{'token': activationToken},
      );
      return raised ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

WindowForegroundHandoff _handoff = const MethodChannelWindowForegroundHandoff();

/// The active foreground hand-off backend.
///
/// Defaults to [MethodChannelWindowForegroundHandoff]. Assign
/// [NoopWindowForegroundHandoff] (or any implementation) to turn it off or
/// to intercept it in a test.
WindowForegroundHandoff get windowForegroundHandoff => _handoff;
set windowForegroundHandoff(WindowForegroundHandoff handoff) =>
    _handoff = handoff;
