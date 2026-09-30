# crux_keybindings

Cross-suite customizable, shareable keyboard-binding infrastructure for the EDACrux suite.

The domain-neutral core of a user-customizable keyboard-shortcut system, generic over each product's `CruxAction` enum. Each of the four products keeps its own action enum, `defaultBindings()`, `Intent` subclass, and localized labels, and composes the pieces here for the model, serialization, persistence math, conflict detection, and label rendering.

## What's in the box

- **`KeyBinding` / `KeyModifier` / `isModifierKey`** — a platform-neutral binding model. The primary accelerator is stored abstractly as `KeyModifier.mod` and `materialize()`s to Command on macOS/iOS and Control everywhere else; `KeyModifier.ctrl` stays literal Control on every platform (for `Ctrl+Tab`-style bindings); Option↔Alt. Serialization is keyId-based (never the layout-dependent key label), with readable tokens for common keys.
- **`KeymapCodec<A extends CruxAction>`** — a versioned JSON codec storing **diffs from default** keyed by `CruxAction.id`, with a `null` value as an explicit-unbind sentinel. Used for both `SharedPreferences` persistence and `.crux-keymap` share files. Tolerant of unknown action ids and malformed bindings (skipped, not fatal), so keymaps survive across releases and products.
- **`KeyBindingResolver`** — pure helpers: `resolve(defaults, diffs)` overlays a persisted diff map onto the product defaults; `diff(actions, current, defaults)` computes the diff to persist/export; `activatorsEqual(...)`. These keep a product's binding notifier trivial.
- **`findShortcutConflicts<A>` / `activatorSignature`** — live conflict detection for an editor UI, with a caller-supplied `intentionalShadows` allow-list so by-design keyboard shadows aren't flagged.
- **`formatShortcutLabel`** — platform-aware human-readable chord labels (`⌘⇧P` on macOS, `Ctrl+Shift+P` elsewhere).

## What's deliberately not here (yet)

This package is the **neutral core**. The editor *widgets* (key-capture field, per-action row, settings section) and the Riverpod notifier/persistence store currently still live in the consuming product while the cross-suite seam for sizing (the product's mobile-metrics) and persistence is finalized. They migrate here in a later increment; the core above is stable and is what each product consumes first.

## Canonical wiring (per product)

```dart
// Product keeps its own enum + defaults + Intent + labels.
final codec = KeymapCodec<MyAction>(actions: MyAction.values, schema: 'myapp.keymap');

// Notifier build(): overlay persisted diffs onto defaults.
final resolved = KeyBindingResolver.resolve(defaultBindings(), persistedDiffs);

// On change: compute + persist diffs; export writes codec.encodeToString(diffs).
final diffs = KeyBindingResolver.diff(MyAction.values, current, defaultBindings());

// Editor: warn on collisions, excluding intentional shadows.
final conflicts = findShortcutConflicts(resolved, intentionalShadows: kMyShadows);

// Capture a chord from a key event into a neutral binding.
final binding = KeyBinding.fromCapture(
  key: event.logicalKey,
  control: keyboard.isControlPressed,
  meta: keyboard.isMetaPressed,
  alt: keyboard.isAltPressed,
  shift: keyboard.isShiftPressed,
);
controller.setBinding(action, binding.materialize());
```

See WaveCrux's `lib/core/shortcuts/` for the reference adopter.
