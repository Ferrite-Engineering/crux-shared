// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_keybindings/src/linux_key_event_repair.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// What Flutter's Linux embedder hands the framework on an XQuartz display
// (`ssh -Y` from a Mac), recorded from a probe app on Xvfb loaded with
// XQuartz's keycodes (Mac virtual key code plus 8). Backspace is keycode 59,
// which the embedder takes for the evdev comma key; Escape is keycode 61, the
// evdev slash key; Return is keycode 44 (evdev J, reported as logical L once
// the embedder has derived its layout); Tab is keycode 56 (evdev B).
const int _gdkBackSpace = 0xff08;
const int _gdkEscape = 0xff1b;

ui.KeyData _data(
  ui.KeyEventType type,
  PhysicalKeyboardKey physical,
  LogicalKeyboardKey logical, {
  String? character,
}) => ui.KeyData(
  timeStamp: Duration.zero,
  type: type,
  physical: physical.usbHidUsage,
  logical: logical.keyId,
  character: character,
  synthesized: false,
);

void main() {
  group('LinuxKeyEventRepair', () {
    test('XQuartz Backspace, reported as the comma key, becomes Backspace '
        'for its press, repeat and release', () {
      final repair = LinuxKeyEventRepair();
      final down = repair.repair(
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.comma,
          LogicalKeyboardKey.comma,
          character: '\b',
        ),
      );
      expect(down.logical, LogicalKeyboardKey.backspace.keyId);
      expect(down.physical, PhysicalKeyboardKey.comma.usbHidUsage);
      expect(down.character, '\b');
      expect(down.type, ui.KeyEventType.down);

      final repeat = repair.repair(
        _data(
          ui.KeyEventType.repeat,
          PhysicalKeyboardKey.comma,
          LogicalKeyboardKey.comma,
          character: '\b',
        ),
      );
      expect(repeat.logical, LogicalKeyboardKey.backspace.keyId);

      // A release has no character; it follows its press.
      final up = repair.repair(
        _data(
          ui.KeyEventType.up,
          PhysicalKeyboardKey.comma,
          LogicalKeyboardKey.comma,
        ),
      );
      expect(up.logical, LogicalKeyboardKey.backspace.keyId);
      expect(up.type, ui.KeyEventType.up);

      // The next press of that key is judged on its own character.
      final comma = repair.repair(
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.comma,
          LogicalKeyboardKey.comma,
          character: ',',
        ),
      );
      expect(comma.logical, LogicalKeyboardKey.comma.keyId);
    });

    test('XQuartz Escape, Return and Tab, and a Delete on a printable key, '
        'become their own keys', () {
      final repair = LinuxKeyEventRepair();
      int repaired(
        PhysicalKeyboardKey physical,
        LogicalKeyboardKey logical,
        String character,
      ) => repair
          .repair(
            _data(
              ui.KeyEventType.down,
              physical,
              logical,
              character: character,
            ),
          )
          .logical;

      expect(
        repaired(PhysicalKeyboardKey.slash, LogicalKeyboardKey.slash, '\x1b'),
        LogicalKeyboardKey.escape.keyId,
      );
      expect(
        repaired(PhysicalKeyboardKey.keyJ, LogicalKeyboardKey.keyL, '\r'),
        LogicalKeyboardKey.enter.keyId,
      );
      expect(
        repaired(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyB, '\t'),
        LogicalKeyboardKey.tab.keyId,
      );
      expect(
        repaired(PhysicalKeyboardKey.period, LogicalKeyboardKey.period, '\x7f'),
        LogicalKeyboardKey.delete.keyId,
      );
    });

    test('keys from an evdev display pass through untouched', () {
      final repair = LinuxKeyEventRepair();
      final events = <ui.KeyData>[
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.backspace,
          LogicalKeyboardKey.backspace,
          character: '\b',
        ),
        _data(
          ui.KeyEventType.up,
          PhysicalKeyboardKey.backspace,
          LogicalKeyboardKey.backspace,
        ),
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.escape,
          LogicalKeyboardKey.escape,
          character: '\x1b',
        ),
        // Numpad Enter's character is also "\r"; its logical key is not
        // printable, so it keeps it.
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.numpadEnter,
          character: '\r',
        ),
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyA,
          character: 'a',
        ),
        _data(
          ui.KeyEventType.up,
          PhysicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyA,
        ),
        _data(
          ui.KeyEventType.down,
          PhysicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftLeft,
        ),
      ];
      for (final event in events) {
        expect(
          identical(repair.repair(event), event),
          isTrue,
          reason: '$event',
        );
      }
    });
  });

  group('installLinuxKeyEventRepair', () {
    late ui.KeyDataCallback? original;

    setUp(() {
      original =
          TestWidgetsFlutterBinding.instance.platformDispatcher.onKeyData;
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.onKeyData =
          original;
    });

    // Delivers a press and release the way the Linux embedder does: the key
    // data first, then the raw GTK key message that releases it to the
    // framework.
    Future<void> pressXQuartzKey(
      WidgetTester tester, {
      required int keycode,
      required int keyval,
      required PhysicalKeyboardKey physical,
      required LogicalKeyboardKey reportedLogical,
      required String character,
    }) async {
      for (final down in <bool>[true, false]) {
        tester.binding.platformDispatcher.onKeyData!(
          _data(
            down ? ui.KeyEventType.down : ui.KeyEventType.up,
            physical,
            reportedLogical,
            character: down ? character : null,
          ),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          SystemChannels.keyEvent.name,
          SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
            'type': down ? 'keydown' : 'keyup',
            'keymap': 'linux',
            'toolkit': 'gtk',
            'keyCode': keyval,
            'scanCode': keycode,
            'modifiers': 0,
            'unicodeScalarValues': down ? character.codeUnitAt(0) : 0,
            'specifiedLogicalKey': reportedLogical.keyId,
          }),
          (_) {},
        );
        await tester.pump();
      }
    }

    Future<TextEditingController> pumpSearchField(
      WidgetTester tester,
      VoidCallback onEscape,
    ) async {
      final controller = TextEditingController(text: 'hello');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
              child: TextField(controller: controller, autofocus: true),
            ),
          ),
        ),
      );
      await tester.pump();
      return controller;
    }

    testWidgets(
      'Backspace edits and Escape reaches its shortcut on an XQuartz display',
      (tester) async {
        installLinuxKeyEventRepair();
        var escapes = 0;
        final controller = await pumpSearchField(
          tester,
          () => escapes++,
        );

        await pressXQuartzKey(
          tester,
          keycode: 59,
          keyval: _gdkBackSpace,
          physical: PhysicalKeyboardKey.comma,
          reportedLogical: LogicalKeyboardKey.comma,
          character: '\b',
        );
        expect(controller.text, 'hell');

        await pressXQuartzKey(
          tester,
          keycode: 61,
          keyval: _gdkEscape,
          physical: PhysicalKeyboardKey.slash,
          reportedLogical: LogicalKeyboardKey.slash,
          character: '\x1b',
        );
        expect(escapes, 1);
        expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'installs once the binding has its key data handler, when called first',
      (tester) async {
        final binding = tester.binding.platformDispatcher.onKeyData!;
        tester.binding.platformDispatcher.onKeyData = null;
        installLinuxKeyEventRepair();
        tester.binding.platformDispatcher.onKeyData = binding;
        await tester.idle();
        expect(
          tester.binding.platformDispatcher.onKeyData,
          isNot(same(binding)),
        );

        // A second call keeps the one repair.
        final installed = tester.binding.platformDispatcher.onKeyData;
        installLinuxKeyEventRepair();
        expect(tester.binding.platformDispatcher.onKeyData, same(installed));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets('does nothing off Linux', (tester) async {
      final before = tester.binding.platformDispatcher.onKeyData;
      installLinuxKeyEventRepair();
      await tester.idle();
      expect(tester.binding.platformDispatcher.onKeyData, same(before));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
