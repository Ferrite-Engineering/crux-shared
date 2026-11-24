# crux_window_chrome

Cross-suite **VS Code-style frameless window chrome** for the EDACrux suite —
the custom title bar, left-aligned mnemonic menu bar, and window caption buttons
that WaveCrux pioneered, promoted here so NetCrux, LintCrux and SimCrux render
the identical look and feel.

## What it does

On **Windows and Linux** the desktop products hide the OS title bar and draw
their own in Flutter: app logo at the far left, a left-aligned menu bar with
native **Alt access-key** mnemonics, then min/maximize/close caption buttons.
**macOS** is deliberately excluded — it keeps its native title bar and the
top-of-screen system menu — and web/mobile have no window frame.

There is **no native runner trick**: the Linux/Windows runners install *no* GTK
header bar (only `gtk_window_set_title`), and `window_manager`'s
`TitleBarStyle.hidden` removes the OS decorations at runtime. A
`VirtualWindowFrame` re-adds the drop shadow and drag-to-resize edges a
frameless window loses.

## Public surface

| Symbol | Role |
|---|---|
| `useCustomWindowChrome` | The one predicate (`!kIsWeb && (windows \|\| linux)`) the host branches on in `bootstrap()`, the root `MaterialApp.builder`, and its `DesktopMenuBar`. |
| `windowChromeLeftResizeEdge` | Left resize-edge inset (8 dp on Linux) so a target flush to the window's left edge isn't swallowed by the resize strip. |
| `initWindowChrome({restore})` | Frameless setup + geometry restore before first show, fitted to the work area of the display it lands on. On Linux it also routes the window close and SIGTERM/SIGHUP through the app's exit request. Call in `bootstrap()` after `ensureInitialized()`, guarded by `useCustomWindowChrome`. |
| `routeTerminationSignalsThroughExitRequest()` | SIGTERM and SIGHUP become the exit request a window close sends; the process then ends, within ten seconds at most. Linux and macOS; `initWindowChrome` installs it on Linux, a macOS host calls it from its own startup. |
| `buildWindowFrame(child)` | Wraps the app in `VirtualWindowFrame`. |
| `buildWindowGeometryPersister({child, onChanged})` | Debounced, de-duplicated in-session geometry persist. The host stores the `WindowBounds` (e.g. in its workspace document). |
| `readCurrentWindowBounds()` | One-shot geometry read (e.g. a quit-time flush). |
| `buildWindowTitleBar({menuBar, logo})` | The VS Code title bar. The host passes its own icon widget as `logo`. |
| `MnemonicMenuBar` / `MnemonicMenuEntry` | The left-aligned menu bar with Alt underline + latch. |
| `WindowBounds` / `DisplayWorkArea` | Persisted window-geometry model and the display work areas `WindowBounds.fittedToDisplays` fits it to (pure Dart). |
| `requestUserAttention({kind})` | Portable request-attention primitive: dock bounce / taskbar flash / Wayland urgency, **never** a focus-steal. Call from the CXP inbound hook on an actionable message. Gracefully no-ops where unavailable. |
| `WindowAttentionRequester` / `NoopWindowAttentionRequester` | The swappable attention backend behind the settable `windowAttentionRequester` global — assign `NoopWindowAttentionRequester` to gate the feature behind a user setting. |
| `windowForegroundHandoff` / `WindowForegroundHandoff` / `NoopWindowForegroundHandoff` | The directed cross-probe's foreground hand-off: the sending app yields the foreground to the target's process, and the target takes it with the token the sender passed. Makes no hand-off where the host has not wired it. |

All of `init*` / `build*` / `read*` are web-safe: they route through a
conditional-import facade whose web stub is a no-op passthrough, so neither
`window_manager` nor `dart:io` reaches a web compilation.

### Request-attention

`requestUserAttention()` nudges the OS attention affordance without stealing
focus — a cross-probe must never pull a window in front of the one the user is
typing in. `window_manager` exposes no
attention API, so it forwards over a minimal `crux_window_chrome/attention`
method channel (method `requestUserAttention`, argument `{'kind': ...}`); the
host wires the native side in its runner:

- **macOS** `AppDelegate` — `NSApp.requestUserAttention(.informationalRequest)`
  (or `.criticalRequest` for `WindowAttentionKind.critical`).
