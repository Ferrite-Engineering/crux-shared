// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/workspace.dart';

/// The folder part that tells same-named tabs apart, per tab.
///
/// Tabs whose labels collide, counted across every pane of [tabs], each get
/// the shortest run of trailing parent-folder segments of their path that no
/// other differently-placed tab in the group shares, joined with `/` (so
/// `/work/soc_sampler/simcrux.yaml` against `/work/alu_core/simcrux.yaml`
/// gives `soc_sampler` and `alu_core`). Two tabs under `a/x` and `b/x` get
/// `a/x` and `b/x`, while a third under `c/y` still gets just `y`.
///
/// A tab is absent from the result when it needs no suffix: its label is
/// unique, it has no path, or every other tab sharing its label is at the
/// very same folder, so no folder name could tell them apart.
///
/// The suffix comes from the parent segments of the path as given and never
/// assumes the path's last segment equals the label. A product may hand in a
/// project directory for a tab named after something else.
///
/// `labelOf` is the label the chip shows; `pathOf` is the product's
/// `tabFilePath`. `pathOf` is only called for tabs whose label collides.
Map<TabId, String> tabFolderSuffixes<P>(
  List<WorkspaceTab<P>> tabs, {
  required String Function(WorkspaceTab<P> tab) labelOf,
  required String? Function(WorkspaceTab<P> tab) pathOf,
}) {
  final byLabel = <String, List<WorkspaceTab<P>>>{};
  for (final tab in tabs) {
    byLabel.putIfAbsent(labelOf(tab), () => []).add(tab);
  }

  final result = <TabId, String>{};
  for (final group in byLabel.values) {
    if (group.length < 2) continue;

    final parents = <TabId, List<String>>{};
    for (final tab in group) {
      final path = pathOf(tab);
      if (path == null || path.isEmpty) continue;
      final segments = _segments(path);
      // Without the last segment, which is the file or directory itself.
      parents[tab.id] = segments.isEmpty
          ? const []
          : segments.sublist(0, segments.length - 1);
    }
    final hasPathless = parents.length < group.length;

    for (final tab in group) {
      final mine = parents[tab.id];
      if (mine == null || mine.isEmpty) continue;
      final others = [
        for (final entry in parents.entries)
          if (entry.key != tab.id && !_sameFolder(entry.value, mine))
            entry.value,
      ];
      if (others.isEmpty && !hasPathless) continue;

      var depth = 1;
      while (depth < mine.length &&
          others.any((o) => _tail(o, depth) == _tail(mine, depth))) {
        depth++;
      }
      result[tab.id] = _tail(mine, depth);
    }
  }
  return result;
}

List<String> _segments(String path) => [
  for (final s in path.split(RegExp(r'[\\/]')))
    if (s.isNotEmpty) s,
];

bool _sameFolder(List<String> a, List<String> b) =>
    a.length == b.length && _tail(a, a.length) == _tail(b, b.length);

/// The last [depth] segments of [parent], joined with `/`.
String _tail(List<String> parent, int depth) =>
    parent.sublist(parent.length > depth ? parent.length - depth : 0).join('/');
