// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' as ui;

import 'package:crux_keybindings/src/x_display_facts.dart';
import 'package:crux_keybindings/src/x_display_probe_stub.dart'
    if (dart.library.ffi) 'package:crux_keybindings/src/x_display_probe_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puts the right logical key back on Backspace, Tab, Enter, Escape and
/// Delete when the app runs on an X display whose keycodes are not the evdev
/// keycodes Flutter's Linux embedder expects, and on an XQuartz display also
/// on the letter keys.
///
/// XQuartz is the common case: `ssh -Y` from a Mac to a Linux machine. Its
/// keycodes are the Mac's virtual key codes plus 8, so Backspace is keycode
/// 59 and Escape keycode 61, where an evdev keyboard has 22 and 9. The
/// embedder works out a keyboard layout from the keycodes it believes are the
/// comma, slash and letter keys, finds Backspace and Escape sitting on two of
/// them, and reports them as the comma and slash keys. The key's own keysym
/// still reaches the framework as the event's character (`"\b"`, `"\x1b"`), so
/// typing works while Backspace and Escape do nothing.
///
/// Letters go wrong the same way. XQuartz's A and S keys (keycodes 8 and 9)
/// are not among the keycodes the embedder looks at, so it places A and S at
/// their evdev keycodes, 38 and 39, which on XQuartz are `]` and O: pressing O
/// reports S, and Ctrl+O runs a Ctrl+S shortcut (E, R, 8 and 0 land on 1, 2,
/// V and B the same way). Only once the X server has been recognised as
/// XQuartz (its vendor string or its own extensions, and Escape on keycode
/// 61; see [XDisplayFacts.hasXQuartzKeycodes]) does the repair give a key
/// that types a Latin letter or digit that letter or digit, and a key that
/// types a non-Latin letter the Latin letter of its position on the Mac
/// keyboard, as the embedder does on an evdev display. The server is read
/// once, in the background, so keys pressed in the first moments after
/// startup may still arrive unrepaired.
///
/// The repair sits in front of the framework's own key data handler, so
/// [HardwareKeyboard] handlers, `Shortcuts` and text fields all see the
/// repaired key. Call once, after `WidgetsFlutterBinding.ensureInitialized()`.
/// It does nothing anywhere but Linux, and on Linux it changes nothing on an
/// evdev display, where every key's logical key already agrees with its
/// character. Calling it again does nothing.
void installLinuxKeyEventRepair() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
  // Start reading the display now; the repair picks the answer up when it
  // comes.
  unawaited(_xquartzKeycodes());
  if (_wrapKeyDataHandler()) return;
  // The binding installs its handler only once the engine has answered its
  // first keyboard-state query. Replies come back in the order the queries
  // went out, so by the time a second query is answered the handler is there.
  unawaited(
    SystemChannels.keyboard
        .invokeMethod<Object?>('getKeyboardState')
        .then<void>(
          (_) => _wrapKeyDataHandler(),
          onError: (Object _) => _wrapKeyDataHandler(),
        ),
  );
}

/// The handler [installLinuxKeyEventRepair] installed, so a second call can
/// see it is already in place.
ui.KeyDataCallback? _installed;

/// Puts the repair in front of the binding's key data handler. False when the
/// binding has not installed its handler yet.
bool _wrapKeyDataHandler() {
  final dispatcher = ServicesBinding.instance.platformDispatcher;
  final inner = dispatcher.onKeyData;
  if (inner == null) return false;
  if (inner == _installed) return true;
  final repair = LinuxKeyEventRepair();
  unawaited(
    _xquartzKeycodes().then<void>(
      (xquartz) => repair.xquartzKeycodes = xquartz,
    ),
  );
  bool repairing(ui.KeyData data) => inner(repair.repair(data));
  dispatcher.onKeyData = _installed = repairing;
  return true;
}

/// Reads the X server's facts. Replaced in tests, which have no X server.
@visibleForTesting
Future<XDisplayFacts?> Function() debugReadXDisplayFacts = readXDisplayFacts;

/// Whether the display has XQuartz's keycodes, read once per process.
Future<bool>? _xquartzDisplay;

/// Forgets the display read so far, so a test can install the repair against
/// another display.
@visibleForTesting
void debugResetXDisplay() => _xquartzDisplay = null;

Future<bool> _xquartzKeycodes() => _xquartzDisplay ??=
    Future<XDisplayFacts?>.sync(
      () => debugReadXDisplayFacts(),
    ).then<bool>(
      (facts) => facts?.hasXQuartzKeycodes ?? false,
      onError: (Object _) => false,
    );

