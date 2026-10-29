// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

#ifndef CRUX_FILE_DIALOGS_H_
#define CRUX_FILE_DIALOGS_H_

#include <flutter_linux/flutter_linux.h>

// Runner support for file dialogs on a Linux session displayed remotely (ssh
// X forwarding, VNC, ETX or NX, or a farm job started from another host),
// where the desktop services a local session provides are missing or belong
// to another machine. Every product's Linux runner compiles this file, the
// open core's and the Pro overlay's alike, so they all behave the same.

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
