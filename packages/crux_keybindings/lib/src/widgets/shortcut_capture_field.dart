// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/src/key_binding.dart';
import 'package:crux_keybindings/src/widgets/key_binding_editor_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An inline key-capture field: while focused it listens for the next chord and
/// reports it as a platform-neutral [KeyBinding].
///
/// Behavior:
/// - Pure modifier presses (Ctrl/Alt/Shift/Cmd) are ignored — the field waits
///   for a real trigger key while modifiers are held.
/// - Bare `Esc` cancels capture (so it stays a safe escape hatch). To bind
///   `Esc` itself, hold a modifier (e.g. `Shift+Esc`).
/// - Any other key (with whatever modifiers are down) is captured and reported
///   via [onCaptured]; the platform accelerator is normalized to
///   [KeyModifier.mod].
class ShortcutCaptureField extends StatefulWidget {
  /// Creates a capture field.
  const ShortcutCaptureField({
    required this.prompt,
    required this.metrics,
    required this.onCaptured,
    required this.onCancel,
    super.key,
  });

  /// Localized prompt shown while waiting for input.
  final String prompt;

  /// Host-supplied sizing.
  final KeyBindingEditorMetrics metrics;

  /// Called with the captured binding.
  final void Function(KeyBinding binding) onCaptured;

  /// Called when the user presses bare `Esc` (or focus is lost).
  final VoidCallback onCancel;

  @override
  State<ShortcutCaptureField> createState() => _ShortcutCaptureFieldState();
}

class _ShortcutCaptureFieldState extends State<ShortcutCaptureField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'ShortcutCaptureField');

  @override
  void initState() {
    super.initState();
    // `autofocus` alone is not enough: it only takes effect when nothing in
    // the scope is focused, and capture usually starts from a focused row.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (isModifierKey(key)) return KeyEventResult.handled;

    final keyboard = HardwareKeyboard.instance;

    // A Caps Lock physically remapped to Control (macOS System Settings >
    // Keyboard > Modifier Keys — a common HDL-engineer setup) surfaces here as
    // the `capsLock` logical key held down rather than a Control key, so
    // `isControlPressed` reads false and the chord would otherwise capture as a
    // bare trigger (e.g. Caps Lock+F → "F" instead of "⌃F"). Treat a *held*
    // Caps Lock as Control: a momentarily-held caps-lock key only happens under
    // such a remap. A genuine lock toggle registers as a `KeyboardLockMode`,
    // not a held key in `logicalKeysPressed`, so this never misfires for users
    // who simply have Caps Lock turned on.
    final control =
        keyboard.isControlPressed ||
        keyboard.logicalKeysPressed.contains(LogicalKeyboardKey.capsLock);
    final hasModifier =
        control || keyboard.isMetaPressed || keyboard.isAltPressed;

    // Bare Esc cancels; Esc + modifier is a real binding.
    if (key == LogicalKeyboardKey.escape &&
        !hasModifier &&
        !keyboard.isShiftPressed) {
      widget.onCancel();
      return KeyEventResult.handled;
    }

    widget.onCaptured(
      KeyBinding.fromCapture(
        key: key,
        control: control,
        meta: keyboard.isMetaPressed,
        alt: keyboard.isAltPressed,
        shift: keyboard.isShiftPressed,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One named node, so a screen reader says what the field is waiting for
    // when capture begins instead of a bare "grouping".
    return Semantics(
      container: true,
      label: widget.prompt,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        onFocusChange: (hasFocus) {
          // Losing focus (e.g. tapping elsewhere) ends capture cleanly.
          if (!hasFocus) widget.onCancel();
        },
        child: ExcludeSemantics(child: _visual(theme)),
      ),
    );
  }

  Widget _visual(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.primary, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard,
            size: widget.metrics.iconSize,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            widget.prompt,
            style: theme.textTheme.labelLarge?.copyWith(
              fontSize: widget.metrics.labelFontSize,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
