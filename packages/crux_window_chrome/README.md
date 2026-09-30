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
| `initWindowChrome({restore})` | Frameless setup + geometry restore before first show. Call in `bootstrap()` after `ensureInitialized()`, guarded by `useCustomWindowChrome`. |
| `buildWindowFrame(child)` | Wraps the app in `VirtualWindowFrame`. |
| `buildWindowGeometryPersister({child, onChanged})` | Debounced, de-duplicated in-session geometry persist. The host stores the `WindowBounds` (e.g. in its workspace document). |
| `readCurrentWindowBounds()` | One-shot geometry read (e.g. a quit-time flush). |
| `buildWindowTitleBar({menuBar, logo})` | The VS Code title bar. The host passes its own icon widget as `logo`. |
| `MnemonicMenuBar` / `MnemonicMenuEntry` | The left-aligned menu bar with Alt underline + latch. |
| `WindowBounds` | Persisted window-geometry model (pure Dart). |
| `requestUserAttention({kind})` | Portable request-attention primitive: dock bounce / taskbar flash / Wayland urgency, **never** a focus-steal. Call from the CXP inbound hook on an actionable message. Gracefully no-ops where unavailable. |
| `WindowAttentionRequester` / `NoopWindowAttentionRequester` | The swappable attention backend behind the settable `windowAttentionRequester` global — assign `NoopWindowAttentionRequester` to gate the feature behind a user setting. |

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
