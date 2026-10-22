## Unreleased

- **Export namespace narrowed by 3 symbols.** `cruxEntriesForGroups`, `displayMenuShortcut`, `nativeMenuShortcut` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- Removed `CruxTopMenu`, which nothing referenced.

## 0.1.0

- Initial extraction of the desktop menu bar from the four product
  `DesktopMenuBar` widgets into one shared, generic implementation.
- `CruxDesktopMenuBar<A>` renders a declarative `CruxMenuLayout<A>` as the
  native macOS `PlatformMenuBar` or the in-window `MnemonicMenuBar` on
  Windows/Linux.
- Platform-idiomatic placement of About / Check for Updates / Settings / Quit,
  the standard macOS application-menu tail, and a macOS Window menu.
- `nativeMenuShortcut` guard keeps bare typing and navigation keys out of macOS
  native key equivalents; `displayMenuShortcut` keeps showing them on
  Windows/Linux where the accelerator label is display-only.
