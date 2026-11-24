// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:edacrux_cxp/edacrux_cxp_listener.dart'
    show cxpNetworkPathRefusal;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// What [Confinement.confine] decided for one path.
@immutable
sealed class ConfinementResult {
  const ConfinementResult();
}

/// The path is inside the root; [path] is the absolute spelling that was
/// checked, and the one to open.
final class ConfinedPath extends ConfinementResult {
  /// The checked path.
  const ConfinedPath(this.path);

  /// The absolute path, exactly as checked. Open this string and no other.
  final String path;
}

/// The path is refused; [message] says why, for a `usage_error`.
final class RefusedPath extends ConfinementResult {
  /// A refusal of [given], saying [message].
  const RefusedPath(this.given, this.message);

  /// The path as it was given.
  final String given;

  /// One sentence naming the path and the reason.
  final String message;
}

/// The rule a refusal comes from: null when the absolute [path] may be
/// opened inside [root], otherwise the reason.
typedef ConfinementRule = String? Function(String root, String path);

/// Every path a tool or a link receives, held inside one root directory.
///
/// No containment logic of its own: the check is `crux_cxp`'s
/// [CxpPathContainment] with the root as its one open directory, keyed by
/// `crux_io`'s `containmentKey`. So a path resolves, after symbolic links,
/// through its deepest existing ancestor; the part that does not exist yet
/// is taken as written, and a `..` in it is refused; and a path that is
/// outside the root after that is refused and never opened.
///
/// Before any of that, a Windows network or device spelling (`\\server\…`,
/// `\\?\…`, `\\.\…`, or the same with `/`) is refused on its text alone,
/// on every host: resolving it on Windows would open a connection to a
/// server the caller chose. A relative path is taken against the root.
///
/// The value checked is the value to open: [confine] returns the absolute
/// string it judged, never a respelling of it. A check describes the file
/// system at the moment it ran; check immediately before opening.
@immutable
class Confinement {
  /// Paths held inside [root], made absolute against the working directory.
  Confinement(String root) : this._(p.absolute(root), _cxpRule);

  /// A confinement whose check is [rule], so a test can prove that a broken
  /// check is caught. Never used outside tests.
  @visibleForTesting
  Confinement.withRule(String root, ConfinementRule rule)
    : this._(p.absolute(root), rule);

  const Confinement._(this.root, this._rule);

  /// The root directory, absolute.
  final String root;

  final ConfinementRule _rule;

  static String? _cxpRule(String root, String path) =>
      CxpPathContainment(roots: () => <String>[root]).refuse(path);

  /// Null when [root] is an existing directory; otherwise why it cannot be
  /// a root, for the `--root` usage error.
  String? rootProblem() {
    if (FileSystemEntity.typeSync(root) != FileSystemEntityType.directory) {
      return '--root $root is not a directory';
    }
    return null;
  }

  /// [given] judged against the root: a relative path is taken against the
  /// root first.
  ConfinementResult confine(String given) => _confine(given, root);

  /// Every one of [paths] judged as [confine] judges it, a relative one
  /// taken against [base] (the directory of the file that names them) or,
  /// when null, the root. Null when every path is inside; otherwise the
  /// first refusal.
  ///
  /// For the files a project names: a product reads its project file,
  /// filelist or manifest the way its command will, and passes every source,
  /// include directory, library, test bench and dump it names.
  RefusedPath? confineAll(Iterable<String> paths, {String? base}) {
    for (final path in paths) {
      final result = _confine(path, base ?? root);
      if (result is RefusedPath) return result;
    }
    return null;
  }

  ConfinementResult _confine(String given, String base) {
    if (given.isEmpty || given.contains('\x00')) {
      return RefusedPath(given, 'a path is empty or holds a NUL character');
    }
    if (cxpNetworkPathRefusal(given, windows: true) != null) {
      return RefusedPath(
        given,
        '`$given` is a network or device path; the server reads only files '
        'inside $root',
      );
    }
    final absolute = p.isAbsolute(given) ? given : p.join(base, given);
    final reason = _rule(root, absolute);
    if (reason == null) return ConfinedPath(absolute);
    return RefusedPath(given, _describe(given, reason));
  }

  String _describe(String given, String reason) {
    if (reason.contains('outside')) {
      return '`$given` is outside the root $root; the server reads only '
          'inside it';
    }
    if (reason.contains('cannot be resolved')) {
      return '`$given` cannot be resolved inside the root $root: a `..` '
          'below a name that does not exist, or a link that leads nowhere';
    }
    final why = reason.replaceFirst('file_path', 'the path');
    return '`$given` is refused: $why';
  }
}
