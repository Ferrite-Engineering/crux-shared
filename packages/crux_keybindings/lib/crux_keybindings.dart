// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite customizable keyboard-binding infrastructure for the EDACrux
/// suite.
///
/// Provides the domain-neutral, product-agnostic core of a user-customizable,
/// shareable keyboard-shortcut system, generic over each product's
/// `CruxAction` enum:
///
/// - `KeyBinding` / `KeyModifier` / `isModifierKey` — a platform-neutral
///   binding model whose primary accelerator (`mod`) materializes to Cmd on
///   macOS/iOS and Ctrl elsewhere (Option↔Alt; literal `ctrl` stays Ctrl),
///   with keyId-based serialization.
/// - `KeymapCodec` — a versioned JSON codec storing diffs-from-default (with an
///   explicit-unbind sentinel) for persistence and `.crux-keymap` share files.
/// - `KeyBindingResolver` — pure helpers to overlay diffs onto defaults and to
///   diff the active bindings back, so a product's notifier stays trivial.
/// - `findShortcutConflicts` / `activatorSignature` — live conflict detection
///   with a caller-supplied intentional-shadow allow-list.
/// - `formatShortcutLabel` — platform-aware human-readable chord labels.
///
/// Each product supplies its own action enum, `defaultBindings()`, `Intent`
/// subclass, and localized labels. See the package README for the canonical
/// wiring pattern.
library;

// `isModifierKey` is hidden deliberately: its only non-test caller is
// `ShortcutCaptureField`, which this barrel already declines to export as an
// implementation detail of `KeyBindingsEditor` (see the note below). Exporting
// a helper for a widget we do not export is surface with no reachable use —
// unlike the rest of this file, none of which appears in an exported
// signature or is thrown by a public method.
export 'src/key_binding.dart' hide isModifierKey;
export 'src/key_binding_resolver.dart';
export 'src/key_bindings_store.dart';
export 'src/keymap_codec.dart';
export 'src/shortcut_conflicts.dart';
export 'src/shortcut_label.dart';
export 'src/widgets/key_binding_editor_metrics.dart';
export 'src/widgets/key_binding_row.dart';
export 'src/widgets/key_bindings_editor.dart';
export 'src/widgets/key_bindings_editor_strings.dart';

// `ShortcutCaptureField` is an implementation detail of `KeyBindingsEditor`
// and is deliberately not part of the public surface.
