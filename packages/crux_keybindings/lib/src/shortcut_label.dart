// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Formats a [ShortcutActivator] as a human-readable badge string for display
/// in the command palette, settings screen, and overflow action menu.
///
/// Returns [emptyLabel] for null activators or non-[SingleActivator] types.
/// On macOS, modifiers render as glyphs (⌃ ⌥ ⌘ ⇧) joined with no separator;
/// on other platforms, modifiers render as words (Ctrl, Alt, Win, Shift) joined
/// with `+` separators.
String formatShortcutLabel(
  ShortcutActivator? activator, {
  String emptyLabel = '',
}) {
  if (activator == null) return emptyLabel;
  if (activator is! SingleActivator) return emptyLabel;
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  final parts = <String>[];
  if (activator.control) parts.add(isMac ? '⌃' : 'Ctrl');
  if (activator.alt) parts.add(isMac ? '⌥' : 'Alt');
  if (activator.meta) parts.add(isMac ? '⌘' : 'Win');
  if (activator.shift) parts.add(isMac ? '⇧' : 'Shift');
  parts.add(_keyLabel(activator.trigger));
  return isMac ? parts.join() : parts.join('+');
}

/// Formats a [ShortcutActivator] in words a screen reader speaks correctly
/// on every platform: `Control+Shift+O`, `Command+Left Arrow`.
///
/// [formatShortcutLabel] is for the eye. Its macOS modifier glyphs and its
/// arrow and minus glyphs are read as a question mark, or not at all, by
/// desktop speech engines, so an accessible name must never be built from
/// it. Returns [emptyLabel] for null activators or non-[SingleActivator]
/// types.
String formatShortcutSpokenLabel(
  ShortcutActivator? activator, {
  String emptyLabel = '',
}) {
  if (activator is! SingleActivator) return emptyLabel;
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  final alt = isMac ? 'Option' : 'Alt';
  final meta = isMac ? 'Command' : 'Windows';
  return <String>[
    if (activator.control) 'Control',
    if (activator.alt) alt,
    if (activator.meta) meta,
    if (activator.shift) 'Shift',
    _spokenKeyLabel(activator.trigger),
  ].join('+');
}

final Map<LogicalKeyboardKey, String> _spokenKeyOverrides = {
  LogicalKeyboardKey.comma: 'Comma',
  LogicalKeyboardKey.period: 'Period',
  LogicalKeyboardKey.slash: 'Slash',
  LogicalKeyboardKey.backslash: 'Backslash',
  LogicalKeyboardKey.equal: 'Equals',
  LogicalKeyboardKey.minus: 'Minus',
  LogicalKeyboardKey.bracketLeft: 'Left Bracket',
  LogicalKeyboardKey.bracketRight: 'Right Bracket',
  LogicalKeyboardKey.semicolon: 'Semicolon',
  LogicalKeyboardKey.quote: 'Apostrophe',
  LogicalKeyboardKey.backquote: 'Grave Accent',
  LogicalKeyboardKey.arrowLeft: 'Left Arrow',
  LogicalKeyboardKey.arrowRight: 'Right Arrow',
  LogicalKeyboardKey.arrowUp: 'Up Arrow',
  LogicalKeyboardKey.arrowDown: 'Down Arrow',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.space: 'Space',
};

String _spokenKeyLabel(LogicalKeyboardKey key) {
  final override = _spokenKeyOverrides[key];
  if (override != null) return override;
  final name = key.keyLabel;
  if (name.isNotEmpty) return name;
  return key.debugName ?? 'Unknown key';
}

/// Punctuation and navigation keys whose [LogicalKeyboardKey.keyLabel] is
/// either empty or unreadable in a shortcut badge.
///
/// Cannot be `const` because [LogicalKeyboardKey] overrides `==`/`hashCode`,
/// so the map is built once at library-initialization time instead. This
/// matters: [formatShortcutLabel] runs once per visible row of the command
/// palette, the overflow action menu, and the key-bindings editor, all of
/// which rebuild on every keystroke.
final Map<LogicalKeyboardKey, String> _keyLabelOverrides = {
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.minus: '−',
  LogicalKeyboardKey.arrowLeft: '←',
  LogicalKeyboardKey.arrowRight: '→',
  LogicalKeyboardKey.arrowUp: '↑',
  LogicalKeyboardKey.arrowDown: '↓',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.escape: 'Esc',
};

String _keyLabel(LogicalKeyboardKey key) {
  final override = _keyLabelOverrides[key];
  if (override != null) return override;
  final name = key.keyLabel;
  return name.isNotEmpty ? name : '?';
}
