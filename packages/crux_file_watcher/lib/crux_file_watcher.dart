// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// File-system watcher with debounced events for the EDACrux suite.
///
/// Wraps `dart:io` file-system watching with a bounded debounce and a clean
/// event model. Events are coalesced over a 500-ms quiet period, but the wait
/// is capped at 2 s so a continuously-written file (a simulator streaming into
/// a dump) still reports changes instead of resetting the debounce forever.
///
/// A watch that dies on its own — deleted parent directory, dropped platform
/// watch, a path whose parent never existed — is reported on
/// `FileWatcherService.stopped` so the host can take down its "auto-reload on"
/// affordance and offer a re-arm.
///
/// On Flutter Web (where `dart:io` file watching is unavailable),
/// `FileWatcherService.startWatching` is a no-op.
library;

export 'src/file_watcher_service.dart';
