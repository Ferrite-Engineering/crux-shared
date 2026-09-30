// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The function keys, the only trigger a *bare* (unmodified) native menu key
/// equivalent may use. F-keys are not typing keys and are not consumed by text
/// fields, so publishing them to the OS menu is safe.
///
/// Not `const`: `LogicalKeyboardKey` overrides `==`, which a constant set may
/// not contain.
final Set<LogicalKeyboardKey> _functionKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
};

/// Maps [activator] to a key equivalent safe to publish to the **native macOS
/// menu**, or null when it must not be published.
///
/// A `NSMenuItem` key equivalent is matched by the OS *before* the keystroke
/// reaches the focused view — including while a text field has focus. So a
/// bare-trigger accelerator installed in the native menu silently steals that
/// keystroke from typing: a bare `[` stops you typing a bracket in a search
/// box, a bare `Escape` stops Escape dismissing a dialog, bare `Home`/`End`
/// stop caret navigation, and a bare letter stops you typing that letter.
///
/// The rule is therefore: an accelerator with **no Ctrl / Cmd / Alt modifier**
/// is published only if its trigger is a function key. Everything else is
/// dropped — the action still fires through the Flutter `Shortcuts` layer
/// (which is text-input aware), the menu simply shows no accelerator next to
/// it. Shift alone does not count as a modifier: `⇧M` is still a typing key.
///
/// Only [SingleActivator] is understood; any other activator type returns null.
MenuSerializableShortcut? nativeMenuShortcut(ShortcutActivator? activator) {
  if (activator is! SingleActivator) return null;
  final hasPrimaryModifier =
      activator.control || activator.meta || activator.alt;
  if (hasPrimaryModifier) return activator;
  return _functionKeys.contains(activator.trigger) ? activator : null;
}

/// Maps [activator] to a shortcut for the **Windows / Linux in-window** menu.
///
/// `MenuItemButton.shortcut` there is a display-only label — it renders the
/// accelerator text and binds nothing, so the key handling stays entirely with
/// the app's `Shortcuts` / `Actions` layer and there is no double-fire and no
/// typing hijack. Bare triggers are therefore kept: a Windows user should see
/// `Esc` next to "Cancel Run" and `F5` next to "Run".
///
/// Only [SingleActivator] is understood; any other activator type returns null.
MenuSerializableShortcut? displayMenuShortcut(ShortcutActivator? activator) =>
    activator is SingleActivator ? activator : null;
