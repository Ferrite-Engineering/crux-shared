// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_keybindings/src/linux_key_event_repair.dart';
import 'package:crux_keybindings/src/x_display_facts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The expected keys here come from outside the repair: from what Flutter's
// Linux embedder reports for the same key on an evdev display. The embedder's
// layout derivation (`guarantee_layout` in `fl_keyboard_manager.cc`, Flutter
// 3.47) is restated below as `_Embedder`, with its tables copied from
// `fl_key_mapping.g.cc`, and run over two keymaps of one layout: the evdev
// keycodes, and XQuartz's (the recorded `xquartz.xkb` of the reproduction,
// Mac virtual key code plus 8). A repaired XQuartz key must name the key the
// evdev display names.

const int _shiftedTab = 0xfe20; // ISO_Left_Tab
const int _returnKeysym = 0xff0d;
const int _tabKeysym = 0xff09;
const int _backSpaceKeysym = 0xff08;
const int _escapeKeysym = 0xff1b;
const int _controlLKeysym = 0xffe3;

/// `kGtkPlane` of `fl_key_mapping.g.cc`: the embedder's plane for a keycode or
/// keysym it has no key for.
const int _gtkPlane = 0x01500000000;

/// A key of the typing block: its xkb name, its keycode on XQuartz (from the
/// recorded keymap) and on evdev, and its keysyms without and with Shift.
class _Key {
  const _Key(this.name, this.xquartz, this.evdev, this.plain, this.shifted);
  final String name;
  final int xquartz;
  final int evdev;
  final int plain;
  final int shifted;

  _Key withKeysyms(int plain, int shifted) =>
      _Key(name, xquartz, evdev, plain, shifted);
}

int _c(String s) => s.codeUnitAt(0);

