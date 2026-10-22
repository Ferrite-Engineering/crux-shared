// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:path/path.dart' as p;

/// [path] in posix form: forward slashes and no `.` or doubled separators.
///
/// A scanned file is named with the host's separator, so on Windows it comes
/// back as `lib\services\foo.dart`, while a pin or an allowlist entry is
/// written once, the way every other path in a consuming repo's guard test is
/// written: `lib/services/foo.dart`. Both sides go through here before they
/// are compared, so an entry reads the same on every host.
String cruxPosixPath(String path) =>
    p.posix.normalize(path.replaceAll(r'\', '/'));

/// Whether the file a guard scanned and the file a pin or allowlist entry
/// names are one file: either path ends with the other, compared in posix
/// form.
///
/// Suffix rather than equality because the scan root differs by caller, so a
/// product pins `lib/services/foo.dart` and a package-level scan names the
/// same file `foo.dart`.
bool cruxPathsMatch(String scanned, String pinned) {
  final a = cruxPosixPath(scanned);
  final b = cruxPosixPath(pinned);
  return a.endsWith(b) || b.endsWith(a);
}
