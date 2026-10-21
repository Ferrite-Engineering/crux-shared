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

/// The containment key of the absolute path [absolute]: the deepest existing
/// prefix as spelled, resolved by the filesystem, with the rest appended as
/// written; null when it has none. See `containmentKey`.
String? hostContainmentKey(String absolute) {
  try {
    var head = absolute;
    final remainder = <String>[];
    while (FileSystemEntity.typeSync(head, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(head);
      if (parent == head) return null;
      remainder.insert(0, p.basename(head));
      head = parent;
    }
    if (remainder.contains('..')) return null;
    final resolved = File(head).resolveSymbolicLinksSync();
    final joined = p.normalize(p.joinAll(<String>[resolved, ...remainder]));
    return hostFilesystemIsCaseInsensitive() ? joined.toLowerCase() : joined;
  } on FileSystemException {
    return null;
  }
}