/// The US (pc+us) typing block.
final List<_Key> _usKeys = <_Key>[
  _Key('AC01', 8, 38, _c('a'), _c('A')),
  _Key('AC02', 9, 39, _c('s'), _c('S')),
  _Key('AC03', 10, 40, _c('d'), _c('D')),
  _Key('AC04', 11, 41, _c('f'), _c('F')),
  _Key('AC06', 12, 43, _c('h'), _c('H')),
  _Key('AC05', 13, 42, _c('g'), _c('G')),
  _Key('AB01', 14, 52, _c('z'), _c('Z')),
  _Key('AB02', 15, 53, _c('x'), _c('X')),
  _Key('AB03', 16, 54, _c('c'), _c('C')),
  _Key('AB04', 17, 55, _c('v'), _c('V')),
  _Key('LSGT', 18, 94, _c('<'), _c('>')),
  _Key('AB05', 19, 56, _c('b'), _c('B')),
  _Key('AD01', 20, 24, _c('q'), _c('Q')),
  _Key('AD02', 21, 25, _c('w'), _c('W')),
  _Key('AD03', 22, 26, _c('e'), _c('E')),
  _Key('AD04', 23, 27, _c('r'), _c('R')),
  _Key('AD06', 24, 29, _c('y'), _c('Y')),
  _Key('AD05', 25, 28, _c('t'), _c('T')),
  _Key('AE01', 26, 10, _c('1'), _c('!')),
  _Key('AE02', 27, 11, _c('2'), _c('@')),
  _Key('AE03', 28, 12, _c('3'), _c('#')),
  _Key('AE04', 29, 13, _c('4'), _c(r'$')),
  _Key('AE06', 30, 15, _c('6'), _c('^')),
  _Key('AE05', 31, 14, _c('5'), _c('%')),
  _Key('AE12', 32, 21, _c('='), _c('+')),
  _Key('AE09', 33, 18, _c('9'), _c('(')),
  _Key('AE07', 34, 16, _c('7'), _c('&')),
  _Key('AE11', 35, 20, _c('-'), _c('_')),
  _Key('AE08', 36, 17, _c('8'), _c('*')),
  _Key('AE10', 37, 19, _c('0'), _c(')')),
  _Key('AD12', 38, 35, _c(']'), _c('}')),
  _Key('AD09', 39, 32, _c('o'), _c('O')),
  _Key('AD07', 40, 30, _c('u'), _c('U')),
  _Key('AD11', 41, 34, _c('['), _c('{')),
  _Key('AD08', 42, 31, _c('i'), _c('I')),
  _Key('AD10', 43, 33, _c('p'), _c('P')),
  const _Key('RTRN', 44, 36, _returnKeysym, _returnKeysym),
  _Key('AC09', 45, 46, _c('l'), _c('L')),
  _Key('AC07', 46, 44, _c('j'), _c('J')),
  _Key('AC11', 47, 48, _c("'"), _c('"')),
  _Key('AC08', 48, 45, _c('k'), _c('K')),
  _Key('AC10', 49, 47, _c(';'), _c(':')),
  _Key('BKSL', 50, 51, _c(r'\'), _c('|')),
  _Key('AB08', 51, 59, _c(','), _c('<')),
  _Key('AB10', 52, 61, _c('/'), _c('?')),
  _Key('AB06', 53, 57, _c('n'), _c('N')),
  _Key('AB07', 54, 58, _c('m'), _c('M')),
  _Key('AB09', 55, 60, _c('.'), _c('>')),
  const _Key('TAB', 56, 23, _tabKeysym, _shiftedTab),
  _Key('SPCE', 57, 65, _c(' '), _c(' ')),
  _Key('TLDE', 58, 49, _c('`'), _c('~')),
  const _Key('BKSP', 59, 22, _backSpaceKeysym, _backSpaceKeysym),
  const _Key('ESC', 61, 9, _escapeKeysym, _escapeKeysym),
  // Control, which evdev has on 37 and XQuartz on 67, the evdev F1 key.
  const _Key('LCTL', 67, 37, _controlLKeysym, _controlLKeysym),
];

/// A layout with the keysyms of [changes] (xkb name to plain and shifted
/// keysyms) over the US one.
List<_Key> _layout(Map<String, (int, int)> changes) => <_Key>[
  for (final key in _usKeys)
    if (changes[key.name] case (final plain, final shifted))
      key.withKeysyms(plain, shifted)
    else
      key,
];

/// A Cyrillic letter as a Unicode keysym.
int _cyr(String s) => 0x1000000 + s.codeUnitAt(0);

/// A Russian layout: Cyrillic on the letter keys and on `[ ] ; ' , . \``.
final List<_Key> _russianKeys = _layout(<String, (int, int)>{
  for (final (name, lower, upper) in <(String, String, String)>[
    ('AD01', 'й', 'Й'),
    ('AD02', 'ц', 'Ц'),
    ('AD03', 'у', 'У'),
    ('AD04', 'к', 'К'),
    ('AD05', 'е', 'Е'),
    ('AD06', 'н', 'Н'),
    ('AD07', 'г', 'Г'),
    ('AD08', 'ш', 'Ш'),
    ('AD09', 'щ', 'Щ'),
    ('AD10', 'з', 'З'),
    ('AD11', 'х', 'Х'),
    ('AD12', 'ъ', 'Ъ'),
    ('AC01', 'ф', 'Ф'),
    ('AC02', 'ы', 'Ы'),
    ('AC03', 'в', 'В'),
    ('AC04', 'а', 'А'),
    ('AC05', 'п', 'П'),
    ('AC06', 'р', 'Р'),
    ('AC07', 'о', 'О'),
    ('AC08', 'л', 'Л'),
    ('AC09', 'д', 'Д'),
    ('AC10', 'ж', 'Ж'),
    ('AC11', 'э', 'Э'),
    ('AB01', 'я', 'Я'),
    ('AB02', 'ч', 'Ч'),
    ('AB03', 'с', 'С'),
    ('AB04', 'м', 'М'),
    ('AB05', 'и', 'И'),
    ('AB06', 'т', 'Т'),
    ('AB07', 'ь', 'Ь'),
    ('AB08', 'б', 'Б'),
    ('AB09', 'ю', 'Ю'),
    ('TLDE', 'ё', 'Ё'),
  ])
    name: (_cyr(lower), _cyr(upper)),
});

/// A French AZERTY layout: digits on Shift, A and Q, Z and W swapped, M on
/// the semicolon key.
final List<_Key> _azertyKeys = _layout(<String, (int, int)>{
  'AE01': (_c('&'), _c('1')),
  'AE02': (0xe9, _c('2')), // é
  'AE03': (_c('"'), _c('3')),
  'AE04': (_c("'"), _c('4')),
  'AE05': (_c('('), _c('5')),
  'AE06': (0xa7, _c('6')), // §
  'AE07': (0xe8, _c('7')), // è
  'AE08': (_c('!'), _c('8')),
  'AE09': (0xe7, _c('9')), // ç
  'AE10': (0xe0, _c('0')), // à
  'AD01': (_c('a'), _c('A')),
  'AD02': (_c('z'), _c('Z')),
  'AC01': (_c('q'), _c('Q')),
  'AC10': (_c('m'), _c('M')),
  'AB01': (_c('w'), _c('W')),
  'AB07': (_c(','), _c('?')),
});

/// `xkb_to_physical_key_map` of `fl_key_mapping.g.cc`, the keycodes used here.
final Map<int, PhysicalKeyboardKey> _evdevPhysical = <int, PhysicalKeyboardKey>{
  9: PhysicalKeyboardKey.escape,
  10: PhysicalKeyboardKey.digit1,
  11: PhysicalKeyboardKey.digit2,
  12: PhysicalKeyboardKey.digit3,
  13: PhysicalKeyboardKey.digit4,
  14: PhysicalKeyboardKey.digit5,
  15: PhysicalKeyboardKey.digit6,
  16: PhysicalKeyboardKey.digit7,
  17: PhysicalKeyboardKey.digit8,
  18: PhysicalKeyboardKey.digit9,
  19: PhysicalKeyboardKey.digit0,
  20: PhysicalKeyboardKey.minus,
  21: PhysicalKeyboardKey.equal,
  22: PhysicalKeyboardKey.backspace,
  23: PhysicalKeyboardKey.tab,
  24: PhysicalKeyboardKey.keyQ,
  25: PhysicalKeyboardKey.keyW,
  26: PhysicalKeyboardKey.keyE,
  27: PhysicalKeyboardKey.keyR,
  28: PhysicalKeyboardKey.keyT,
  29: PhysicalKeyboardKey.keyY,
  30: PhysicalKeyboardKey.keyU,
  31: PhysicalKeyboardKey.keyI,
  32: PhysicalKeyboardKey.keyO,
  33: PhysicalKeyboardKey.keyP,
  34: PhysicalKeyboardKey.bracketLeft,
  35: PhysicalKeyboardKey.bracketRight,
  36: PhysicalKeyboardKey.enter,
  37: PhysicalKeyboardKey.controlLeft,
  38: PhysicalKeyboardKey.keyA,
  39: PhysicalKeyboardKey.keyS,
  40: PhysicalKeyboardKey.keyD,
  41: PhysicalKeyboardKey.keyF,
  42: PhysicalKeyboardKey.keyG,
  43: PhysicalKeyboardKey.keyH,
  44: PhysicalKeyboardKey.keyJ,
  45: PhysicalKeyboardKey.keyK,
  46: PhysicalKeyboardKey.keyL,
  47: PhysicalKeyboardKey.semicolon,
  48: PhysicalKeyboardKey.quote,
  49: PhysicalKeyboardKey.backquote,
  50: PhysicalKeyboardKey.shiftLeft,
  51: PhysicalKeyboardKey.backslash,
  52: PhysicalKeyboardKey.keyZ,
  53: PhysicalKeyboardKey.keyX,
  54: PhysicalKeyboardKey.keyC,
  55: PhysicalKeyboardKey.keyV,
  56: PhysicalKeyboardKey.keyB,
  57: PhysicalKeyboardKey.keyN,
  58: PhysicalKeyboardKey.keyM,
  59: PhysicalKeyboardKey.comma,
  60: PhysicalKeyboardKey.period,
  61: PhysicalKeyboardKey.slash,
  65: PhysicalKeyboardKey.space,
  67: PhysicalKeyboardKey.f1,
  94: PhysicalKeyboardKey.intlBackslash,
};

/// `layout_goals` of `fl_key_mapping.g.cc`: keycode, logical key, mandatory.
const List<(int, int, bool)> _layoutGoals = <(int, int, bool)>[
  (0x41, 0x20, false),
  (0x30, 0x22, false),
  (0x3b, 0x2c, false),
  (0x14, 0x2d, false),
  (0x3c, 0x2e, false),
  (0x3d, 0x2f, false),
  (0x13, 0x30, true),
  (0x0a, 0x31, true),
  (0x0b, 0x32, true),
  (0x0c, 0x33, true),
  (0x0d, 0x34, true),
  (0x0e, 0x35, true),
  (0x0f, 0x36, true),
  (0x10, 0x37, true),
  (0x11, 0x38, true),
  (0x12, 0x39, true),
  (0x2f, 0x3b, false),
  (0x15, 0x3d, false),
  (0x22, 0x5b, false),
  (0x33, 0x5c, false),
  (0x23, 0x5d, false),
  (0x31, 0x60, false),
  (0x26, 0x61, true),
  (0x38, 0x62, true),
  (0x36, 0x63, true),
  (0x28, 0x64, true),
  (0x1a, 0x65, true),
  (0x29, 0x66, true),
  (0x2a, 0x67, true),
  (0x2b, 0x68, true),
  (0x1f, 0x69, true),
  (0x2c, 0x6a, true),
  (0x2d, 0x6b, true),
  (0x2e, 0x6c, true),
  (0x3a, 0x6d, true),
  (0x39, 0x6e, true),
  (0x20, 0x6f, true),
  (0x21, 0x70, true),
  (0x18, 0x71, true),
  (0x1b, 0x72, true),
  (0x27, 0x73, true),
  (0x1c, 0x74, true),
  (0x1e, 0x75, true),
  (0x37, 0x76, true),
  (0x19, 0x77, true),
  (0x35, 0x78, true),
  (0x1d, 0x79, true),
  (0x34, 0x7a, true),
  (0x5e, 0x200000020, false),
];

/// `gtk_keyval_to_logical_key_map`, the keysyms used here.
final Map<int, int> _keysymLogical = <int, int>{
  _shiftedTab: LogicalKeyboardKey.tab.keyId,
  _backSpaceKeysym: LogicalKeyboardKey.backspace.keyId,
  _tabKeysym: LogicalKeyboardKey.tab.keyId,
  _returnKeysym: LogicalKeyboardKey.enter.keyId,
  _escapeKeysym: LogicalKeyboardKey.escape.keyId,
  _controlLKeysym: LogicalKeyboardKey.controlLeft.keyId,
};

/// `gdk_keyval_to_unicode` for the keysyms used here.
String? _keysymCharacter(int keysym) => switch (keysym) {
  _backSpaceKeysym => '\b',
  _tabKeysym || _shiftedTab => '\t',
  _returnKeysym => '\r',
  _escapeKeysym => '\x1b',
  _controlLKeysym => null,
  < 0x100 => String.fromCharCode(keysym),
  >= 0x1000000 => String.fromCharCode(keysym - 0x1000000),
  _ => null,
};

/// `to_lower` of `fl_key_embedder_responder.cc`.
int _toLower(int n) {
  if (n >= 0x41 && n <= 0x5a) return n + 0x20;
  if (n >= 0xc0 && n <= 0xde && n != 0xf7) return n + 0x20;
  return n;
}

/// Flutter's Linux embedder for one keymap: the key data it hands the
/// framework for a key press.
class _Embedder {
  _Embedder(List<_Key> keys, {required bool xquartz})
    : _keysyms = <int, (int, int)>{
        for (final key in keys)
          (xquartz ? key.xquartz : key.evdev): (key.plain, key.shifted),
      } {
    _deriveLayout();
  }

  final Map<int, (int, int)> _keysyms;
  final Map<int, int> _layout = <int, int>{};

  /// `convert_key_to_char`: 0 where the keycode has no keysym.
  int _clue(int keycode, {required bool shifted}) {
    final keysyms = _keysyms[keycode];
    if (keysyms == null) return 0;
    final keysym = shifted ? keysyms.$2 : keysyms.$1;
    return keysym < 0xd7ff ? keysym : 0xffff;
  }

  /// `guarantee_layout`.
  void _deriveLayout() {
    final remaining = <int, int>{
      for (final (keycode, logical, mandatory) in _layoutGoals)
        if (mandatory) logical: keycode,
    };
    for (final (keycode, logical, _) in _layoutGoals) {
      final clues = <int>[
        _clue(keycode, shifted: false),
        _clue(keycode, shifted: true),
      ];
      for (final clue in clues) {
        if (remaining.containsKey(clue)) {
          _layout[keycode] = clue;
          remaining.remove(clue);
          break;
        }
      }
      if (!_layout.containsKey(keycode) && !clues.any((c) => c < 256)) {
        _layout[keycode] = logical;
      }
    }
    remaining.forEach((logical, keycode) => _layout[keycode] = logical);
  }

  ui.KeyData press(
    int keycode, {
    bool shifted = false,
    ui.KeyEventType type = ui.KeyEventType.down,
  }) {
    final (plain, shift) = _keysyms[keycode]!;
    final keysym = shifted ? shift : plain;
    final int logical;
    if (_layout[keycode] case final derived?) {
      logical = derived;
    } else if (_keysymLogical[keysym] case final mapped?) {
      logical = mapped;
    } else if (keysym < 0x100) {
      logical = _toLower(keysym);
    } else {
      logical = _gtkPlane | keysym;
    }
    return ui.KeyData(
      timeStamp: Duration.zero,
      type: type,
      physical: _evdevPhysical[keycode]?.usbHidUsage ?? (_gtkPlane | keycode),
      logical: logical,
      character: type == ui.KeyEventType.up ? null : _keysymCharacter(keysym),
      synthesized: false,
    );
  }
}

String _name(int logical) =>
    LogicalKeyboardKey.findKeyByKeyId(logical)?.debugName ??
    '0x${logical.toRadixString(16)}';

/// For every key of [keys] that types a character, with and without Shift:
/// the key the evdev display reports, and the key an XQuartz display reports
/// once [repair] has seen it.
Map<String, (String, String)> _compare(
  List<_Key> keys,
  LinuxKeyEventRepair repair,
) {
  final evdev = _Embedder(keys, xquartz: false);
  final xquartz = _Embedder(keys, xquartz: true);
  return <String, (String, String)>{
    for (final key in keys)
      for (final shifted in <bool>[false, true])
        if (_keysymCharacter(shifted ? key.shifted : key.plain) != null)
          '${key.name}${shifted ? '+Shift' : ''}': (
            _name(evdev.press(key.evdev, shifted: shifted).logical),
            _name(
              repair
                  .repair(xquartz.press(key.xquartz, shifted: shifted))
                  .logical,
            ),
          ),
  };
}

/// The entries of [comparison] whose two keys differ.
Map<String, (String, String)> _differences(
  Map<String, (String, String)> comparison,
) => <String, (String, String)>{
  for (final MapEntry(:key, :value) in comparison.entries)
    if (value.$1 != value.$2) key: value,
};

void main() {
  group('the restated embedder', () {
    test('reproduces what was recorded on Xvfb with the XQuartz keymap', () {
      final xquartz = _Embedder(_usKeys, xquartz: true);
      // x, keycode 15: physical Digit 6, logical Key X, char x.
      final x = xquartz.press(15);
      expect(x.physical, PhysicalKeyboardKey.digit6.usbHidUsage);
      expect(x.logical, LogicalKeyboardKey.keyX.keyId);
      expect(x.character, 'x');
      // o, keycode 39: physical Key S, logical Key S, char o (the issue).
      final o = xquartz.press(39);
      expect(o.physical, PhysicalKeyboardKey.keyS.usbHidUsage);
      expect(o.logical, LogicalKeyboardKey.keyS.keyId);
      expect(o.character, 'o');
      // BackSpace, keycode 59: Comma; Escape, keycode 61: Slash; Tab,
      // keycode 56: Key B.
      expect(xquartz.press(59).logical, LogicalKeyboardKey.comma.keyId);
      expect(xquartz.press(61).logical, LogicalKeyboardKey.slash.keyId);
      expect(xquartz.press(56).logical, LogicalKeyboardKey.keyB.keyId);
    });

    test('names every US key by its character on an evdev display', () {
      final evdev = _Embedder(_usKeys, xquartz: false);
      expect(evdev.press(32).logical, LogicalKeyboardKey.keyO.keyId);
      expect(evdev.press(39).logical, LogicalKeyboardKey.keyS.keyId);
      expect(evdev.press(10, shifted: true).logical, 0x31);
    });
  });

  group('XQuartz keys, repaired', () {
    test("the issue's reproduction: keycode 39 typing o arrives as O, and "
        'its repeat and release follow', () {
      final repair = LinuxKeyEventRepair(xquartzKeycodes: true);
      final xquartz = _Embedder(_usKeys, xquartz: true);
      expect(
        repair.repair(xquartz.press(39)).logical,
        LogicalKeyboardKey.keyO.keyId,
      );
      expect(
        repair.repair(xquartz.press(39, type: ui.KeyEventType.repeat)).logical,
        LogicalKeyboardKey.keyO.keyId,
      );
      expect(
        repair.repair(xquartz.press(39, type: ui.KeyEventType.up)).logical,
        LogicalKeyboardKey.keyO.keyId,
      );
      // Shift+O is the O key too.
      expect(
        repair.repair(xquartz.press(39, shifted: true)).logical,
        LogicalKeyboardKey.keyO.keyId,
      );
    });

    test('with the control-key repair alone, the US keymap misplaces O, ], '
        '1, 2, V and B', () {
      final comparison = _compare(_usKeys, LinuxKeyEventRepair());
      expect(_differences(comparison).keys.toSet(), <String>{
        'AD09', 'AD09+Shift', // o: Key S
        'AD12', 'AD12+Shift', // ]: Key A
        'AE01', 'AE01+Shift', // 1: Key E
        'AE02', 'AE02+Shift', // 2: Key R
        'AB04', 'AB04+Shift', // v: Digit 8
        'AB05', 'AB05+Shift', // b: Digit 0
        'AE08+Shift', 'AE10+Shift', // *, ): not Digit 8, Digit 0
      });
    });

    test('every US key names what it names on an evdev display', () {
      final comparison = _compare(
        _usKeys,
        LinuxKeyEventRepair(xquartzKeycodes: true),
      );
      expect(_differences(comparison), isEmpty);
      expect(comparison['AD09'], ('Key O', 'Key O'));
    });

    test('every Russian key names its US position, as on an evdev display', () {
      final comparison = _compare(
        _russianKeys,
        LinuxKeyEventRepair(xquartzKeycodes: true),
      );
      expect(_differences(comparison), isEmpty);
      // щ is on the O key; х on [.
      expect(comparison['AD09'], ('Key O', 'Key O'));
      expect(comparison['AD11'], ('Bracket Left', 'Bracket Left'));
      // Unrepaired, the Russian keymap is misread far more widely.
      expect(
        _differences(_compare(_russianKeys, LinuxKeyEventRepair())).length,
        greaterThan(30),
      );
    });

    test('every AZERTY key names what it names on an evdev display: & is the '
        'digit 1, A and Q keep their letters', () {
      final comparison = _compare(
        _azertyKeys,
        LinuxKeyEventRepair(xquartzKeycodes: true),
      );
      expect(_differences(comparison), isEmpty);
      expect(comparison['AE01'], ('Digit 1', 'Digit 1'));
      expect(comparison['AD01'], ('Key A', 'Key A'));
      expect(comparison['AC01'], ('Key Q', 'Key Q'));
    });
  });

  group('not XQuartz', () {
    test('an evdev display is untouched, on a layout whose Latin keys differ '
        'from the characters on purpose', () {
      // Russian on evdev: the O key types щ and is the O key on purpose.
      for (final keys in <List<_Key>>[_usKeys, _russianKeys, _azertyKeys]) {
        final evdev = _Embedder(keys, xquartz: false);
        final repair = LinuxKeyEventRepair();
        for (final key in keys) {
          for (final shifted in <bool>[false, true]) {
            final data = evdev.press(key.evdev, shifted: shifted);
            expect(
              identical(repair.repair(data), data),
              isTrue,
              reason: '${key.name} shifted: $shifted',
            );
          }
        }
      }
      final russian = _Embedder(_russianKeys, xquartz: false).press(32);
      expect(russian.character, 'щ');
      expect(russian.logical, LogicalKeyboardKey.keyO.keyId);
      expect(
        LinuxKeyEventRepair().repair(russian).logical,
        LogicalKeyboardKey.keyO.keyId,
      );
    });

    test("the issue's key is left alone until the display is XQuartz", () {
      final data = _Embedder(_usKeys, xquartz: true).press(39);
      expect(identical(LinuxKeyEventRepair().repair(data), data), isTrue);
    });
  });

  group('XDisplayFacts', () {
    XDisplayFacts facts({
      String vendor = 'The X.Org Foundation',
      List<String> extensions = const <String>['XKEYBOARD', 'RENDER'],
      int keysymAt61 = 0x2f, // slash, evdev
    }) => XDisplayFacts(
      vendor: vendor,
      extensions: extensions,
      keysymAtKeycode61: keysymAt61,
    );

    test('XQuartz by its extensions or its vendor, with Escape on 61', () {
      expect(
        facts(
          extensions: <String>['XKEYBOARD', 'Apple-WM', 'Apple-DRI'],
          keysymAt61: 0xff1b,
        ).hasXQuartzKeycodes,
        isTrue,
      );
      expect(
        facts(
          vendor: 'The XQuartz Project',
          keysymAt61: 0xff1b,
        ).hasXQuartzKeycodes,
        isTrue,
      );
    });

    test("reading this machine's display never throws, and a test machine "
        'is not XQuartz', () async {
      // Null off Linux or without DISPLAY; on a Linux runner with an X
      // server this goes through libX11.
      final read = await debugReadXDisplayFacts();
      expect(read?.hasXQuartzKeycodes ?? false, isFalse, reason: '$read');
    });

    test('anything else is not', () {
      // A Linux desktop.
      expect(facts().hasXQuartzKeycodes, isFalse);
      // Xvfb with XQuartz's keymap loaded (the reproduction rig): not XQuartz.
      expect(facts(keysymAt61: 0xff1b).hasXQuartzKeycodes, isFalse);
      // XQuartz whose keycodes are not the Mac's (Escape moved): unrepaired.
      expect(
        facts(extensions: <String>['Apple-WM']).hasXQuartzKeycodes,
        isFalse,
      );
      expect(
        facts(vendor: 'The XQuartz Project', keysymAt61: 0).hasXQuartzKeycodes,
        isFalse,
      );
    });
  });

  group('installLinuxKeyEventRepair on an XQuartz display', () {
    late ui.KeyDataCallback? original;
    late Future<XDisplayFacts?> Function() originalReader;

    setUp(() {
      original =
          TestWidgetsFlutterBinding.instance.platformDispatcher.onKeyData;
      originalReader = debugReadXDisplayFacts;
      debugResetXDisplay();
    });

    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.onKeyData =
          original;
      debugReadXDisplayFacts = originalReader;
      debugResetXDisplay();
    });

    // Sends the key data, then the raw GTK key message that releases it to
    // the framework, as the Linux embedder does.
    Future<void> send(
      WidgetTester tester,
      ui.KeyData data, {
      required int keycode,
      required int keyval,
      int modifiers = 0,
    }) async {
      tester.binding.platformDispatcher.onKeyData!(data);
      final down = data.type == ui.KeyEventType.down;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.keyEvent.name,
        SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
          'type': down ? 'keydown' : 'keyup',
          'keymap': 'linux',
          'toolkit': 'gtk',
          'keyCode': keyval,
          'scanCode': keycode,
          'modifiers': modifiers,
          'unicodeScalarValues': down ? (data.character?.runes.first ?? 0) : 0,
          'specifiedLogicalKey': data.logical,
        }),
        (_) {},
      );
      await tester.pump();
    }

    Future<List<String>> pressControlO(WidgetTester tester) async {
      final fired = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () =>
                  fired.add('Ctrl+O'),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  fired.add('Ctrl+S'),
            },
            child: const Focus(autofocus: true, child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      final xquartz = _Embedder(_usKeys, xquartz: true);
      const controlMask = 1 << 2; // GDK_CONTROL_MASK
      await send(
        tester,
        xquartz.press(67),
        keycode: 67,
        keyval: _controlLKeysym,
      );
      await send(
        tester,
        xquartz.press(39),
        keycode: 39,
        keyval: _c('o'),
        modifiers: controlMask,
      );
      await send(
        tester,
        xquartz.press(39, type: ui.KeyEventType.up),
        keycode: 39,
        keyval: _c('o'),
        modifiers: controlMask,
      );
      await send(
        tester,
        xquartz.press(67, type: ui.KeyEventType.up),
        keycode: 67,
        keyval: _controlLKeysym,
        modifiers: controlMask,
      );
      expect(HardwareKeyboard.instance.logicalKeysPressed, isEmpty);
      return fired;
    }

    testWidgets(
      'Ctrl+O runs the Ctrl+O shortcut, not Ctrl+S',
      (tester) async {
        debugReadXDisplayFacts = () async => const XDisplayFacts(
          vendor: 'The X.Org Foundation',
          extensions: <String>['Apple-DRI', 'Apple-WM', 'XKEYBOARD'],
          keysymAtKeycode61: 0xff1b,
        );
        installLinuxKeyEventRepair();
        await tester.idle();
        expect(await pressControlO(tester), <String>['Ctrl+O']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'a display that is not XQuartz keeps the letters as reported',
      (tester) async {
        debugReadXDisplayFacts = () async => const XDisplayFacts(
          vendor: 'The X.Org Foundation',
          extensions: <String>['XKEYBOARD'],
          keysymAtKeycode61: 0xff1b,
        );
        installLinuxKeyEventRepair();
        await tester.idle();
        expect(await pressControlO(tester), <String>['Ctrl+S']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'a display that cannot be read keeps the letters as reported',
      (tester) async {
        debugReadXDisplayFacts = () => Future<XDisplayFacts?>.error(
          StateError('no libX11'),
        );
        installLinuxKeyEventRepair();
        await tester.idle();
        expect(await pressControlO(tester), <String>['Ctrl+S']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });
}
