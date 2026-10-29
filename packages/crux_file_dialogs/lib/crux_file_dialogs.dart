// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// File dialogs on Linux that work on a remote display.
///
/// `GtkFilePicker` replaces file_picker's Linux implementation, which needs
/// the XDG desktop portal over a DBus session bus, with GTK file choosers the
/// app's own runner draws in-process. `useGtkFileDialogsOnLinux` installs it
/// from a product's `bootstrap()`. The runner half is the C++ in this
/// package's `native/linux/`, compiled by every product's Linux runner.
library;

export 'src/gtk_file_picker.dart'
    show GtkFilePicker, kCruxFileDialogChannel, useGtkFileDialogsOnLinux;
