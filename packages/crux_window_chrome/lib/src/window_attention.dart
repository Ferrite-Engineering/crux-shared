// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// The urgency of a [requestUserAttention] request.
///
/// Maps to each platform's informational-vs-critical distinction where one
/// exists (macOS `NSRequestUserAttentionType`, Windows `FlashWindowEx` flag
/// count / stop-at-focus). Platforms without the distinction treat both the
/// same.
enum WindowAttentionKind {
  /// A gentle, one-shot nudge — a single dock bounce / brief taskbar flash.
  /// The default; use for an ordinary actionable cross-probe arriving.
  informational,

  /// A persistent nudge — a continuous dock bounce / taskbar flash until the
  /// window is focused. Reserve for genuinely can't-miss events.
  critical,
}

/// A portable "request the user's attention" primitive.
///
/// The seam the shared CXP inbound hook calls when an *actionable* message
/// lands (a highlight applied, an artifact opened) to nudge the OS's attention
/// affordance — **without ever stealing focus**. Per platform the native side
/// is expected to do:
///
/// - **macOS** — `NSApp.requestUserAttention(.informationalRequest)` (a dock
///   bounce); `.criticalRequest` for [WindowAttentionKind.critical].
/// - **Windows** — `FlashWindowEx` (taskbar button flash).
/// - **Linux X11/Wayland** — the window's urgency / `xdg` attention hint.
///
/// It must **never** raise, focus, or foreground the window — that is the whole
/// point of decision 1, and the difference between a courteous nudge and a
/// disruptive focus-steal.
///
/// A deliberate swappable seam (method-channel / no-op / test-fake
/// implementations behind a settable global), not a one-shot callback.
// ignore: one_member_abstracts
abstract interface class WindowAttentionRequester {
  /// Requests user attention at the given [kind]. Implementations must never
  /// throw and never steal focus.
  Future<void> requestUserAttention(WindowAttentionKind kind);
}

/// A [WindowAttentionRequester] that does nothing.
///
/// The no-op seam a user setting flips to: an app whose "bounce on cross-probe"
/// preference is off assigns this to [windowAttentionRequester]; turning the
/// preference back on restores [MethodChannelWindowAttentionRequester]. Also
/// the safe default anywhere attention is unavailable.
class NoopWindowAttentionRequester implements WindowAttentionRequester {
  /// Creates a no-op requester.
  const NoopWindowAttentionRequester();

  @override
  Future<void> requestUserAttention(WindowAttentionKind kind) async {}
}

/// The platform channel the default requester invokes.
///
/// A host wires the native side (in its macOS `AppDelegate` / the Windows /
/// Linux runner) to this channel's `requestUserAttention` method, whose sole
/// argument is `{'kind': 'informational' | 'critical'}`. Exposed for tests.
@visibleForTesting
const MethodChannel windowAttentionChannel = MethodChannel(
  'crux_window_chrome/attention',
);

/// The default requester: forwards to the host's native handler over
/// [windowAttentionChannel], degrading to a silent no-op when no handler is
/// registered.
///
/// The graceful no-op is load-bearing. On web, on a platform with no native
/// implementation, or in an app that has not (yet) wired the native side, the
/// channel throws [MissingPluginException]; a native failure throws
/// [PlatformException]. Both are swallowed — requesting attention is a
/// courtesy that must never disrupt the caller, and this is exactly what keeps
/// app widget tests (which have a binding but no platform handler) from
/// exploding when their CXP inbound hook fires.
class MethodChannelWindowAttentionRequester
    implements WindowAttentionRequester {
  /// Creates the platform-channel requester.
  const MethodChannelWindowAttentionRequester();

  @override
  Future<void> requestUserAttention(WindowAttentionKind kind) async {
    try {
      await windowAttentionChannel.invokeMethod<void>(
        'requestUserAttention',
        <String, Object?>{'kind': kind.name},
      );
    } on MissingPluginException {
      // No native handler (web, unsupported platform, or not-yet-wired app).
    } on PlatformException {
      // Native side failed — attention must never surface as an error.
    }
  }
}

WindowAttentionRequester _requester =
    const MethodChannelWindowAttentionRequester();

/// The active attention backend.
///
/// Defaults to [MethodChannelWindowAttentionRequester]. Assign
/// [NoopWindowAttentionRequester] (or any custom implementation) to gate the
/// feature behind a user setting, or to intercept it in a test.
WindowAttentionRequester get windowAttentionRequester => _requester;
set windowAttentionRequester(WindowAttentionRequester requester) =>
    _requester = requester;

/// Requests the user's attention via the active [windowAttentionRequester],
/// **without stealing focus** — a cross-probe must never pull a window in
/// front of the one the user is typing in.
///
/// Call this from the CXP inbound hook when an actionable message has been
/// applied. Safe to call anywhere: it never throws and no-ops when attention is
/// unavailable or gated off. [kind] defaults to
/// [WindowAttentionKind.informational].
Future<void> requestUserAttention({
  WindowAttentionKind kind = WindowAttentionKind.informational,
}) => _requester.requestUserAttention(kind);
