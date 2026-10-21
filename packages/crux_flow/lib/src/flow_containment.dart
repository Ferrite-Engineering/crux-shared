// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// A path a flow reader was asked to read that lies outside every directory
/// it may read from.
class FlowContainmentException implements Exception {
  /// Creates the exception. [reason] is one of the fixed strings
  /// [FlowContainment.refuse] returns and never repeats the path.
  const FlowContainmentException(this.reason);

  /// Why the path was refused.
  final String reason;

  @override
  String toString() => 'FlowContainmentException: $reason';
}

/// The directories a flow may read from, and the check every run root and
/// every path a run's own records name goes through before it is read.
///
/// A run directory is user-controlled and may be someone else's CI
/// artifact, so a path it names is a hint, not a permission: a run root must
/// resolve inside the project root or a directory the user chose to ingest
/// from, and a netlist, SDF or cell-model path a run's configuration names
/// must resolve inside the run root or the PDK root. Resolution follows
/// symlinks the way an open would (`containmentKey` in `crux_io`), so a link
/// inside a run that points out of it is outside, and a PDK root that is
/// itself a link (ciel and volare link the enabled PDK) is checked at its
/// target.
///
/// Reasons are fixed strings that never repeat the path, so they are safe to
/// show beside a path that came from someone else's files.
@immutable
class FlowContainment {
  /// Creates the rule over [roots].
  const FlowContainment(this.roots);

  /// The directories paths must resolve inside. Blank entries are ignored;
  /// none at all refuses everything.
  final List<String> roots;

  /// Null when [path] may be read; otherwise why not.
  String? refuse(String path) {
    if (path.trim().isEmpty) return 'the path is empty';
    if (path.contains('\x00')) return 'the path contains a NUL character';
    if (path.trim() != path) return 'the path begins or ends with white space';
    if (!p.isAbsolute(path) || p.isRootRelative(path)) {
      return 'the path is not absolute';
    }
    if (!roots.any((r) => r.trim().isNotEmpty)) {
      return 'no directory has been allowed';
    }
    if (containmentKey(path) == null) return 'the path cannot be resolved';
    if (containingRoot(path, roots) == null) {
      return 'the path is outside the allowed directories';
    }
    return null;
  }

  /// Whether [path] may be read.
  bool allows(String path) => refuse(path) == null;

  /// [path], canonicalised with its symlinks resolved, when it may be read.
  ///
  /// Throws [FlowContainmentException] otherwise. Read the returned path,
  /// not [path], so the value checked is the value opened.
  String require(String path) {
    final reason = refuse(path);
    if (reason != null) throw FlowContainmentException(reason);
    return _resolved(path);
  }

  /// [path] with its deepest existing prefix resolved by the filesystem and
  /// the rest appended as written, case preserved: the path an open would
  /// reach, whether or not the file exists yet. [refuse] has already
  /// established that this resolves and that the rest holds no `..`.
  static String _resolved(String path) {
    var head = path;
    final remainder = <String>[];
    while (FileSystemEntity.typeSync(head, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(head);
      if (parent == head) return canonicalizePath(path);
      remainder.insert(0, p.basename(head));
      head = parent;
    }
    try {
      final resolved = File(head).resolveSymbolicLinksSync();
      return p.normalize(p.joinAll([resolved, ...remainder]));
    } on FileSystemException {
      throw const FlowContainmentException('the path cannot be resolved');
    }
  }

  /// [recorded] (a path a run's own records name: absolute, or relative to
  /// [base]) resolved and checked as [require] does.
  ///
  /// [base] is normally the run root. A relative [recorded] is joined to it
  /// as written; its `..` segments are then judged by the filesystem, never
  /// collapsed as text first.
  String requireRecorded(String base, String recorded) {
    if (recorded.contains('\x00')) {
      throw const FlowContainmentException(
        'the path contains a NUL character',
      );
    }
    final joined = p.isAbsolute(recorded) ? recorded : p.join(base, recorded);
    return require(joined);
  }
}
