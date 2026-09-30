# Changelog

## 0.0.2

- **Fix: Enter now executes the highlighted action.** The palette handled
  Enter only as a framework key event, but on every platform whose engine owns
  the focused field's text-input connection the keystroke is translated into a
  `TextInputAction.done` and never arrives as a `KeyDownEvent`. Keyboard
  execution was therefore dead in shipped desktop builds while widget tests —
  which deliver synthetic key events — stayed green. The query field's
  `onSubmitted` is now wired to the same handler, and a latch keeps a platform
  that delivers *both* signals from popping twice or dispatching twice.
- The ↑/↓/Enter/Escape handler now reports the keys as consumed (a `Focus`
  with an `onKeyEvent` returning `KeyEventResult.handled`, replacing the
  always-ignoring `KeyboardListener`). Arrow keys no longer move the query
  field's caret while moving the highlight, and Escape no longer bubbles on to
  the enclosing `ModalRoute` and pops a second route.
- No public API change.

## 0.0.1

- Initial extraction. `CommandPalette<T extends CruxAction>` generic widget
  lifted from WaveCrux open-core's `CommandPaletteDialog`. All
  wavecrux-specific bits (provider reads, hidden-action filter, L10N keys,
  TrackpadScrollListener wrapper) are now caller-supplied constructor
  parameters so the widget itself is product-agnostic.
