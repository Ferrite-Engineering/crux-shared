// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:edacrux_cxp/edacrux_cxp_listener.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The receiver-side rule for a path a peer asked this process to open.
///
/// CXP §11 puts two obligations on a receiver of `request_open_source` and
/// `request_open_artifact`: it **SHOULD** treat the path as a hint, resolve
/// it against directories the user has already opened, and refuse paths
/// outside them; and it **MUST** apply the same rule to an artifact it
/// resolved through its own records as to a `file_path` on the wire, and
/// apply it to the value it is about to open rather than the value it
/// looked up. This class is that rule, written once so every product
/// applies the same one.
///
/// `LocalCxpServer` applies it before a request reaches the product: a
/// `request_open_source` whose `file_path` is refused is acknowledged
/// `honored: false` with the reason and never dispatched, and a
/// `request_open_artifact` whose `path` hint is refused is dispatched with
/// the hint removed. `CxpWorkspaceStore` applies it to what it resolves.
/// Neither is the value *about to be opened* — that is in the product,
/// after any symlink or record could have changed — so a product calls
/// [refuse] once more on the final path, immediately before opening it.
///
/// ### The two tiers
///
/// Without [roots] the rule is the floor: the path must be absolute and
/// well-formed. That is what every product enforced on its own before this
/// class existed (some on one of the two requests, none on both), and it
/// refuses the shapes an argv element must never take — a relative path,
/// an option-looking string, a NUL.
///
/// With [roots] the rule is the spec's: the path, canonicalised, must lie
/// inside one of the directories the callback returns, canonicalised the
/// same way (`crux_io`'s `containmentKey` says what canonical means here).
/// The callback is consulted on every check so it can read live session
/// state. A callback
/// that returns nothing means nothing is open, and everything is refused.
///
/// ### The value checked is the value opened
///
/// Both tiers judge [refuse]'s argument exactly as spelled, and a caller
/// opens that same string. Nothing is trimmed or respelled first: a check
/// that trimmed passed `" /etc/hosts"` as absolute while the untrimmed
/// string — relative as written — went on to the product. A path that
/// begins or ends with white space is refused instead of repaired. Leading
/// white space makes it relative as spelled, which the floor refuses
/// anyway; trailing white space is part of a POSIX file name, so trimming
/// it would open a different file than the one named, and Windows strips
/// it when it opens, so keeping it would name one file two ways. No Crux
/// product writes such a path.
///
/// ### Network and device paths on Windows
///
/// A `\\server\share\…`, `\\?\…` or `\\.\…` path is judged on its spelling
/// alone, before the filesystem is asked anything: resolving it would open
/// an SMB connection to a server the peer chose, which can offer the user's
/// credentials to it. Such a path is refused in both tiers, unless one of
/// [roots] begins with the same `\\server\share`, in which case it goes on
/// to the ordinary containment check.
///
/// ### What a check cannot promise
///
/// The answer describes the filesystem at the moment [refuse] ran. A
/// process that can write inside an open directory can replace a directory
/// with a link between the check and the open, and the open then follows
/// the link. Calling [refuse] on the final string immediately before
/// opening narrows that window; closing it needs an open that refuses to
/// leave a directory handle (`openat2` with `RESOLVE_BENEATH` on Linux),
/// which `dart:io` does not offer. Such a process already has the user's
/// file access, which CXP trusts (§11.1); a peer that can only send frames
/// cannot move files.
///
/// Reasons are fixed strings that never repeat the path: they travel back
/// to the sender in an ack's `reason` (§9.11), and echoing sender-chosen
/// input into another application's interface is what that section warns
/// against.
@immutable
class CxpPathContainment {
  /// Creates the rule. See the class doc for what [roots] changes.
  const CxpPathContainment({this.roots});

  /// Directories the user has opened in this session, consulted on every
  /// check. Null: the floor rule only. Returning nothing: refuse everything.
  final Iterable<String> Function()? roots;

  /// Null when [path] may be opened; otherwise why it may not, written for
  /// an ack's `reason`.
  String? refuse(String path) {
    if (path.trim().isEmpty) return 'file_path is empty';
    if (path.contains('\x00')) {
      return 'file_path contains a NUL character';
    }
    if (path.trim() != path) {
      return 'file_path begins or ends with white space';
    }
    // `\foo` on Windows is rooted but not absolute; refuse it with the
    // relative forms — a receiver cannot know which drive was meant.
    if (!p.isAbsolute(path) || p.isRootRelative(path)) {
      return 'file_path must be an absolute path';
    }
    final openRoots = roots?.call().toList();
    // Before anything below asks the filesystem about the path: on Windows
    // that question, for a `\\server\share` path, is an SMB connection to a
    // server the peer chose.
    final network = cxpNetworkPathRefusal(
      path,
      windows: Platform.isWindows,
      roots: openRoots,
    );
    if (network != null) return network;
    if (openRoots == null) return null;

    // Both sides are keyed by crux_io's `containmentKey`, CXP §11.3's "the
    // path the filesystem would reach": the deepest existing prefix as
    // spelled is resolved by the filesystem, the rest is appended as
    // written, a `..` in that rest or an unresolvable prefix has no key, and
    // case is folded where the filesystem folds it. On Windows the
    // filesystem API collapses `..` as text before it resolves anything, and
    // so does the resolution, so the check reads a path the way the open
    // will; junctions resolve like links. A missing drive or share has no
    // key. The same rule guards every other contained path in the suite.
    final rootKeys = <String>[];
    var anyRoot = false;
    for (final root in openRoots) {
      if (root.trim().isEmpty) continue;
      anyRoot = true;
      final rootKey = containmentKey(p.absolute(root));
      if (rootKey != null) rootKeys.add(rootKey);
    }
    if (!anyRoot) return 'no directory is open in this session';
    final key = containmentKey(path);
    if (key == null) return 'file_path cannot be resolved';
    for (final rootKey in rootKeys) {
      if (key == rootKey || p.isWithin(rootKey, key)) return null;
    }
    return 'file_path is outside the directories open in this session';
  }

  /// Whether [path] may be opened — [refuse] returned null.
  bool allows(String path) => refuse(path) == null;
}
