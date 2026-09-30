// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether the platform's default filesystem ignores case: macOS and Windows.
bool hostFilesystemIsCaseInsensitive() =>
    Platform.isMacOS || Platform.isWindows;

/// Absolute, normalized and (when [resolveSymlinks]) symlink-resolved form of
/// [trimmed], failing soft at every step.
String hostCanonicalizePath(String trimmed, {required bool resolveSymlinks}) {
  var result = trimmed;
  try {
    result = p.normalize(p.absolute(trimmed));
  } on Object {
    // p.absolute reads Directory.current, which can throw if the working
    // directory has been deleted out from under the process.
    return trimmed;
  }

  if (!resolveSymlinks) return result;
  try {
    // Defined on FileSystemEntity, so this resolves directories and links as
    // well as regular files. Throws when the path does not exist, which is a
    // normal case here (a workspace document can outlive its file).
    return File(result).resolveSymbolicLinksSync();
  } on Object {
    return result;
  }
}
