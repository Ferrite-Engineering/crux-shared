# Changelog

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
