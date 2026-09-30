// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Stable, comparable descriptor of one project loaded into a product's
/// multi-project workspace.
///
/// The descriptor captures *the project metadata the workspace needs to
/// manage* — its identity, where its config file lives, when it was opened,
/// and whether the user pinned it. Per-project feature state (each product's
/// own stores — violations/baselines/waivers, results/trends, and so on)
/// lives in per-project Riverpod scopes keyed by [id]; the descriptor itself
/// is the stable lookup key, not the state container.
///
/// JSON-serializable. Forward-compatible: unknown keys are tolerated by
/// [fromJson] for forward compatibility with future workspace schema
/// versions.
///
/// Shared across the EDACrux suite via `crux_projects` so every product's
/// multi-project surface uses one identity + persistence contract.
@immutable
class ProjectDescriptor {
  /// Creates a [ProjectDescriptor].
  const ProjectDescriptor({
    required this.id,
    required this.displayName,
    required this.projectPath,
    required this.loadedAt,
    required this.lastAccessedAt,
    this.isPinned = false,
  });

  /// Stable identifier for this project. Derived from a hash of the
  /// canonical path so it is deterministic across app restarts but
  /// independent of any displayName the user might assign later.
  ///
  /// The id is what per-project Riverpod scopes key off, so its
  /// stability is the workspace's binding contract.
  final String id;

  /// User-facing label. Defaults to the project path's basename;
  /// when multiple loaded projects share a basename the registry
  /// disambiguates by appending a parent-directory suffix.
  final String displayName;

  /// Absolute path to the project root or its config file. The registry
  /// treats this as opaque — what counts as "a project" is determined by
  /// each product's project loader, not the workspace.
  final String projectPath;

  /// ISO 8601 timestamp when this project was first opened in the
  /// current workspace session. Survives close → reopen via the
  /// recent projects list (re-opening resets [loadedAt] to the new
  /// open event).
  final DateTime loadedAt;

  /// ISO 8601 timestamp last time the user switched the active tab
  /// to this project. Drives MRU ordering in the project switcher.
  final DateTime lastAccessedAt;

  /// Pinned projects survive `closeAllProjects` actions. Pin state
  /// is persisted in the workspace.
  final bool isPinned;

  /// Field-by-field copy with optional overrides.
  ProjectDescriptor copyWith({
    String? id,
    String? displayName,
    String? projectPath,
    DateTime? loadedAt,
    DateTime? lastAccessedAt,
    bool? isPinned,
  }) {
    return ProjectDescriptor(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      projectPath: projectPath ?? this.projectPath,
      loadedAt: loadedAt ?? this.loadedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  /// JSON serialization for workspace persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'display_name': displayName,
    'project_path': projectPath,
    'loaded_at': loadedAt.toIso8601String(),
    'last_accessed_at': lastAccessedAt.toIso8601String(),
    'is_pinned': isPinned,
  };

  /// Tolerant JSON parser. Missing optional fields fall back to safe
  /// defaults; missing required fields (`id`, `display_name`,
  /// `project_path`) yield `null`. Forward-compatible — unknown
  /// keys are silently ignored.
  static ProjectDescriptor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final displayName = raw['display_name'];
    final projectPath = raw['project_path'];
    if (id is! String || id.isEmpty) return null;
    if (displayName is! String || displayName.isEmpty) return null;
    if (projectPath is! String || projectPath.isEmpty) return null;
    final loadedRaw = raw['loaded_at'];
    final accessedRaw = raw['last_accessed_at'];
    final loadedAt = loadedRaw is String
        ? DateTime.tryParse(loadedRaw) ?? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final lastAccessedAt = accessedRaw is String
        ? DateTime.tryParse(accessedRaw) ?? loadedAt
        : loadedAt;
    final pinned = raw['is_pinned'];
    return ProjectDescriptor(
      id: id,
      displayName: displayName,
      projectPath: projectPath,
      loadedAt: loadedAt,
      lastAccessedAt: lastAccessedAt,
      isPinned: pinned is bool && pinned,
    );
  }

  /// Derive the deterministic [id] for a project located at
  /// [projectPath]. Uses a simple stable hash of the canonical path
  /// so the same project re-opens with the same id across restarts.
  ///
  /// The id is intentionally opaque — callers should not parse it
  /// for path information. 32-bit operands keep the hash representable
  /// on JavaScript-compiled targets even though the Crux products are
  /// desktop-first — keeping the model platform-agnostic costs nothing.
  static String idForPath(String projectPath) {
    // Stable non-cryptographic hash; FNV-1a-style 32-bit folded twice.
    var lo = 0x811c9dc5;
    var hi = 0x01000193;
    const prime = 0x01000193;
    for (final b in projectPath.codeUnits) {
      lo = ((lo ^ b) * prime) & 0xFFFFFFFF;
      hi = ((hi ^ (b * 31 + 7)) * prime) & 0xFFFFFFFF;
    }
    final loHex = lo.toRadixString(16).padLeft(8, '0');
    final hiHex = hi.toRadixString(16).padLeft(8, '0');
    return 'project_$hiHex$loHex';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProjectDescriptor) return false;
    return other.id == id &&
        other.displayName == displayName &&
        other.projectPath == projectPath &&
        other.loadedAt == loadedAt &&
        other.lastAccessedAt == lastAccessedAt &&
        other.isPinned == isPinned;
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    projectPath,
    loadedAt,
    lastAccessedAt,
    isPinned,
  );

  @override
  String toString() =>
      'ProjectDescriptor(id: $id, path: $projectPath, '
      'pinned: $isPinned)';
}
