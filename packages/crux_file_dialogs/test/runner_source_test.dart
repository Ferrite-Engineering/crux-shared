// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The runner half of the file dialogs is C++ that no test here compiles; the
// Linux launch test in each product does that. These checks hold the two
// halves to one contract: the same channel name, the same method names, and a
// chooser that never goes through the portal.

import 'dart:io';

import 'package:crux_file_dialogs/crux_file_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final header = File('native/linux/crux_file_dialogs.h').readAsStringSync();
  final source = File('native/linux/crux_file_dialogs.cc').readAsStringSync();
  final dart = File('lib/src/gtk_file_picker.dart').readAsStringSync();

  test('the header names the channel the Dart side calls', () {
    expect(
      header,
      contains('#define CRUX_FILE_DIALOG_CHANNEL "$kCruxFileDialogChannel"'),
    );
    expect(source, contains('CRUX_FILE_DIALOG_CHANNEL,'));
  });

  test('every method the Dart side sends is one the runner answers', () {
    final sent = RegExp(
      r"_show\(\s*'(\w+)'",
    ).allMatches(dart).map((m) => m.group(1)).toSet();
    expect(sent, <String>{'open', 'save', 'directory'});
    for (final method in sent) {
      expect(source, contains('strcmp(method, "$method") == 0'));
    }
  });

  // GtkFileChooserNative goes through the portal when GTK_USE_PORTAL is set,
  // which is the failure this package exists to avoid.
  test('the runner draws a GtkFileChooserDialog, never the native one', () {
    expect(source, contains('gtk_file_chooser_dialog_new('));
    expect(source, isNot(contains('gtk_file_chooser_native_new')));
  });

  test(
    'the bell handler drops only BadAccess on a bell and chains the rest',
    () {
      expect(source, contains('bell && event->error_code == BadAccess'));
      expect(source, contains('gdk_x_error_handler(display, event)'));
    },
  );

  test('a display on another machine gets the software renderer', () {
    expect(header, contains('void crux_select_renderer_for_display('));
    expect(source, contains('x_display_is_remote(gdk_display_get_name('));
    expect(source, contains('g_setenv("FLUTTER_LINUX_RENDERER", "software"'));
  });

  test('with no session bus, the accessibility bridge is turned off', () {
    expect(
      header,
      contains('void crux_skip_accessibility_bridge_without_session_bus('),
    );
    expect(source, contains('g_bus_get_sync(G_BUS_TYPE_SESSION'));
    expect(source, contains('g_setenv("NO_AT_BRIDGE", "1"'));
  });

  test('with only DISPLAY set, GTK is limited to X11', () {
    expect(
      header,
      contains('void crux_prefer_x11_when_only_display_is_set('),
    );
    expect(source, contains('g_getenv("GDK_BACKEND") != nullptr'));
    expect(source, contains('g_getenv("WAYLAND_DISPLAY")'));
    expect(source, contains('gdk_set_allowed_backends("x11")'));
  });
}
