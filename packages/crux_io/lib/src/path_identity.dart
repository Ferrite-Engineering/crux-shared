// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/src/path_identity_host.dart';

/// Whether the platform's default filesystem treats `Foo.txt` and `foo.txt`
/// as the same file.
///
/// This is a platform heuristic, not a per-volume probe: macOS (APFS) and
/// Windows (NTFS) default to case-insensitive, Linux to case-sensitive. A
/// case-*sensitive* macOS volume exists and would be judged wrongly here, so
/// the trade is deliberate — treating two paths that differ only in case as
/// one project is right on the overwhelming majority of machines, and being
/// wrong costs a user one merged tab rather than a lost file. Probing the
/// actual volume would mean a filesystem write on every comparison.
///
/// `false` in a browser, which has no filesystem to fold case, and whose URLs
/// are case-sensitive.
bool get filesystemIsCaseInsensitive => hostFilesystemIsCaseInsensitive();

/// Resolves [path] to the absolute, normalized, symlink-free form used to
/// decide whether two paths name the same file.
///
/// Applies, in order:
///
/// 1. **Absolute** — a relative path is resolved against the current working
///    directory. A shell handing an app `./design.vcd` and a restored
///    document holding `/home/u/design.vcd` name one file.
/// 2. **Normalized** — `.` and `..` segments collapse and a trailing
///    separator is dropped, so `/a/b/../b/x` and `/a/b/x/` converge.
/// 3. **Symlink-resolved** — best effort. On macOS this is what makes
///    `/tmp/x` and `/private/tmp/x` the same path.
///
/// Fails soft at every step: an unreadable or not-yet-existing path returns
/// the best form reached so far rather than throwing. Callers are comparing
/// paths, not opening them, and a path that cannot be resolved must still
/// compare equal to itself.
///
/// Case is **preserved** — this returns a path, not a comparison key. Use
/// [canonicalPathKey] to compare.
///
/// **In a browser** the answer is [path] trimmed and nothing more. There is no
/// working directory to make it absolute against and no filesystem to resolve
/// links in, and a web location — an uploaded file's name, a URL, a `blob:` id
/// — is already canonical. Dot segments are left alone there too: normalising
/// would rewrite a URL's query string, changing what it names.
String canonicalizePath(String path, {bool resolveSymlinks = true}) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return '';
  return hostCanonicalizePath(trimmed, resolveSymlinks: resolveSymlinks);
}

/// Canonical comparison key for [path] — [canonicalizePath] plus case folding
/// on filesystems that ignore case.
///
/// Two paths naming the same file produce the same key; that is the whole
/// contract. The key is **not** a usable path on a case-insensitive platform
/// and must never be stored, displayed, or opened — keep the user's original
/// string for that and use the key only to compare.
///
/// Pass [caseInsensitive] to pin the behaviour in tests; it defaults to
/// [filesystemIsCaseInsensitive].
///
/// Never throws, in a browser included, where the key is the trimmed location
/// with its case preserved unless [caseInsensitive] is `true`.
String canonicalPathKey(
  String path, {
  bool? caseInsensitive,
  bool resolveSymlinks = true,
}) {
  final canonical = canonicalizePath(path, resolveSymlinks: resolveSymlinks);
  if (canonical.isEmpty) return '';
  final fold = caseInsensitive ?? filesystemIsCaseInsensitive;
  return fold ? canonical.toLowerCase() : canonical;
}

/// Whether [a] and [b] name the same file, per [canonicalPathKey].
///
/// Two empty (or whitespace-only) paths are *not* the same file: an absent
/// path is unknown, not a shared identity. Collapsing that distinction is how
/// every unsaved document in an app becomes "the same document".
///
/// In a browser this compares the two locations trimmed, case-sensitively
/// unless [caseInsensitive] is `true` — see [canonicalizePath].
bool isSamePath(
  String a,
  String b, {
  bool? caseInsensitive,
  bool resolveSymlinks = true,
}) {
  final keyA = canonicalPathKey(
    a,
    caseInsensitive: caseInsensitive,
    resolveSymlinks: resolveSymlinks,
  );
  if (keyA.isEmpty) return false;
  final keyB = canonicalPathKey(
    b,
    caseInsensitive: caseInsensitive,
    resolveSymlinks: resolveSymlinks,
  );
  return keyA == keyB;
}
