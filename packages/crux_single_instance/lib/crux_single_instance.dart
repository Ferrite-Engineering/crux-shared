// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Single-instance link delivery for the EDACrux desktop apps on Windows and
/// Linux.
///
/// macOS delivers a URL to the running application. Windows and Linux start
/// a new process with the URL as its argument instead, so every link opened a
/// new window. `SingleInstance.claim` makes the new process hand its link to
/// the running instance and exit: over a Unix domain socket in a directory
/// private to the user on Linux, and over a token-guarded `127.0.0.1` socket
/// on Windows. The design is in this package's README.
///
/// Pure Dart (`dart:io`, plus `chmod` through `dart:ffi`), no Flutter.
library;

export 'src/link_policy.dart';
export 'src/rendezvous.dart' show SingleInstanceTransport;
export 'src/single_instance.dart';
