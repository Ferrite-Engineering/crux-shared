// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A host without `dart:io` — a browser. It has no process environment and no
/// filesystem, so there is never a policy file to find.
library;

/// The process environment: none.
Map<String, String> hostEnvironment() => const <String, String>{};

/// The host operating system. No `Platform` to ask, so a name no platform
/// switch matches.
String hostOperatingSystem() => 'web';

/// Whether a file exists at [path]: never, with no filesystem.
bool hostFileExists(String path) => false;

/// The contents of the file at [path]. Unreachable in practice, because
/// [hostFileExists] is always false; throws rather than inventing contents.
String hostReadFile(String path) =>
    throw UnsupportedError('no filesystem to read $path from');

/// Whether [path] is writable by every user: no filesystem, so nothing is.
bool hostIsWorldWritable(String path) => false;
