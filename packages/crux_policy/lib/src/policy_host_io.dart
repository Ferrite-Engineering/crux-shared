// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// The process environment.
Map<String, String> hostEnvironment() => Platform.environment;

/// The host operating system, in `Platform.operatingSystem` vocabulary.
String hostOperatingSystem() => Platform.operatingSystem;

/// Whether a file exists at [path].
bool hostFileExists(String path) => File(path).existsSync();

/// The contents of the file at [path]. Throws when it cannot be read.
String hostReadFile(String path) => File(path).readAsStringSync();

/// Whether the file system object at [path] is writable by every user.
///
/// POSIX only: the `o+w` bit. On Windows the mode bits `dart:io` reports carry
/// no such meaning, and the installer's ACL on `%ProgramData%\EDACrux` is the
/// control instead — so the answer there is `false`, never a guess. Anything
/// that does not exist or cannot be examined is also `false`: this decides
/// whether to *distrust* a path, and a path that cannot be read is refused
/// upstream for that reason rather than this one.
bool hostIsWorldWritable(String path) {
  if (Platform.isWindows) return false;
  try {
    final stat = FileStat.statSync(path);
    if (stat.type == FileSystemEntityType.notFound) return false;
    return (stat.mode & 0x2) != 0;
  } on Object {
    return false;
  }
}
