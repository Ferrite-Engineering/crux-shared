// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/src/path_identity_host.dart';
import 'package:path/path.dart' as p;

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

/// The key a containment check compares for the absolute path [absolute], or
/// null when it has none and must be refused.
///
/// This is the path the filesystem would reach, so the filesystem does the
/// reading:
///
/// - **Existing prefix.** The deepest prefix of the path *as spelled* that
///   exists is resolved by the filesystem (`realpath` on POSIX): every link is
///   followed before the `..` that comes after it, as `open` does. Nothing is
///   normalised first. Collapsing `<root>/link/..` as text puts it in
///   `<root>` when the filesystem finds it beside the link's target, which is
///   how a link inside a root once opened a file outside it.
/// - **Remainder.** What does not exist yet is appended as written, and a
///   `..` in it has no key: the filesystem cannot walk a directory that does
///   not exist, and one created later could be a link.
/// - **Unresolvable.** A prefix that exists but cannot be resolved (a
///   dangling link, a loop) has no key. A write through a dangling link would
///   create its target wherever it points.
/// - **Case.** Folded where the filesystem folds it (macOS, Windows), drive
///   letters included.
///
/// Both sides of a comparison go through here, so a root spelled through a
/// link (macOS `/tmp` to `/private/tmp`) and a path spelled on the other side
/// of it agree, whether or not the path exists yet. Unlike [canonicalPathKey],
/// which fails soft because it compares, this fails closed because it
/// guards.
///
/// The key is a comparison value, never a path to open. In a browser it is
/// [absolute] unchanged, or null when it holds a `..` segment.
String? containmentKey(String absolute) {
  if (absolute.isEmpty || absolute.contains('\x00')) return null;
  return hostContainmentKey(absolute);
}

/// Whether [path] resolves to [root] or to somewhere inside it, by
/// [containmentKey] on both sides.
///
/// [path] must be absolute and is judged exactly as spelled: a relative path,
/// one with surrounding white space, an empty one or one holding a NUL is
/// never contained. [root] is made absolute against the working directory
/// first. Whole path components are compared, so `/work/project-old` is not
/// inside `/work/project`.
///
/// The answer describes the filesystem at the moment of the call: a process
/// that can write inside [root] can replace a directory with a link between
/// this check and an open. Check the value about to be opened, immediately
/// before opening it.
bool isPathWithin(String root, String path) =>
    containingRoot(path, <String>[root]) != null;

/// The first of [roots] that [path] resolves inside (see [isPathWithin]), or
/// null when none does. Blank roots are skipped.
String? containingRoot(String path, Iterable<String> roots) {
  if (path.isEmpty || path.trim() != path) return null;
  if (!p.isAbsolute(path) || p.isRootRelative(path)) return null;
  final key = containmentKey(path);
  if (key == null) return null;
  for (final root in roots) {
    if (root.trim().isEmpty) continue;
    final String absoluteRoot;
    try {
      absoluteRoot = p.absolute(root);
    } on Object {
      continue;
    }
    final rootKey = containmentKey(absoluteRoot);
    if (rootKey == null) continue;
    if (key == rootKey || p.isWithin(rootKey, key)) return root;
  }
  return null;
}
