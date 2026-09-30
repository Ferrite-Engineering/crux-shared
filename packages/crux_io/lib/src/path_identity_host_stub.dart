// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A host without `dart:io` — a browser. There is no filesystem, no working
/// directory and no symlink, and a location is an uploaded file's name or a
/// URL.
library;

/// Case matters: there is no case-folding filesystem, and a URL's path is
/// case-sensitive.
bool hostFilesystemIsCaseInsensitive() => false;

/// [trimmed] itself. A browser location is already its own identity: there is
/// nothing to resolve a relative name against, and normalising dot segments
/// would change what a URL names.
String hostCanonicalizePath(String trimmed, {required bool resolveSymlinks}) =>
    trimmed;