/// The control key each control character stands for. The embedder fills
/// [ui.KeyData.character] from the key's keysym, so these characters arrive
/// only from the keys themselves (Ctrl+H is the character `h` on Linux).
const Map<String, LogicalKeyboardKey> _controlKeys =
    <String, LogicalKeyboardKey>{
      '\b': LogicalKeyboardKey.backspace,
      '\t': LogicalKeyboardKey.tab,
      '\r': LogicalKeyboardKey.enter,
      '\x1b': LogicalKeyboardKey.escape,
      '\x7f': LogicalKeyboardKey.delete,
    };

/// The physical key Flutter's Linux embedder reports for X keycode 8, which
/// evdev does not use: the keycode in the embedder's GTK plane.
const int _gtkPlaneKeycode8 = 0x01500000008;

/// XQuartz's letter and punctuation keys, by the physical key the embedder
/// reports for them, as the US key at that position on a Mac (ANSI)
/// keyboard: what the embedder names a key that types a non-Latin character
/// on an evdev display.
///
/// An XQuartz keycode is the Mac virtual key code plus 8 (`kVK_ANSI_A` is 0,
/// so A is keycode 8). The embedder takes every keycode for an evdev keycode
/// and reports evdev's physical key for it, so XQuartz's O key (`kVK_ANSI_O`
/// 0x1F, keycode 39) arrives as the physical S key.
final Map<int, int> _xquartzUsKeyByPhysical = <int, int>{
  PhysicalKeyboardKey.digit9.usbHidUsage:
      LogicalKeyboardKey.intlBackslash.keyId, // kVK_ISO_Section 0x0A, 18
  PhysicalKeyboardKey.keyO.usbHidUsage: LogicalKeyboardKey.equal.keyId, // 32
  PhysicalKeyboardKey.bracketRight.usbHidUsage:
      LogicalKeyboardKey.minus.keyId, // 35
  PhysicalKeyboardKey.keyA.usbHidUsage:
      LogicalKeyboardKey.bracketRight.keyId, // 38
  PhysicalKeyboardKey.keyF.usbHidUsage:
      LogicalKeyboardKey.bracketLeft.keyId, // 41
  PhysicalKeyboardKey.semicolon.usbHidUsage:
      LogicalKeyboardKey.quote.keyId, // 47
  PhysicalKeyboardKey.backquote.usbHidUsage:
      LogicalKeyboardKey.semicolon.keyId, // 49
  PhysicalKeyboardKey.shiftLeft.usbHidUsage:
      LogicalKeyboardKey.backslash.keyId, // 50
  PhysicalKeyboardKey.backslash.usbHidUsage:
      LogicalKeyboardKey.comma.keyId, // 51
  PhysicalKeyboardKey.keyZ.usbHidUsage: LogicalKeyboardKey.slash.keyId, // 52
  PhysicalKeyboardKey.keyV.usbHidUsage: LogicalKeyboardKey.period.keyId, // 55
  PhysicalKeyboardKey.keyM.usbHidUsage:
      LogicalKeyboardKey.backquote.keyId, // 58
  // The letters.
  _gtkPlaneKeycode8: LogicalKeyboardKey.keyA.keyId, // 0x00 + 8 = 8
  PhysicalKeyboardKey.escape.usbHidUsage: LogicalKeyboardKey.keyS.keyId, // 9
  PhysicalKeyboardKey.digit1.usbHidUsage: LogicalKeyboardKey.keyD.keyId, // 10
  PhysicalKeyboardKey.digit2.usbHidUsage: LogicalKeyboardKey.keyF.keyId, // 11
  PhysicalKeyboardKey.digit3.usbHidUsage: LogicalKeyboardKey.keyH.keyId, // 12
  PhysicalKeyboardKey.digit4.usbHidUsage: LogicalKeyboardKey.keyG.keyId, // 13
  PhysicalKeyboardKey.digit5.usbHidUsage: LogicalKeyboardKey.keyZ.keyId, // 14
  PhysicalKeyboardKey.digit6.usbHidUsage: LogicalKeyboardKey.keyX.keyId, // 15
  PhysicalKeyboardKey.digit7.usbHidUsage: LogicalKeyboardKey.keyC.keyId, // 16
  PhysicalKeyboardKey.digit8.usbHidUsage: LogicalKeyboardKey.keyV.keyId, // 17
  PhysicalKeyboardKey.digit0.usbHidUsage: LogicalKeyboardKey.keyB.keyId, // 19
  PhysicalKeyboardKey.minus.usbHidUsage: LogicalKeyboardKey.keyQ.keyId, // 20
  PhysicalKeyboardKey.equal.usbHidUsage: LogicalKeyboardKey.keyW.keyId, // 21
  PhysicalKeyboardKey.backspace.usbHidUsage: LogicalKeyboardKey.keyE.keyId,
  PhysicalKeyboardKey.tab.usbHidUsage: LogicalKeyboardKey.keyR.keyId, // 23
  PhysicalKeyboardKey.keyQ.usbHidUsage: LogicalKeyboardKey.keyY.keyId, // 24
  PhysicalKeyboardKey.keyW.usbHidUsage: LogicalKeyboardKey.keyT.keyId, // 25
  PhysicalKeyboardKey.keyS.usbHidUsage: LogicalKeyboardKey.keyO.keyId, // 39
  PhysicalKeyboardKey.keyD.usbHidUsage: LogicalKeyboardKey.keyU.keyId, // 40
  PhysicalKeyboardKey.keyG.usbHidUsage: LogicalKeyboardKey.keyI.keyId, // 42
  PhysicalKeyboardKey.keyH.usbHidUsage: LogicalKeyboardKey.keyP.keyId, // 43
  PhysicalKeyboardKey.keyK.usbHidUsage: LogicalKeyboardKey.keyL.keyId, // 45
  PhysicalKeyboardKey.keyL.usbHidUsage: LogicalKeyboardKey.keyJ.keyId, // 46
  PhysicalKeyboardKey.quote.usbHidUsage: LogicalKeyboardKey.keyK.keyId, // 48
  PhysicalKeyboardKey.keyX.usbHidUsage: LogicalKeyboardKey.keyN.keyId, // 53
  PhysicalKeyboardKey.keyC.usbHidUsage: LogicalKeyboardKey.keyM.keyId, // 54
};

