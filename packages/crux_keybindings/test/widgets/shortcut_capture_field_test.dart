// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
// `ShortcutCaptureField` is an implementation detail of `KeyBindingsEditor`
// and is deliberately absent from the barrel, so this test imports it from
// src directly.
import 'package:crux_keybindings/src/widgets/shortcut_capture_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _metrics = KeyBindingEditorMetrics(
  touchTarget: 44,
  iconSize: 24,
  bodyFontSize: 14,
  labelFontSize: 12,
  monoFontSize: 13,
);

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    required void Function(KeyBinding) onCaptured,
    required VoidCallback onCancel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutCaptureField(
            prompt: 'Press keys',
            metrics: _metrics,
            onCaptured: onCaptured,
            onCancel: onCancel,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('captures a modifier + key chord (accelerator → mod)', (
    tester,
  ) async {
    KeyBinding? captured;
    await pumpField(tester, onCaptured: (b) => captured = b, onCancel: () {});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.key, LogicalKeyboardKey.keyP);
    expect(captured!.modifiers, {KeyModifier.mod});
  });

  testWidgets(
    'held Caps Lock (macOS Caps Lock→Control remap) captures as Control',
    (tester) async {
      // Under a macOS Caps Lock→Control remap, Flutter surfaces the
      // remapped key as a held `capsLock` logical key with
      // `isControlPressed == false`. The chord must still capture as
      // the Control accelerator, not a bare trigger.
      KeyBinding? captured;
      await pumpField(tester, onCaptured: (b) => captured = b, onCancel: () {});

      await tester.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.key, LogicalKeyboardKey.keyF);
      expect(captured!.modifiers, {KeyModifier.mod});
    },
  );

  testWidgets('held Caps Lock defeats the bare-Esc cancel shortcut', (
    tester,
  ) async {
    // Caps Lock+Esc under the remap is Control+Esc — a real binding, not a
    // cancel.
    var cancelled = false;
    KeyBinding? captured;
    await pumpField(
      tester,
      onCaptured: (b) => captured = b,
      onCancel: () => cancelled = true,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.capsLock);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.capsLock);
    await tester.pump();

    expect(cancelled, isFalse);
    expect(captured!.key, LogicalKeyboardKey.escape);
    expect(captured!.modifiers, {KeyModifier.mod});
  });

  testWidgets('ignores standalone modifier presses', (tester) async {
    var count = 0;
    await pumpField(tester, onCaptured: (_) => count++, onCancel: () {});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(count, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  });

  testWidgets('bare Esc cancels instead of binding', (tester) async {
    var cancelled = false;
    KeyBinding? captured;
    await pumpField(
      tester,
      onCaptured: (b) => captured = b,
      onCancel: () => cancelled = true,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(cancelled, isTrue);
    expect(captured, isNull);
  });

  testWidgets('Shift+Esc binds Esc (modifier defeats the cancel shortcut)', (
    tester,
  ) async {
    var cancelled = false;
    KeyBinding? captured;
    await pumpField(
      tester,
      onCaptured: (b) => captured = b,
      onCancel: () => cancelled = true,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(cancelled, isFalse);
    expect(captured!.key, LogicalKeyboardKey.escape);
    expect(captured!.modifiers, {KeyModifier.shift});
  });
}
