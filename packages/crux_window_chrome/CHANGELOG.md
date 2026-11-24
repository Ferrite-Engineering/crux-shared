# Changelog

## Unreleased

- **Foreground hand-off for a directed cross-probe.** `WindowForegroundHandoff`
  and its default, `windowForegroundHandoff`, forward over the
  `crux_window_chrome/foreground` channel: `yieldForeground({pid})` in the
  sending app answers an activation token (empty when the platform needs
  none) or null, and `takeForeground({token})` in the target answers whether
  the window came forward. Per platform: macOS yields activation to the
  process (`NSApp.yieldActivation(to:)`, macOS 14 and later) and the target
  activates; Windows calls `AllowSetForegroundWindow` for the target's
  process and the target calls `SetForegroundWindow`; Linux passes an
  `xdg-activation` token on Wayland and presents the window on X11. With no
  native handler it makes no hand-off and never raises.
  `NoopWindowForegroundHandoff` turns it off.

- **Export namespace narrowed by 2 symbols.** `buildWindowTitleBar`, `windowAttentionChannel` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- **Closing the window on Linux asks the app first.** `window_manager`
  replaces the engine's `delete-event` handler, which turns a window close into
  `System.requestAppExit`, with one that lets GTK destroy the window. No
  `AppLifecycleListener` ran, so the unclean-shutdown marker was left behind and
  every window close counted as a crash at the next launch. `initWindowChrome`
  now holds the window open on close and asks the engine to exit through
  `ServicesBinding.exitApplication(AppExitType.cancelable)`. If that request
  fails, the window is closed anyway.

- **A restored window is fitted to the display it lands on.** Saved geometry
  was checked against fixed limits only, so a window saved on another display,
  at another scale or beside another taskbar could open partly off screen (on
  Windows at 175%, 2894 px wide on a 2880 px work area). `initWindowChrome`
  now reads the displays' work areas and applies
  `WindowBounds.fittedToDisplays`: the window is shrunk to fit and moved fully
  onto the work area of the display it overlaps most, or centred on the
  primary display when that display is gone. A maximized window is placed
  first, so it maximizes on its own display. New: `DisplayWorkArea`.

- **SIGTERM and SIGHUP quit like a window close (Linux and macOS).**
  `routeTerminationSignalsThroughExitRequest` watches both signals and sends
  the same cancelable exit request a window close does, so every exit
  listener runs (the session marker and the cross-probe peer file are
  removed), then ends the process, within ten seconds at most. A second
  signal starts nothing new. `initWindowChrome` installs it on Linux.

## 0.2.0

- Add the portable **request-attention** primitive, for an actionable
  cross-probe arriving at a window that is not in front. `requestUserAttention({WindowAttentionKind kind})` nudges the OS's
  attention affordance — macOS dock bounce (`NSApp.requestUserAttention`),
  Windows taskbar flash (`FlashWindowEx`), Linux X11/Wayland urgency / `xdg`
  attention hint — **without ever raising, focusing, or foregrounding the
  window** (decision 1: no focus steal). Meant to be called from the shared CXP
  inbound hook when an actionable message is applied.
- Implemented as a swappable seam: `WindowAttentionRequester` with the default
  `MethodChannelWindowAttentionRequester` (forwards to the host's native handler
  over the `crux_window_chrome/attention` channel) and `NoopWindowAttentionRequester`.
  `window_manager` (already a dependency) exposes no attention API, so this uses
  a minimal method channel; the host wires the native side in its runner.
- Gracefully **no-ops** where attention is unavailable — web, an unsupported
  platform, or an app that has not wired the native side — by swallowing
  `MissingPluginException` / `PlatformException`, so an app's widget tests never
  explode when their CXP inbound hook fires. The settable `windowAttentionRequester`
  global lets a user setting gate the feature (assign `NoopWindowAttentionRequester`
  to turn it off).
- No change to the existing window-chrome surface.

## 0.1.0

- Initial release. The suite's VS Code-style frameless window chrome, promoted
  from the proven WaveCrux implementation as the shared source of truth so all
  four desktop products render identical chrome on Windows/Linux.
- `useCustomWindowChrome` — the single platform predicate (`!kIsWeb && (windows
  || linux)`) every host branches on — plus `windowChromeLeftResizeEdge`, the
  left resize-edge inset a `VirtualWindowFrame` overlays on Linux.
- Window-manager wiring, web-guarded behind a conditional-import facade so
  neither `window_manager` nor `dart:io` reaches a web build: `initWindowChrome`
  (frameless `TitleBarStyle.hidden` + geometry restore before first show),
  `buildWindowFrame` (`VirtualWindowFrame` shadow/resize edges),
  `buildWindowGeometryPersister` (debounced, de-duplicated in-session persist),
  and `readCurrentWindowBounds`.
- `buildWindowTitleBar` — the VS Code title bar (host-supplied `logo`, inline
  `menuBar`, min/maximize/close caption buttons).
- `MnemonicMenuBar` / `MnemonicMenuEntry` — the left-aligned Material menu bar
  with native Alt access-key underline + latch behaviour.
- `WindowBounds` — the persisted window-geometry model (pure Dart), with
  `sanitizedForRestore` off-screen/degenerate guards.
- The host keeps its own `DesktopMenuBar`: macOS renders a native
  `PlatformMenuBar`; Windows/Linux feed a `MnemonicMenuBar` into
  `buildWindowTitleBar`.