/// XQuartz's digit-row keys, by the physical key the embedder reports for
/// them, as their digit (`kVK_ANSI_1` is 0x12, so 1 is keycode 26, the evdev
/// E key).
final Map<int, int> _xquartzDigitByPhysical = <int, int>{
  PhysicalKeyboardKey.keyE.usbHidUsage: LogicalKeyboardKey.digit1.keyId, // 26
  PhysicalKeyboardKey.keyR.usbHidUsage: LogicalKeyboardKey.digit2.keyId, // 27
  PhysicalKeyboardKey.keyT.usbHidUsage: LogicalKeyboardKey.digit3.keyId, // 28
  PhysicalKeyboardKey.keyY.usbHidUsage: LogicalKeyboardKey.digit4.keyId, // 29
  PhysicalKeyboardKey.keyU.usbHidUsage: LogicalKeyboardKey.digit6.keyId, // 30
  PhysicalKeyboardKey.keyI.usbHidUsage: LogicalKeyboardKey.digit5.keyId, // 31
  PhysicalKeyboardKey.keyP.usbHidUsage: LogicalKeyboardKey.digit9.keyId, // 33
  PhysicalKeyboardKey.bracketLeft.usbHidUsage:
      LogicalKeyboardKey.digit7.keyId, // 34
  PhysicalKeyboardKey.enter.usbHidUsage: LogicalKeyboardKey.digit8.keyId, // 36
  PhysicalKeyboardKey.controlLeft.usbHidUsage:
      LogicalKeyboardKey.digit0.keyId, // 37
};

/// Rewrites the logical key of the key data [installLinuxKeyEventRepair]
/// passes through.
///
/// A key press is repaired when its character is one of the control
/// characters above and its logical key is a printable key (one in the
/// Unicode plane). A printable logical key with a control character can only
/// come from a misread keycode: a numpad Enter, whose character is also
/// `"\r"`, keeps its own logical key because that key is not printable. The
/// repeats and the release of a repaired press carry the same repaired key,
/// matched by physical key, because a release has no character of its own.
///
/// When [xquartzKeycodes] is set, letters are repaired too: see
/// [installLinuxKeyEventRepair].
@visibleForTesting
class LinuxKeyEventRepair {
  /// A repair; letters are repaired only when [xquartzKeycodes] is true.
  LinuxKeyEventRepair({this.xquartzKeycodes = false});

  /// Whether the display is XQuartz, whose keycodes are the Mac virtual key
  /// codes plus 8. Set once the X server has been read.
  bool xquartzKeycodes;

  final Map<int, int> _repairedByPhysical = <int, int>{};

