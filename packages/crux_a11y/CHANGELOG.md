# Changelog

## Unreleased

- **Added `CruxModalGate`, `CruxModalSurface` and `CruxScrollRegion`**, for a
  modal surface that cannot be a route: a licence agreement or consent
  disclosure mounted above the app's `Navigator`. Stacked over the app with
  only a `ModalBarrier`, such a surface stops the pointer but not the
  keyboard: focus stays on the app behind it, Tab walks controls the user
  cannot see (silent, because the barrier blocks their semantics), and Enter
  can press one of them.
  - `CruxModalGate(modal:, child:)` excludes `child` from focus and semantics
    while `modal` is non-null, so nothing behind the surface can be focused by
    Tab, pointer or app code. When `modal` becomes null and focus has fallen to
    nowhere, it moves focus to the first control in `child`, which is how a
    second gate nested in `child` receives focus when the first is answered.
    `child` keeps its element and state throughout.
  - `CruxModalSurface(label:, child:)` names the dialog (`scopesRoute`,
    `namesRoute`), keeps Tab and Shift+Tab cycling inside it, and consumes
    Escape so a surface that must be answered is not dismissed.
  - `CruxScrollRegion(semanticLabel:, builder:)` makes a block of scrolling
    text one named Tab stop that scrolls with the arrow keys, Page Up/Down,
    Home and End, and draws a focus outline. `excludeContentSemantics` makes
    the label the content, for a short passage.

## 0.2.0

- `crux_a11y_testing.dart` gains the focus walk: `walkFocus` presses Tab (or
  Shift+Tab) through a surface and returns a `FocusWalk` of `FocusStop`s —
  name, role, states and the named containers entered — modelled on what the
  desktop accessibility bridge hands to NVDA and VoiceOver (label as name,
  tooltip as description, role from flags, hint dropped).
  `expectCleanFocusWalk` fails on silent and nameless stops, one control
  under two names, a container repeating its control's name, unspeakable
  glyphs, off-window stops and a Tab order that never cycles.
  `expectFocusAnnounced` asserts focus landed somewhere named (launch, dialog
  open, after a close). `expectFocusWalkGolden` keeps a plain-text transcript
  per surface. `AnnouncementRecorder` captures `SemanticsService`
  announcements — and, correctly, not SnackBars, which the desktop bridges
  never announce.

## 0.1.0

- `CruxSlider` — a `Slider` hosted in its own `Overlay` so its value-indicator
  portal no longer serializes an unclaimed semantics node when the slider sits
  in a dialog or pushed route (flutter/flutter#190357).
- `crux_a11y_testing.dart` — `SemanticsOrphanGuard`, `SemanticsOrphanRecording`
  and `SemanticsOrphanTestBinding`: a widget-test harness that re-implements the
  desktop accessibility bridge's "every node must be claimed" invariant so an
  orphaned node fails `flutter test` instead of freezing a screen reader.
