# Changelog

This file was backfilled during the CS documentation sweep, so the entry below
describes the package's surface as of 0.1.0 rather than reconstructing the
increments that built it. Changes from here on get their own entries.

## 0.3.0

- The editor is operable by keyboard and screen reader. Every row is one
  focus stop announced as a button named "action, binding"; the list holds a
  single Tab stop, Up / Down / Home / End move between rows, Enter or Space
  starts capture, Delete or Backspace unbinds, Shift+Delete resets. Focus
  returns to the row when capture ends. The row's icon buttons remain for
  the pointer and leave the Tab order.
- `KeyBindingsAccessibilityStrings` (optional, via
  `KeyBindingsEditor.accessibilityStrings`): the keyboard hint, spoken once
  on entering the list and shown under the description, and the spoken form
  of "not bound".
- `formatShortcutSpokenLabel` formats a binding in words
  (`Control+Shift+Left Arrow`); the glyph badge from `formatShortcutLabel` is
  read as question marks by desktop speech engines.
- `ShortcutCaptureField` announces its prompt and takes focus even when
  capture starts from a focused row.

## 0.2.0

- **BREAKING:** `KeyBindingsEditor` now requires a `categoryCardBuilder`. The
  editor no longer ships its own card chrome; the host supplies it (typically
  a `CruxSettingsCategory` from `crux_settings_ui`) so the editor drops into
  each product's settings surface without a forked card style. Migration: pass
  a `categoryCardBuilder` that wraps the section in your settings card.
- `findShortcutConflicts` gained deterministic conflict precedence and
  asymmetric editor warnings, so two bindings that shadow each other report a
  stable primary/secondary rather than order-dependent noise.
- Fix: a macOS Caps Lock → Control remap is now captured as Control rather
  than as the Caps Lock key.
- Fix: `KeyBindingsStore.load()` now lets `KeymapSchemaVersionException`
  propagate instead of swallowing it to an empty map. A keymap written by a
  newer build previously read as "no customizations", and the next save wiped
  the user's real bindings; the refusal now surfaces so the host can skip that
  destructive save.

## 0.1.0

- Initial extraction from WaveCrux open-core. The customizable, shareable
  keyboard-shortcut system, generic over each product's `CruxAction` enum.
- Model: `KeyBinding` / `KeyModifier`, platform-neutral by construction — the
  primary accelerator `mod` materializes to Cmd on macOS/iOS and Ctrl
  elsewhere, `option` and `alt` are the same modifier, and a literal `ctrl`
  stays Ctrl on every platform. Serialization is keyId-based.
- `KeymapCodec` — versioned JSON codec storing diffs-from-default with an
  explicit-unbind sentinel, used both for persistence and for `.crux-keymap`
  share files. A schema version it does not recognize raises
  `KeymapSchemaVersionException` rather than degrading, because a keymap is a
  user-authored artifact that may arrive from a newer build.
- `KeyBindingResolver` — pure helpers to overlay diffs onto defaults and diff
  the active bindings back, so each product's notifier stays trivial.
- `findShortcutConflicts` / `activatorSignature` — live conflict detection
  with a caller-supplied intentional-shadow allow-list.
- `formatShortcutLabel` — platform-aware human-readable chord labels.
- `KeyBindingsStore` — `SharedPreferences`-backed persistence. Every operation
  is best-effort: a missing platform plugin, corrupt JSON or an I/O error
  resolves to "no customizations" rather than crashing the app.
- Editor widgets: `KeyBindingsEditor`, `KeyBindingRow`,
  `KeyBindingsEditorStrings` and `KeyBindingEditorMetrics` (the sizing seam
  that replaces each product's own metrics type). `ShortcutCaptureField` is an
  implementation detail of the editor and is not exported.
- **Not** included, by design: Riverpod. The package contains none. Each
  product keeps its own notifier, action enum, `defaultBindings()`, `Intent`
  subclass and localized labels.
