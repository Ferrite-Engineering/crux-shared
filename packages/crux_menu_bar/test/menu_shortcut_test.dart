// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nativeMenuShortcut', () {
    test('publishes modifier-bearing accelerators unchanged', () {
      const cmdS = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
      const ctrlShiftP = SingleActivator(
        LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      );
      const altE = SingleActivator(LogicalKeyboardKey.keyE, alt: true);

      expect(nativeMenuShortcut(cmdS), same(cmdS));
      expect(nativeMenuShortcut(ctrlShiftP), same(ctrlShiftP));
      expect(nativeMenuShortcut(altE), same(altE));
    });

    test('publishes bare function keys', () {
      const f1 = SingleActivator(LogicalKeyboardKey.f1);
      const f5 = SingleActivator(LogicalKeyboardKey.f5);
      expect(nativeMenuShortcut(f1), same(f1));
      expect(nativeMenuShortcut(f5), same(f5));
    });

    test('drops bare letters — they would be stolen from typing', () {
      expect(
        nativeMenuShortcut(const SingleActivator(LogicalKeyboardKey.keyQ)),
        isNull,
      );
      // Shift alone is not a primary modifier: ⇧M is still a typing key.
      expect(
        nativeMenuShortcut(
          const SingleActivator(LogicalKeyboardKey.keyM, shift: true),
        ),
        isNull,
      );
    });

    test('drops bare punctuation — NetCrux fanin/fanout regression', () {
      expect(
        nativeMenuShortcut(
          const SingleActivator(LogicalKeyboardKey.bracketLeft),
        ),
        isNull,
      );
      expect(
        nativeMenuShortcut(
          const SingleActivator(LogicalKeyboardKey.bracketRight),
        ),
        isNull,
      );
    });

    test('drops bare Escape — it must stay available to dismiss dialogs', () {
      expect(
        nativeMenuShortcut(const SingleActivator(LogicalKeyboardKey.escape)),
        isNull,
      );
    });

    test('drops bare caret-navigation keys', () {
      for (final key in [
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.delete,
      ]) {
        expect(
          nativeMenuShortcut(SingleActivator(key)),
          isNull,
          reason: '$key must not become a native key equivalent',
        );
      }
    });

    test('returns null for null and for non-SingleActivator types', () {
      expect(nativeMenuShortcut(null), isNull);
      expect(
        nativeMenuShortcut(
          const CharacterActivator('x', control: true),
        ),
        isNull,
      );
    });
  });

  group('displayMenuShortcut', () {
    test('keeps bare accelerators — the label binds nothing on Win/Linux', () {
      const esc = SingleActivator(LogicalKeyboardKey.escape);
      const bracket = SingleActivator(LogicalKeyboardKey.bracketLeft);
      expect(displayMenuShortcut(esc), same(esc));
      expect(displayMenuShortcut(bracket), same(bracket));
    });

    test('returns null for null and for non-SingleActivator types', () {
      expect(displayMenuShortcut(null), isNull);
      expect(displayMenuShortcut(const CharacterActivator('x')), isNull);
    });
  });
}
