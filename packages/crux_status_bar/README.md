# crux_status_bar

Cross-suite bottom **status bar** for the EDACrux suite.

Every product — WaveCrux, NetCrux, LintCrux, SimCrux — mounts `CruxStatusBar`
at the window bottom so the four apps share one bottom-of-window chrome: one
fixed height, one background/border treatment, one typography baseline, all
theme-aware (light/dark). WaveCrux is the canonical reference for the look.

The surface and the baseline text follow the active theme's
`statusBar.background` and `statusBar.foreground` chrome tokens (see
`crux_theme`'s `CruxChromeColors`), falling back to
`surfaceContainerHighest` and `onSurface` at 75 %. A host that styles its own
segments should start from `CruxStatusBar.resolveTextStyle(context)` so the
theme's text colour reaches them too.

The package hard-codes **no** per-app content. The host contributes widgets
into ordered slots, laid out left → right:

- `leading` — flush-left widgets before the segment strip (e.g. a panel
  chevron).
- `segments` — metric segments joined by a `|` divider in a horizontally
  scrollable, left-aligned region. Use `CruxStatusSegment` for plain text.
- `segmentsTrailing` — fixed widgets right after the (scrolling) strip.
- `center` — an optional widget pinned to the geometric center.
- `trailing` — right-pinned widgets, including the open-core/Pro extension
  slot generalized from WaveCrux's `statusBarTrailingWidgetsProvider`.

```dart
CruxStatusBar(
  segments: [
    CruxStatusSegment('File: cpu.v'),
    CruxStatusSegment('Top: cpu'),
    CruxStatusSegment('42 cells'),
  ],
  trailing: ref.watch(statusBarTrailingWidgetsProvider),
)
```
