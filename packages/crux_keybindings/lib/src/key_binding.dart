// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A platform-neutral keyboard modifier.
///
/// The crucial distinction is [mod] vs [ctrl] / [meta]:
///
/// - [mod] is the **abstract primary accelerator**. It materializes to the
///   Command (meta) key on macOS / iOS and to the Control key on every other
///   platform. This is what lets a binding authored on a Mac (`Cmd+P`) work as
///   `Ctrl+P` on Windows / Linux and vice-versa.
/// - [ctrl] is the **literal Control key on every platform** — needed for
///   bindings like `Ctrl+Tab` that use Control even on macOS.
/// - [meta] is the literal Command / Windows / Super key (rare; the accelerator
///   role is [mod]).
/// - [alt] is Option on macOS, Alt elsewhere; [shift] is Shift.
enum KeyModifier {
  /// Abstract primary accelerator: Cmd on macOS/iOS, Ctrl elsewhere.
  mod,

  /// Literal Control on every platform (e.g. Ctrl+Tab).
  ctrl,

  /// Option on macOS, Alt elsewhere.
  alt,

  /// Shift.
  shift,

  /// Literal Command / Windows / Super (rare — prefer [mod]).
  meta;

  /// Parses a serialized modifier name, or `null` when unrecognized.
  static KeyModifier? fromName(String name) {
    for (final m in KeyModifier.values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// A platform-neutral, serializable keyboard shortcut: one trigger [key] plus a
/// set of [modifiers] drawn from [KeyModifier].
///
/// Unlike a Flutter [SingleActivator] — which bakes the concrete `control` /
/// `meta` choice in at construction and therefore cannot be shared across
/// platforms — a [KeyBinding] stays abstract until [materialize] resolves it
/// for the host platform. This is the on-disk / over-the-wire representation
/// used by the keymap codec, persistence, and the `.crux-keymap` share file.
///
/// Serialization is keyId-based ([LogicalKeyboardKey.keyId]), never
/// [LogicalKeyboardKey.keyLabel] (which is keyboard-layout dependent). Common
/// keys serialize to a readable token (`'o'`, `'f7'`, `'arrowLeft'`); anything
/// else falls back to `'key:<keyId>'`.
@immutable
class KeyBinding {
  /// Creates a binding for [key] with the given [modifiers].
  const KeyBinding({required this.key, this.modifiers = const {}});

  /// Builds a binding from a captured key event, normalizing the platform
  /// accelerator (Cmd on macOS/iOS, Ctrl elsewhere) to [KeyModifier.mod].
  ///
  /// [control] / [meta] / [alt] / [shift] are the live modifier-pressed states
  /// at capture time (typically from `HardwareKeyboard.instance`). [platform]
  /// defaults to [defaultTargetPlatform] and exists for testing.
  factory KeyBinding.fromCapture({
    required LogicalKeyboardKey key,
    required bool control,
    required bool meta,
    required bool alt,
    required bool shift,
    TargetPlatform? platform,
  }) {
    final isMac = _isMac(platform);
    final mods = <KeyModifier>{};
    if (isMac) {
      if (meta) mods.add(KeyModifier.mod);
      if (control) mods.add(KeyModifier.ctrl);
    } else {
      if (control) mods.add(KeyModifier.mod);
      if (meta) mods.add(KeyModifier.meta);
    }
    if (alt) mods.add(KeyModifier.alt);
    if (shift) mods.add(KeyModifier.shift);
    return KeyBinding(key: key, modifiers: mods);
  }

  /// Derives a neutral binding from an existing [SingleActivator], applying the
  /// same host-platform accelerator heuristic as `fromCapture`: the platform's
  /// primary modifier becomes [KeyModifier.mod]; the other primary modifier is
  /// treated as literal. Used to migrate `defaultBindings()` and to diff the
  /// active bindings for persistence. [platform] defaults to
  /// [defaultTargetPlatform].
  factory KeyBinding.fromActivator(
    SingleActivator activator, {
    TargetPlatform? platform,
  }) => KeyBinding.fromCapture(
    key: activator.trigger,
    control: activator.control,
    meta: activator.meta,
    alt: activator.alt,
    shift: activator.shift,
    platform: platform,
  );

  /// Decodes a binding from its JSON object form, or `null` when the payload is
  /// malformed (unknown key token, wrong shape). Unknown modifier names are
  /// dropped rather than failing the whole binding.
  static KeyBinding? fromJson(Object? json) {
    if (json is! Map) return null;
    final token = json['key'];
    if (token is! String) return null;
    final key = _keyFromToken(token);
    if (key == null) return null;
    final rawMods = json['mods'];
    final mods = <KeyModifier>{};
    if (rawMods is List) {
      for (final m in rawMods) {
        if (m is String) {
          final parsed = KeyModifier.fromName(m);
          if (parsed != null) mods.add(parsed);
        }
      }
    }
    return KeyBinding(key: key, modifiers: mods);
  }

  /// The trigger key.
  final LogicalKeyboardKey key;

  /// The modifier set. See [KeyModifier].
  final Set<KeyModifier> modifiers;

  /// Resolves this neutral binding to a concrete [SingleActivator] for the host
  /// platform: [KeyModifier.mod] → meta on macOS/iOS / control elsewhere;
  /// [KeyModifier.ctrl] → control; [KeyModifier.meta] → meta. [platform]
  /// defaults to [defaultTargetPlatform].
  SingleActivator materialize({TargetPlatform? platform}) {
    final isMac = _isMac(platform);
    final hasMod = modifiers.contains(KeyModifier.mod);
    return SingleActivator(
      key,
      control: modifiers.contains(KeyModifier.ctrl) || (hasMod && !isMac),
      meta: modifiers.contains(KeyModifier.meta) || (hasMod && isMac),
      alt: modifiers.contains(KeyModifier.alt),
      shift: modifiers.contains(KeyModifier.shift),
    );
  }

  /// Encodes this binding to a JSON object (`{'key': <token>, 'mods': [...]}`).
  Map<String, Object?> toJson() => {
    'key': _tokenForKey(key),
    // Stable, deterministic order so the same binding always serializes
    // identically (useful for diffing and committed share files).
    'mods': [
      for (final m in KeyModifier.values)
        if (modifiers.contains(m)) m.name,
    ],
  };

  @override
  bool operator ==(Object other) =>
      other is KeyBinding &&
      other.key == key &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(
    key,
    // Order-independent hash of the modifier set.
    Object.hashAllUnordered(modifiers),
  );

  @override
  String toString() {
    final mods = modifiers.map((m) => m.name).join(', ');
    return 'KeyBinding(${_tokenForKey(key)}, {$mods})';
  }

  static bool _isMac(TargetPlatform? platform) {
    final p = platform ?? defaultTargetPlatform;
    return p == TargetPlatform.macOS || p == TargetPlatform.iOS;
  }

  static String _tokenForKey(LogicalKeyboardKey key) =>
      _keyToToken[key] ?? 'key:${key.keyId}';

  static LogicalKeyboardKey? _keyFromToken(String token) {
    final named = _tokenToKey[token];
    if (named != null) return named;
    if (token.startsWith('key:')) {
      final id = int.tryParse(token.substring(4));
      if (id == null) return null;
      return LogicalKeyboardKey.findKeyByKeyId(id) ?? LogicalKeyboardKey(id);
    }
    return null;
  }
}

/// Readable, layout-independent string tokens for the keys WaveCrux binds or a
/// user is likely to capture. Anything outside this table serializes as
/// `'key:<keyId>'`, so the table is an optimization for human-readable share
/// files, not a constraint on which keys can be bound.
const Map<String, LogicalKeyboardKey> _tokenToKey = {
  // Letters.
  'a': LogicalKeyboardKey.keyA,
  'b': LogicalKeyboardKey.keyB,
  'c': LogicalKeyboardKey.keyC,
  'd': LogicalKeyboardKey.keyD,
  'e': LogicalKeyboardKey.keyE,
  'f': LogicalKeyboardKey.keyF,
  'g': LogicalKeyboardKey.keyG,
  'h': LogicalKeyboardKey.keyH,
  'i': LogicalKeyboardKey.keyI,
  'j': LogicalKeyboardKey.keyJ,
  'k': LogicalKeyboardKey.keyK,
  'l': LogicalKeyboardKey.keyL,
  'm': LogicalKeyboardKey.keyM,
  'n': LogicalKeyboardKey.keyN,
  'o': LogicalKeyboardKey.keyO,
  'p': LogicalKeyboardKey.keyP,
  'q': LogicalKeyboardKey.keyQ,
  'r': LogicalKeyboardKey.keyR,
  's': LogicalKeyboardKey.keyS,
  't': LogicalKeyboardKey.keyT,
  'u': LogicalKeyboardKey.keyU,
  'v': LogicalKeyboardKey.keyV,
  'w': LogicalKeyboardKey.keyW,
  'x': LogicalKeyboardKey.keyX,
  'y': LogicalKeyboardKey.keyY,
  'z': LogicalKeyboardKey.keyZ,
  // Digits.
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
  // Function keys.
  'f1': LogicalKeyboardKey.f1,
  'f2': LogicalKeyboardKey.f2,
  'f3': LogicalKeyboardKey.f3,
  'f4': LogicalKeyboardKey.f4,
  'f5': LogicalKeyboardKey.f5,
  'f6': LogicalKeyboardKey.f6,
  'f7': LogicalKeyboardKey.f7,
  'f8': LogicalKeyboardKey.f8,
  'f9': LogicalKeyboardKey.f9,
  'f10': LogicalKeyboardKey.f10,
  'f11': LogicalKeyboardKey.f11,
  'f12': LogicalKeyboardKey.f12,
  // Punctuation / symbols.
  'comma': LogicalKeyboardKey.comma,
  'period': LogicalKeyboardKey.period,
  'slash': LogicalKeyboardKey.slash,
  'backslash': LogicalKeyboardKey.backslash,
  'bracketLeft': LogicalKeyboardKey.bracketLeft,
  'bracketRight': LogicalKeyboardKey.bracketRight,
  'semicolon': LogicalKeyboardKey.semicolon,
  'quote': LogicalKeyboardKey.quoteSingle,
  'backquote': LogicalKeyboardKey.backquote,
  'equal': LogicalKeyboardKey.equal,
  'minus': LogicalKeyboardKey.minus,
  // Whitespace / editing.
  'space': LogicalKeyboardKey.space,
  'enter': LogicalKeyboardKey.enter,
  'tab': LogicalKeyboardKey.tab,
  'escape': LogicalKeyboardKey.escape,
  'backspace': LogicalKeyboardKey.backspace,
  'delete': LogicalKeyboardKey.delete,
  'insert': LogicalKeyboardKey.insert,
  // Navigation.
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'pageUp': LogicalKeyboardKey.pageUp,
  'pageDown': LogicalKeyboardKey.pageDown,
  'arrowLeft': LogicalKeyboardKey.arrowLeft,
  'arrowRight': LogicalKeyboardKey.arrowRight,
  'arrowUp': LogicalKeyboardKey.arrowUp,
  'arrowDown': LogicalKeyboardKey.arrowDown,
};

/// Inverse of [_tokenToKey], built once.
final Map<LogicalKeyboardKey, String> _keyToToken = {
  for (final entry in _tokenToKey.entries) entry.value: entry.key,
};

/// Whether [key] is a standalone modifier key (Control / Shift / Alt / Meta /
/// CapsLock / Fn). A modifier key is never captured as a shortcut *trigger* —
/// the capture field waits for a real key while modifiers are held.
bool isModifierKey(LogicalKeyboardKey key) => _modifierKeys.contains(key);

// Not const: LogicalKeyboardKey overrides ==/hashCode, so it can't be a const
// set element (it can be a const map *value*, hence _tokenToKey is const).
final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};
