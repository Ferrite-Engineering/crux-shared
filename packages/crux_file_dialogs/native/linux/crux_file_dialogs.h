// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

#ifndef CRUX_FILE_DIALOGS_H_
#define CRUX_FILE_DIALOGS_H_

#include <flutter_linux/flutter_linux.h>

// Runner support for a Linux session displayed remotely (ssh X forwarding,
// VNC, ETX or NX, or a farm job started from another host), where the desktop
// services a local session provides are missing or belong to another machine:
// the renderer choice, the accessibility bridge and the file dialogs. Every product's Linux runner compiles this file, the
// open core's and the Pro overlay's alike, so they all behave the same.

// Turns off GTK's accessibility bridge when no DBus session bus can be
// reached. The bridge looks for the accessibility bus through the session
// bus, and without one it only fails, noisily, on every window. A value the
// user has set for NO_AT_BRIDGE is left alone. [app_name] starts the line
// written to standard error when it does. GTK reads the variable while it
// initializes, so call this before the application runs.
void crux_skip_accessibility_bridge_without_session_bus(const gchar* app_name);

// Chooses the software renderer when OpenGL would be slow or absent: when the
// X display is on another machine, so every OpenGL frame crosses the network,
// or when the display cannot create an OpenGL context at all. A value the
// user has set for FLUTTER_LINUX_RENDERER, "opengl" included, is left alone.
// [app_name] starts the line written to standard error when it switches. The
// engine reads the variable when it is created, inside fl_view_new, so call
// this before that.
void crux_select_renderer_for_display(const gchar* app_name);

// The method channel crux_file_dialogs' GtkFilePicker calls. The Dart side
// names it kCruxFileDialogChannel, and a test holds the two spellings equal.
#define CRUX_FILE_DIALOG_CHANNEL "crux/file_dialog"

// Serves CRUX_FILE_DIALOG_CHANNEL with GTK file choosers drawn in this
// process, on the display the window is on. file_picker's own Linux code asks
// the XDG desktop portal to draw them over the DBus session bus instead, which
// fails when no bus is reachable and, when one is, can open the dialog on
// another machine's screen. Call once, after fl_register_plugins.
void crux_register_file_dialog_channel(FlView* view);

// Keeps an X server's refusal of the alert sound from ending the process.
// `ssh -X` forwards the app as an untrusted client, and the X SECURITY
// extension answers its Bell requests with BadAccess, which GDK's default X
// error handler treats as fatal. The GTK file chooser rings the bell itself
// (a typed path that matches nothing), so every runner that serves the
// channel above needs this too. [app_name] starts the one line written to
// standard error when it first happens. Call once GTK has opened the display.
void crux_tolerate_refused_x_bell(const gchar* app_name);

#endif  // CRUX_FILE_DIALOGS_H_
