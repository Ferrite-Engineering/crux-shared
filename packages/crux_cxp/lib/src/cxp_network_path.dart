// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// The lexical rule for Windows network and device paths, applied before
/// `CxpPathContainment` touches the filesystem.
///
/// On Windows a path that begins with two separators names a network share
/// (`\\server\share\…`) or a device namespace (`\\?\…`, `\\.\…`). Asking the
/// filesystem whether such a path exists, or what it resolves to, opens an
/// SMB connection to a server the peer chose, and that connection can offer
/// the user's NTLM credentials before any decision has been made. So the
/// check is made on the string alone: such a path is refused unless one of
/// the open [roots] begins with the same first two components, compared
/// without regard to case or separator spelling. A refused path is never
/// handed to the filesystem; an allowed one continues to the ordinary
/// containment check, which then resolves it under a share the user opened
/// themselves.
///
/// With no roots (the floor tier) every such path is refused: the floor
/// lets a path through to the product, and the product would open it.
///
/// Off Windows ([windows] false) a leading `//` is an ordinary absolute
/// path and this returns null.
///
/// Returns null when the path is not a network or device path, or when a
/// root shares its prefix; otherwise the refusal reason.
@internal
String? cxpNetworkPathRefusal(
  String path, {
  required bool windows,
  Iterable<String>? roots,
}) {
  if (!windows) return null;
  final prefix = _networkPrefix(path);
  if (prefix == null) return null;
  if (roots != null) {
    for (final root in roots) {
      if (_networkPrefix(root) == prefix) return null;
    }
  }
  return 'file_path is a network or device path';
}

/// The lower-cased first two components of a path that begins with two
/// separators, or null for any other path. A path with fewer than two
/// components after the separators (`\\server`) still counts as a network
/// path, and its prefix is what it has.
String? _networkPrefix(String path) {
  bool isSep(int c) => c == 0x5C || c == 0x2F; // \ or /
  if (path.length < 2) return null;
  if (!isSep(path.codeUnitAt(0)) || !isSep(path.codeUnitAt(1))) return null;
  final parts = path
      .substring(2)
      .split(RegExp(r'[\\/]'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s.toLowerCase())
      .toList();
  return '\\\\${parts.join(r'\')}';
}