  /// Returns [data], or a copy of it with the repaired logical key.
  ui.KeyData repair(ui.KeyData data) {
    switch (data.type) {
      case ui.KeyEventType.down:
        final repaired =
            _controlKeyFor(data) ??
            (xquartzKeycodes ? _xquartzKeyFor(data) : null);
        if (repaired == null) {
          _repairedByPhysical.remove(data.physical);
          return data;
        }
        _repairedByPhysical[data.physical] = repaired;
        return _withLogical(data, repaired);
      case ui.KeyEventType.repeat:
        final repaired = _repairedByPhysical[data.physical];
        return repaired == null ? data : _withLogical(data, repaired);
      case ui.KeyEventType.up:
        final repaired = _repairedByPhysical.remove(data.physical);
        return repaired == null ? data : _withLogical(data, repaired);
    }
  }

  static int? _controlKeyFor(ui.KeyData data) {
    final character = data.character;
    if (character == null) return null;
    final control = _controlKeys[character];
    if (control == null || data.logical == control.keyId) return null;
    final printable =
        data.logical != 0 &&
        data.logical & LogicalKeyboardKey.planeMask ==
            LogicalKeyboardKey.unicodePlane;
    return printable ? control.keyId : null;
  }

  /// The logical key of a key press on an XQuartz display, when the
  /// embedder's differs from it.
  ///
  /// The embedder looks for every Latin letter and digit on the keycodes of
  /// an evdev keyboard, and places the ones it does not find at their evdev
  /// keycodes. On XQuartz it misses A, S, E, R, 8 and 0, and places them on
  /// the keys that type `]`, O, 1, 2, V and B. So:
  ///
  /// What the embedder gives each key on an evdev display, by the same rules,
  /// with XQuartz's positions:
  ///
  /// - A key that types a Latin letter or a digit gets that letter (in lower
  ///   case) or digit.
  /// - Any other key on the Mac's digit row gets its digit: the `!` of the 1
  ///   key, AZERTY's `&` and `é`, and a non-Latin character there.
  /// - A key that types a non-Latin character gets the US key of its position
  ///   on the Mac keyboard (a Latin letter, or `[`, `;` and the like), as on
  ///   an evdev display the embedder gives it the key of its position on a US
  ///   keyboard.
  /// - A key that types another Latin character but is reported as a letter
  ///   was given a letter it does not carry (XQuartz's `]` key reports A, and
  ///   with a layout that has no N the space bar reports N). It gets the key
  ///   of the character it types.
  /// - Anything else keeps its logical key.
  static int? _xquartzKeyFor(ui.KeyData data) {
    final runes = data.character?.runes;
    if (runes == null || runes.length != 1) return null;
    final rune = runes.first;
    final int? key;
    if (_isLatinLetter(rune) || _isDigit(rune)) {
      key = _lowerCase(rune);
    } else if (_xquartzDigitByPhysical[data.physical] case final digit?
        when _isPrintable(rune)) {
      key = digit;
    } else if (rune > 0xff) {
      key = _xquartzUsKeyByPhysical[data.physical];
    } else if (_isPrintable(rune) && _isLetterKey(data.logical)) {
      key = _lowerCase(rune);
    } else {
      key = null;
    }
    return key == data.logical ? null : key;
  }

  static bool _isLetterKey(int logical) =>
      logical >= LogicalKeyboardKey.keyA.keyId &&
      logical <= LogicalKeyboardKey.keyZ.keyId;

  static bool _isLatinLetter(int code) =>
      (code >= 0x61 && code <= 0x7a) || (code >= 0x41 && code <= 0x5a);

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  /// A character a key types, as opposed to a control character.
  static bool _isPrintable(int code) =>
      (code >= 0x20 && code < 0x7f) || code >= 0xa0;

  /// The embedder's lower case for a Latin-1 character, which is how it names
  /// a printable key. Its `to_lower` shifts all of 0xC0 to 0xDE, `×` too, so
  /// this does as well: the key must match what an evdev display reports.
  static int _lowerCase(int code) {
    final upper =
        (code >= 0x41 && code <= 0x5a) || (code >= 0xc0 && code <= 0xde);
    return upper ? code + 0x20 : code;
  }

  static ui.KeyData _withLogical(ui.KeyData data, int logical) => ui.KeyData(
    timeStamp: data.timeStamp,
    type: data.type,
    physical: data.physical,
    logical: logical,
    character: data.character,
    synthesized: data.synthesized,
    deviceType: data.deviceType,
  );
}
