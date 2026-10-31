// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puts the right logical key back on Backspace, Tab, Enter, Escape and
/// Delete when the app runs on an X display whose keycodes are not the evdev
/// keycodes Flutter's Linux embedder expects.
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
/// The repair sits in front of the framework's own key data handler, so
/// [HardwareKeyboard] handlers, `Shortcuts` and text fields all see the
/// repaired key. Call once, after `WidgetsFlutterBinding.ensureInitialized()`.
/// It does nothing anywhere but Linux, and on Linux it changes nothing on an
/// evdev display, where every key's logical key already agrees with its
/// character. Calling it again does nothing.
void installLinuxKeyEventRepair() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
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
  bool repairing(ui.KeyData data) => inner(repair.repair(data));
  dispatcher.onKeyData = _installed = repairing;
  return true;
}

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
@visibleForTesting
class LinuxKeyEventRepair {
  final Map<int, int> _repairedByPhysical = <int, int>{};

  /// Returns [data], or a copy of it with the repaired logical key.
  ui.KeyData repair(ui.KeyData data) {
    switch (data.type) {
      case ui.KeyEventType.down:
        final repaired = _repairFor(data);
        if (repaired == null) {
          _repairedByPhysical.remove(data.physical);
          return data;
        }
        _repairedByPhysical[data.physical] = repaired.keyId;
        return _withLogical(data, repaired.keyId);
      case ui.KeyEventType.repeat:
        final repaired = _repairedByPhysical[data.physical];
        return repaired == null ? data : _withLogical(data, repaired);
      case ui.KeyEventType.up:
        final repaired = _repairedByPhysical.remove(data.physical);
        return repaired == null ? data : _withLogical(data, repaired);
    }
  }

  static LogicalKeyboardKey? _repairFor(ui.KeyData data) {
    final character = data.character;
    if (character == null) return null;
    final control = _controlKeys[character];
    if (control == null || data.logical == control.keyId) return null;
    final printable =
        data.logical != 0 &&
        data.logical & LogicalKeyboardKey.planeMask ==
            LogicalKeyboardKey.unicodePlane;
    return printable ? control : null;
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
