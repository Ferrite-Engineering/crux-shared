// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
// isModifierKey is intentionally not exported from the barrel (see the hide
// clause there); the test reaches the src library directly.
import 'package:crux_keybindings/src/key_binding.dart' show isModifierKey;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyBinding.materialize', () {
    test('mod resolves to meta on macOS and control elsewhere', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.keyP,
        modifiers: {KeyModifier.mod, KeyModifier.shift},
      );

      final mac = binding.materialize(platform: TargetPlatform.macOS);
      expect(mac.meta, isTrue);
      expect(mac.control, isFalse);
      expect(mac.shift, isTrue);
      expect(mac.trigger, LogicalKeyboardKey.keyP);

      final linux = binding.materialize(platform: TargetPlatform.linux);
      expect(linux.control, isTrue);
      expect(linux.meta, isFalse);
      expect(linux.shift, isTrue);
    });

    test('mod resolves to meta on iOS (Magic Keyboard parity)', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.keyO,
        modifiers: {KeyModifier.mod},
      );
      final ios = binding.materialize(platform: TargetPlatform.iOS);
      expect(ios.meta, isTrue);
      expect(ios.control, isFalse);
    });

    test('literal ctrl stays control on every platform (Ctrl+Tab)', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.tab,
        modifiers: {KeyModifier.ctrl},
      );
      for (final platform in TargetPlatform.values) {
        final a = binding.materialize(platform: platform);
        expect(a.control, isTrue, reason: '$platform');
        expect(a.meta, isFalse, reason: '$platform');
      }
    });

    test('alt maps straight through (Option on macOS, Alt elsewhere)', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.keyG,
        modifiers: {KeyModifier.mod, KeyModifier.alt},
      );
      expect(binding.materialize(platform: TargetPlatform.macOS).alt, isTrue);
      expect(binding.materialize(platform: TargetPlatform.windows).alt, isTrue);
    });

    test('bare key has no modifiers', () {
      const binding = KeyBinding(key: LogicalKeyboardKey.keyW);
      final a = binding.materialize(platform: TargetPlatform.linux);
      expect(a.control, isFalse);
      expect(a.meta, isFalse);
      expect(a.alt, isFalse);
      expect(a.shift, isFalse);
    });
  });

  group('KeyBinding.fromCapture', () {
    test('normalizes the platform accelerator to mod', () {
      final mac = KeyBinding.fromCapture(
        key: LogicalKeyboardKey.keyP,
        control: false,
        meta: true,
        alt: false,
        shift: true,
        platform: TargetPlatform.macOS,
      );
      expect(mac.modifiers, {KeyModifier.mod, KeyModifier.shift});

      final win = KeyBinding.fromCapture(
        key: LogicalKeyboardKey.keyP,
        control: true,
        meta: false,
        alt: false,
        shift: true,
        platform: TargetPlatform.windows,
      );
      expect(win.modifiers, {KeyModifier.mod, KeyModifier.shift});
    });

    test('control captured on macOS is literal ctrl, not mod', () {
      final mac = KeyBinding.fromCapture(
        key: LogicalKeyboardKey.tab,
        control: true,
        meta: false,
        alt: false,
        shift: false,
        platform: TargetPlatform.macOS,
      );
      expect(mac.modifiers, {KeyModifier.ctrl});
    });
  });

  group('cross-platform round-trip', () {
    test('a mac-authored binding materializes correctly on Windows/Linux', () {
      // User on macOS binds Cmd+Shift+P.
      final captured = KeyBinding.fromCapture(
        key: LogicalKeyboardKey.keyP,
        control: false,
        meta: true,
        alt: false,
        shift: true,
        platform: TargetPlatform.macOS,
      );
      // Serialized, shared, decoded on another machine.
      final shared = KeyBinding.fromJson(captured.toJson())!;
      final onLinux = shared.materialize(platform: TargetPlatform.linux);
      expect(onLinux.control, isTrue);
      expect(onLinux.meta, isFalse);
      expect(onLinux.shift, isTrue);
      expect(onLinux.trigger, LogicalKeyboardKey.keyP);
    });
  });

  group('fromActivator', () {
    test('round-trips a default-style activator through the host platform', () {
      const activator = SingleActivator(
        LogicalKeyboardKey.keyS,
        meta: true,
        shift: true,
      );
      final binding = KeyBinding.fromActivator(
        activator,
        platform: TargetPlatform.macOS,
      );
      expect(binding.modifiers, {KeyModifier.mod, KeyModifier.shift});
      final back = binding.materialize(platform: TargetPlatform.macOS);
      expect(back.meta, isTrue);
      expect(back.shift, isTrue);
      expect(back.trigger, LogicalKeyboardKey.keyS);
    });
  });

  group('JSON', () {
    test('round-trips readable tokens for common keys', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.keyO,
        modifiers: {KeyModifier.mod},
      );
      final json = binding.toJson();
      expect(json['key'], 'o');
      expect(json['mods'], ['mod']);
      expect(KeyBinding.fromJson(json), binding);
    });

    test('mods serialize in deterministic enum order', () {
      const binding = KeyBinding(
        key: LogicalKeyboardKey.keyG,
        modifiers: {KeyModifier.shift, KeyModifier.mod, KeyModifier.alt},
      );
      expect(binding.toJson()['mods'], ['mod', 'alt', 'shift']);
    });

    test('named keys round-trip (arrows, f-keys, punctuation)', () {
      for (final key in const [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.comma,
        LogicalKeyboardKey.backslash,
        LogicalKeyboardKey.escape,
      ]) {
        final binding = KeyBinding(key: key);
        expect(KeyBinding.fromJson(binding.toJson())!.key, key);
      }
    });

    test('uncatalogued keys fall back to a keyId token and round-trip', () {
      const binding = KeyBinding(key: LogicalKeyboardKey.audioVolumeUp);
      final token = binding.toJson()['key']! as String;
      expect(token, startsWith('key:'));
      expect(
        KeyBinding.fromJson(binding.toJson())!.key,
        LogicalKeyboardKey.audioVolumeUp,
      );
    });

    test('unknown modifier names are dropped, not fatal', () {
      final binding = KeyBinding.fromJson({
        'key': 'p',
        'mods': ['mod', 'hyper', 42],
      });
      expect(binding, isNotNull);
      expect(binding!.modifiers, {KeyModifier.mod});
    });

    test('malformed payloads decode to null', () {
      expect(KeyBinding.fromJson(null), isNull);
      expect(KeyBinding.fromJson('nope'), isNull);
      expect(KeyBinding.fromJson({'mods': <String>[]}), isNull);
      expect(KeyBinding.fromJson({'key': 123}), isNull);
      expect(KeyBinding.fromJson({'key': 'not-a-real-token'}), isNull);
    });
  });

  group('equality', () {
    test('equal regardless of modifier insertion order', () {
      const a = KeyBinding(
        key: LogicalKeyboardKey.keyP,
        modifiers: {KeyModifier.mod, KeyModifier.shift},
      );
      const b = KeyBinding(
        key: LogicalKeyboardKey.keyP,
        modifiers: {KeyModifier.shift, KeyModifier.mod},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs on key or modifier set', () {
      const base = KeyBinding(
        key: LogicalKeyboardKey.keyP,
        modifiers: {KeyModifier.mod},
      );
      expect(
        base ==
            const KeyBinding(
              key: LogicalKeyboardKey.keyO,
              modifiers: {KeyModifier.mod},
            ),
        isFalse,
      );
      expect(
        base == const KeyBinding(key: LogicalKeyboardKey.keyP),
        isFalse,
      );
    });
  });

  group('isModifierKey', () {
    test('true for standalone modifier keys', () {
      for (final key in const [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.capsLock,
      ]) {
        expect(isModifierKey(key), isTrue, reason: '$key');
      }
    });

    test('false for real trigger keys', () {
      for (final key in const [
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.f7,
      ]) {
        expect(isModifierKey(key), isFalse, reason: '$key');
      }
    });
  });

  test('default-target-platform path works without an explicit platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const binding = KeyBinding(
      key: LogicalKeyboardKey.keyP,
      modifiers: {KeyModifier.mod},
    );
    expect(binding.materialize().meta, isTrue);
  });
}
