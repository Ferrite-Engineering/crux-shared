// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action { openFile, zoomIn, quit }

void main() {
  const defaults = <_Action, ShortcutActivator>{
    _Action.openFile: SingleActivator(LogicalKeyboardKey.keyO, meta: true),
    _Action.zoomIn: SingleActivator(LogicalKeyboardKey.equal, meta: true),
    _Action.quit: SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
  };

  group('resolve', () {
    test('overlays a rebind onto the defaults', () {
      final resolved = KeyBindingResolver.resolve(defaults, {
        _Action.zoomIn: const KeyBinding(
          key: LogicalKeyboardKey.keyZ,
          modifiers: {KeyModifier.mod},
        ),
      });
      final z = resolved[_Action.zoomIn]! as SingleActivator;
      expect(z.trigger, LogicalKeyboardKey.keyZ);
      // Untouched entries remain.
      expect(resolved[_Action.openFile], defaults[_Action.openFile]);
    });

    test('a null diff removes the binding (explicit unbind)', () {
      final resolved = KeyBindingResolver.resolve(defaults, {
        _Action.quit: null,
      });
      expect(resolved.containsKey(_Action.quit), isFalse);
    });
  });

  group('diff', () {
    test('is empty when current equals defaults', () {
      expect(
        KeyBindingResolver.diff(_Action.values, defaults, defaults),
        isEmpty,
      );
    });

    test('captures rebinds and explicit unbinds', () {
      final current = Map<_Action, ShortcutActivator>.of(defaults)
        ..[_Action.zoomIn] = const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
        )
        ..remove(_Action.quit);

      final diffs = KeyBindingResolver.diff(_Action.values, current, defaults);
      expect(diffs.keys, containsAll([_Action.zoomIn, _Action.quit]));
      expect(diffs[_Action.zoomIn]!.key, LogicalKeyboardKey.keyZ);
      expect(diffs[_Action.quit], isNull);
      expect(diffs.containsKey(_Action.openFile), isFalse);
    });

    test('resolve(diff(current)) reproduces current', () {
      final current = Map<_Action, ShortcutActivator>.of(defaults)
        ..[_Action.openFile] = const SingleActivator(
          LogicalKeyboardKey.keyP,
          control: true,
        )
        ..remove(_Action.quit);
      final round = KeyBindingResolver.resolve(
        defaults,
        KeyBindingResolver.diff(_Action.values, current, defaults),
      );
      expect(
        KeyBindingResolver.activatorsEqual(
          round[_Action.openFile],
          current[_Action.openFile],
        ),
        isTrue,
      );
      expect(round.containsKey(_Action.quit), isFalse);
    });
  });

  group('activatorsEqual', () {
    test('two nulls are equal; one null is not', () {
      expect(KeyBindingResolver.activatorsEqual(null, null), isTrue);
      expect(
        KeyBindingResolver.activatorsEqual(
          null,
          const SingleActivator(LogicalKeyboardKey.keyA),
        ),
        isFalse,
      );
    });

    test('compares SingleActivators by trigger + modifiers', () {
      expect(
        KeyBindingResolver.activatorsEqual(
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
        ),
        isTrue,
      );
      expect(
        KeyBindingResolver.activatorsEqual(
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          const SingleActivator(LogicalKeyboardKey.keyA, control: true),
        ),
        isFalse,
      );
    });
  });
}
