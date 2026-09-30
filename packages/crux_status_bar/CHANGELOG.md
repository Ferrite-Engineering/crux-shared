# Changelog

## Unreleased

- The bar's surface and baseline text follow the theme's
  `statusBar.background` and `statusBar.foreground` chrome tokens, read from
  `crux_theme`'s `CruxChromeColors`; the defaults are unchanged. An explicit
  `backgroundColor` or `textStyle` still wins. Depends on `crux_theme`.

## 0.1.0

- Initial release. `CruxStatusBar` — the cross-suite bottom status bar:
  a left-aligned, fixed-height (`kCruxStatusBarHeight`, 24 dp),
  theme-aware bar with the canonical WaveCrux look (monospace
  `kCruxStatusBarFontSize`, `surfaceContainerHighest` background, 0.5 dp
  `dividerColor` top border, clamped text scaling).
- Host-contributed slots — `leading`, `segments` (divider-joined, scrollable,
  left-aligned), `segmentsTrailing`, an optional geometrically-centered
  `center`, and `trailing` — generalize WaveCrux's
  `statusBarTrailingWidgetsProvider` extension pattern; the package hard-codes
  no per-app content.
- `CruxStatusSegment` — a plain-text segment that inherits the bar's baseline
  typography via `CruxStatusBar.resolveTextStyle`.
