# Changelog

## Unreleased

- **`CruxRoutedContent`: the strips above the `Navigator` are heard.** Every route the `Navigator` shows, a page included, puts a modal barrier under its content, and the barrier blocks the semantics of everything painted before it in the same container: the window's, for a strip a product draws in `MaterialApp.builder`. Tab reached the strip's buttons but each one was a silent stop. Wrapping the builder's `child` in `CruxRoutedContent` gives the routed content its own semantics container, so the barrier blocks only what lies under it. The router's `Navigator` already hands Tab to the window at a route's edges, so Tab and Shift+Tab run from the page through the strips and back; a dialog still keeps Tab inside itself.

- **Export namespace narrowed by 4 symbols.** `cruxFocusRingWidth`, `kCruxSwitchThumbSize`, `kCruxSwitchTrackHeight`, `kCruxSwitchTrackWidth` left the barrel. No product build and no other package referenced them, so none was deprecated first; the declarations are unchanged and stay under `lib/src/`.

- **`CruxPressable` / `CruxPressState` / `CruxFocusRing`: the interaction
  core and focus ring of the owned desktop controls.** `CruxPressable` is a
  Tab stop that a click, Space or Enter activates, reporting pressed,
  hovered, keyboard-focused and enabled to its builder, with one button
  semantics node (label, value, selected and expanded states) and the
  drawn content excluded. `CruxFocusRing` is the one ring: 1.5 px (2.5 px
  in high contrast, `cruxFocusRingWidth`) primary, 2 px outside the control
  or inside it with `inset`, painted in the foreground so it never moves
  layout. `CruxFocusRingPainter` and `kCruxFocusRingGap` are public for the
  theme's ring shapes and for tests.

- **`CruxSwitch`: the desktop switch.** A 32×18 track with a 14 px thumb,
  drawn at size rather than a scaled Material `Switch`. One Tab stop that
  Space and Enter toggle, one semantics node with the toggled state and
  `semanticLabel`, hover, a disabled state, and an always-visible focus ring
  (1.5 px, 2.5 px in high contrast).

- **`CruxRegionHintHost` and `CruxRegionHint`: a region's content can
  describe the region without renaming it.** A host builds its region
  semantics with `cruxRegionHintSemantics`; a `CruxRegionHint` below it
  supplies the description while mounted (the most recently mounted wins),
  one frame after it mounts. The description is set as the semantics hint
  and as the tooltip, because the desktop accessibility bridge drops the
  hint and exposes the tooltip as the accessible description.
- **The focus walk reports a container's description on entry.** An entered
  container with a semantics tooltip renders as `<name> <role> —
  <description>` instead of `<name> <role>`, so a transcript records what a
  screen reader reads on entering it. Transcripts that enter a region holding
  a `CruxPanelEmptyState` change.

- **`CruxScrollRegion`'s focus ring clears the text.** It sat flush against
  the content with square corners, and since it paints in front of the
  content the stroke landed on the glyphs, so the first-launch dialogs' text
  read as compressed and the ring as a selection. The content is now inset
  8 px horizontally and 6 px vertically inside a 4 px-radius ring. The inset
  is unconditional and the stroke is still always 2 px (transparent when
  unfocused), so focus never reflows the text.
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
