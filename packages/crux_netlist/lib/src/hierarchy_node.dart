// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/src/module.dart';
import 'package:crux_netlist/src/netlist_model.dart';
import 'package:meta/meta.dart';

/// A position inside a [NetlistModel]'s instance hierarchy.
///
/// A [HierarchyNode] points to one module at the location reached by
/// following the chain of instance names in [path]. The empty path
/// `<[]>` is the top module; the next level is a single-element list
/// like `<['u_cpu']>`, and so on. Both the [path] and the resolved
/// [moduleName] are kept as part of the value so two equal nodes
/// compare equal and hash identically without needing to dereference
/// the model.
///
/// This is the unit the hierarchy browser, push-in / pop-out
/// navigator, and per-scope schematic graph builder address. The model
/// itself is *not* embedded in the node — callers pass the [NetlistModel]
/// in alongside the node when they need to resolve children. This keeps
/// the value small, comparable, and serializable.
@immutable
class HierarchyNode {
  /// Creates a hierarchy node at [path], pointing at [moduleName].
  const HierarchyNode({
    required this.path,
    required this.moduleName,
  });

  /// Builds the root node for [model]. Returns `null` when the model
  /// has no top module (e.g. a malformed elaboration); callers should
  /// surface that as a diagnostic rather than guessing.
  static HierarchyNode? rootOf(NetlistModel model) {
    final top = model.topModule;
    if (top == null) return null;
    return HierarchyNode(path: const <String>[], moduleName: top.name);
  }

  /// Instance-name path from the top module to *this* node, in
  /// outer-to-inner order. Empty for the root.
  final List<String> path;

  /// Module name the node currently resolves to.
  final String moduleName;

  /// True for the top-of-design node — the path is empty.
  bool get isRoot => path.isEmpty;

  /// Number of levels below the top. 0 for the root.
  int get depth => path.length;

  /// Instance name the user sees in the hierarchy browser for this
  /// node. For the root this is the module name; for nested levels it
  /// is the leaf of [path] (the instance name).
  String get displayName => isRoot ? moduleName : path.last;

  /// Canonical scope path the user sees in the breadcrumb /
  /// status bar (e.g. `top.u_cpu.alu`). The first segment is the top
  /// module's name; subsequent segments are instance names.
  String canonicalPath(NetlistModel model) {
    final top = model.topModule;
    final root = top?.name ?? moduleName;
    if (path.isEmpty) return root;
    return <String>[root, ...path].join('.');
  }

  /// Returns the child [HierarchyNode] reached by walking into the cell
  /// instance named [instanceName] in the resolved [Module].
  ///
  /// Returns `null` when the named cell either does not exist, has a
  /// `type` that does not name another user-defined module in [model]
  /// (it is a primitive like `$and`), or [model] is missing the
  /// declared module entirely (defensive — a broken elaboration).
  HierarchyNode? child(NetlistModel model, String instanceName) {
    final module = model.modules[moduleName];
    if (module == null) return null;
    final cell = module.cells[instanceName];
    if (cell == null) return null;
    final childModule = model.modules[cell.type];
    // A black-box module is a leaf: its instance is a cell, not a scope.
    if (childModule == null || childModule.isBlackBox) return null;
    return HierarchyNode(
      path: <String>[...path, instanceName],
      moduleName: childModule.name,
    );
  }

  /// Returns the parent [HierarchyNode], or `null` at the root.
  ///
  /// Walks [path] in [model] to resolve the parent's module name.
  /// Returns `null` if the walk diverges from [model] (the node has
  /// gone stale).
  HierarchyNode? parent(NetlistModel model) {
    if (isRoot) return null;
    final parentPath = path.sublist(0, path.length - 1);
    final top = model.topModule;
    if (top == null) return null;
    var module = top;
    for (final instanceName in parentPath) {
      final cell = module.cells[instanceName];
      if (cell == null) return null;
      final next = model.modules[cell.type];
      if (next == null || next.isBlackBox) return null;
      module = next;
    }
    return HierarchyNode(path: parentPath, moduleName: module.name);
  }

  /// Resolves the [Module] this node points at. Returns `null` when
  /// [model] no longer contains a module with [moduleName] (the model
  /// was replaced after the node was captured).
  Module? resolve(NetlistModel model) => model.modules[moduleName];

  /// Returns the set of *user-defined child* instance names — i.e.
  /// cells whose `type` names another module in [model]. Primitive
  /// cells (`$and`, `$mux`, `$dff`) are excluded since they have no
  /// inner hierarchy to descend into.
  List<String> childInstanceNames(NetlistModel model) {
    final module = resolve(model);
    if (module == null) return const <String>[];
    final result = <String>[];
    for (final entry in module.cells.entries) {
      final child = model.modules[entry.value.type];
      if (child != null && !child.isBlackBox) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Returns a copy with the given fields replaced.
  HierarchyNode copyWith({List<String>? path, String? moduleName}) {
    return HierarchyNode(
      path: path ?? this.path,
      moduleName: moduleName ?? this.moduleName,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HierarchyNode) return false;
    if (other.moduleName != moduleName) return false;
    if (other.path.length != path.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (other.path[i] != path[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(moduleName, Object.hashAll(path));

  @override
  String toString() =>
      'HierarchyNode(path: ${path.join('.')}, module: $moduleName)';
}
