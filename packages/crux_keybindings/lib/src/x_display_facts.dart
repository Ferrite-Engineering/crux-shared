// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// What the X server behind `DISPLAY` says about itself, read once at
/// startup: enough to tell whether its keycodes are XQuartz's.
@immutable
class XDisplayFacts {
  /// Facts as read from the server.
  const XDisplayFacts({
    required this.vendor,
    required this.extensions,
    required this.keysymAtKeycode61,
  });

  /// The server's vendor string (`ServerVendor`, as `xdpyinfo` prints it).
  final String vendor;

  /// The names of the extensions the server supports (`XListExtensions`).
  final List<String> extensions;

  /// The keysym at keycode 61 without modifiers, or 0 when it has none.
  final int keysymAtKeycode61;

  /// Extensions only XQuartz carries: its window-manager and DRI extensions.
  /// An XQuartz build may report the X.Org vendor string, so these count as
  /// the mark of XQuartz too.
  static const Set<String> xquartzExtensions = <String>{
    'Apple-WM',
    'Apple-DRI',
  };

  /// The Escape keysym, `XK_Escape`.
  static const int escapeKeysym = 0xff1b;

  /// Whether the server is XQuartz and its keycodes are the Mac virtual key
  /// codes plus 8.
  ///
  /// Both must hold. XQuartz is recognised by its vendor string or by one of
  /// its own extensions. Its keycode table is confirmed by Escape: Mac virtual
  /// key code 53, so keycode 61, where an evdev keyboard has the slash key.
  /// Escape sits there on every Mac layout, so the check does not depend on
  /// which letters the layout types. Anything else, including a server that
  /// could not be read, is not XQuartz, and keys are left as the embedder
  /// reports them.
  bool get hasXQuartzKeycodes {
    final xquartz =
        vendor.toLowerCase().contains('xquartz') ||
        extensions.any(xquartzExtensions.contains);
    return xquartz && keysymAtKeycode61 == escapeKeysym;
  }

  @override
  String toString() =>
      'XDisplayFacts(vendor: $vendor, extensions: $extensions, '
      'keysymAtKeycode61: 0x${keysymAtKeycode61.toRadixString(16)})';
}