- **Windows** runner — `FlashWindowEx`.
- **Linux** runner — the window's urgency / `xdg` attention hint.

Until a host wires it (or on web / an unsupported platform), the call swallows
`MissingPluginException` and no-ops, so it is always safe to invoke — including
from an app's widget tests.

### Foreground hand-off

A cross-probe the user sends to one named app should land them in that app.
Since macOS 14 an app comes forward only when the active app yields to it, and
Windows lets a process set the foreground window only when the foreground
process allowed it, so the sending app (the active one, acting on the user's
click) hands the foreground over and the target takes it. A broadcast never
does: the CXP runtime only hands over on a directed request.

`windowForegroundHandoff` forwards over the `crux_window_chrome/foreground`
method channel; the host wires two methods in its runner:

- `yieldForeground`, argument `{'pid': int}`, answers a `String` token (empty
  when none is needed) or null when no hand-off was made.
  - **macOS**: `NSApp.yieldActivation(to: NSRunningApplication(processIdentifier: pid))`
    on macOS 14 and later; answer `""`.
  - **Windows**: `AllowSetForegroundWindow(pid)`; answer `""`.
  - **Linux**: on Wayland, an `xdg-activation` token (GTK's
    `gdk_app_launch_context_get_startup_notify_id`); on X11, `""`; null where
    the desktop supports neither.
- `takeForeground`, argument `{'token': String}`, answers a `bool`.
  - **macOS**: `NSApp.activate()` and `makeKeyAndOrderFront` on the main window.
  - **Windows**: restore if minimised, then `SetForegroundWindow`.
  - **Linux**: set the startup id to the token when it is not empty, then
    `gtk_window_present`.

Unwired, it answers null and false, so the target asks for attention as before.

### Windows logoff, shutdown and restart

Windows has no SIGTERM: a logoff, shutdown or restart sends each top-level
window `WM_QUERYENDSESSION`, then `WM_ENDSESSION`, and may end the process as
soon as `WM_ENDSESSION` returns. Neither the engine nor `window_manager`
handles them, so each host's `windows/runner/flutter_window.cpp` does, with
no Dart code of its own:

- `WM_QUERYENDSESSION` goes to `DefWindowProc`, which answers `TRUE` at once.
- `WM_ENDSESSION` with `wParam` `TRUE` sends the framework, on
  `flutter/platform`, the cancelable exit request the engine sends when the
  last window closes (`{"method":"System.requestAppExit","args":{"type":"cancelable"}}`),
  then pumps messages until the reply arrives or three seconds pass (Windows
  offers to end an app that holds `WM_ENDSESSION` for five), and returns 0.

Every `AppLifecycleListener.onExitRequested` runs, so the session marker and
the cross-probe peer file are removed as on a window close.
`test/windows_session_end_request_test.dart` pins the message and the reply
the runners rely on. The runner change is identical in every host.

## How a host wires it

Each product keeps its own `DesktopMenuBar` (coupled to its action catalog):

- **macOS** → native `PlatformMenuBar` (unchanged).
- **Windows/Linux** → build the same category-grouped model into a
  `MnemonicMenuBar`, then return
  `Column(children: [buildWindowTitleBar(menuBar: menuBar, logo: appLogo), Expanded(child: child)])`.

And in `bootstrap()` / the root builder:

```dart
WidgetsFlutterBinding.ensureInitialized();
if (useCustomWindowChrome) {
  await initWindowChrome(restore: peekPersistedWindowBounds());
}
// …
if (useCustomWindowChrome) {
  app = buildWindowGeometryPersister(
    onChanged: (b) => persistWindowBounds(b),
    child: buildWindowFrame(app),
  );
}
```

Add `window_manager: ^0.5.0` to the host's `pubspec.yaml`, and make its Linux
runner install no GTK header bar (mirror WaveCrux's `my_application.cc`).

## Exported on purpose

`tool/unused-exports.py` reports a symbol as *internal* when no other package and no product references it. These stay in the export namespace, for the reason given:

- **Named by an exported signature** (a host can receive or must name the type): `WindowAttentionKind` (in `MethodChannelWindowAttentionRequester`), `WindowAttentionRequester` (in `MethodChannelWindowAttentionRequester`).
