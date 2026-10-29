// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The static check each product runs from `test/static/` to hold its Linux
/// runner to the file-dialog channel: the runner compiles
/// `crux_file_dialogs.cc`, links X11, and registers the channel and the bell
/// handler after its plugins.
///
/// Plain string checks over the three files, with no Flutter import, so a
/// pure Dart test can call it.
library;

export 'src/runner_guard.dart';
