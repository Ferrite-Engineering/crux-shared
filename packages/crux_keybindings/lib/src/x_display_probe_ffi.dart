// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crux_keybindings/src/x_display_facts.dart';
import 'package:ffi/ffi.dart';

typedef _XOpenDisplayC = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _XServerVendorC = Pointer<Utf8> Function(Pointer<Void>);
typedef _XListExtensionsC =
    Pointer<Pointer<Utf8>> Function(Pointer<Void>, Pointer<Int>);
typedef _XFreeExtensionListC = Int Function(Pointer<Pointer<Utf8>>);
typedef _XFreeExtensionListDart = int Function(Pointer<Pointer<Utf8>>);
typedef _XkbKeycodeToKeysymC =
    UnsignedLong Function(Pointer<Void>, Uint8, Int, Int);
typedef _XkbKeycodeToKeysymDart = int Function(Pointer<Void>, int, int, int);
typedef _XCloseDisplayC = Int Function(Pointer<Void>);
typedef _XCloseDisplayDart = int Function(Pointer<Void>);

/// Reads [XDisplayFacts] from the X server named by `DISPLAY`, or null when
/// this is not Linux, there is no `DISPLAY`, libX11 cannot be loaded or the
/// server cannot be reached. Never throws.
///
/// It opens its own short connection (the same server the app's window is
/// on) on a background isolate, because over `ssh -Y` the connection costs a
/// network round trip the UI should not wait for.
Future<XDisplayFacts?> readXDisplayFacts() async {
  if (!Platform.isLinux) return null;
  final display = Platform.environment['DISPLAY'];
  if (display == null || display.isEmpty) return null;
  try {
    return await Isolate.run(_readFacts);
  } on Object catch (_) {
    return null;
  }
}

XDisplayFacts? _readFacts() {
  final DynamicLibrary x11;
  try {
    x11 = DynamicLibrary.open('libX11.so.6');
  } on Object catch (_) {
    return null;
  }
  final openDisplay = x11.lookupFunction<_XOpenDisplayC, _XOpenDisplayDart>(
    'XOpenDisplay',
  );
  final serverVendor = x11.lookupFunction<_XServerVendorC, _XServerVendorC>(
    'XServerVendor',
  );
  final listExtensions = x11
      .lookupFunction<_XListExtensionsC, _XListExtensionsC>('XListExtensions');
  final freeExtensionList = x11
      .lookupFunction<_XFreeExtensionListC, _XFreeExtensionListDart>(
        'XFreeExtensionList',
      );
  final keycodeToKeysym = x11
      .lookupFunction<_XkbKeycodeToKeysymC, _XkbKeycodeToKeysymDart>(
        'XkbKeycodeToKeysym',
      );
  final closeDisplay = x11.lookupFunction<_XCloseDisplayC, _XCloseDisplayDart>(
    'XCloseDisplay',
  );

  final dpy = openDisplay(nullptr);
  if (dpy == nullptr) return null;
  final count = calloc<Int>();
  try {
    final vendorPointer = serverVendor(dpy);
    final vendor = vendorPointer == nullptr ? '' : vendorPointer.toDartString();
    final extensions = <String>[];
    final list = listExtensions(dpy, count);
    if (list != nullptr) {
      for (var i = 0; i < count.value; i++) {
        extensions.add(list[i].toDartString());
      }
      freeExtensionList(list);
    }
    return XDisplayFacts(
      vendor: vendor,
      extensions: extensions,
      keysymAtKeycode61: keycodeToKeysym(dpy, 61, 0, 0),
    );
  } finally {
    calloc.free(count);
    closeDisplay(dpy);
  }
}
