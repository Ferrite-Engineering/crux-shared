// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/src/project_descriptor.dart';
import 'package:meta/meta.dart';

/// Snapshot of the multi-project workspace.
///
/// Captures *which projects are open*, *which is active*, and *which
/// projects are remembered for one-click reopen*. Per-project feature state
/// (each product's own stores) lives in per-project Riverpod scopes; this
/// model is the workspace-level lookup table the rest of the app reads to
/// know what is currently open.
///
/// Empty workspace is a valid first-class state: `openProjects` empty,
/// `activeProjectId` null. The dashboard renders an empty-workspace surface
/// in that state.
///
/// Distinct from the `crux_workspace` `Workspace` type, which holds the
/// multi-tab / multi-pane *viewing* state: a tab represents one open file
/// inside one project; this workspace represents the set of open *projects*
/// (each of which may host one or more tabs).
@immutable
class ProjectWorkspace {
  /// Creates a [ProjectWorkspace].
  ProjectWorkspace({
    List<ProjectDescriptor> openProjects = const <ProjectDescriptor>[],
    this.activeProjectId,
    List<ProjectDescriptor> recentProjects = const <ProjectDescriptor>[],
  }) : openProjects = List<ProjectDescriptor>.unmodifiable(openProjects),
       recentProjects = List<ProjectDescriptor>.unmodifiable(
         recentProjects.take(recentProjectsCap),
       );

  /// Convenience: an empty workspace with no open or recent projects.
  factory ProjectWorkspace.empty() => ProjectWorkspace();

  /// Maximum number of entries retained in [recentProjects]. The
  /// registry enforces the cap on every mutation; constructor input
  /// is also truncated for safety.
  static const int recentProjectsCap = 10;

  /// Schema version for [toJson] / [fromJson]. Bumps on incompatible
  /// changes; current parsers reject any future major version they
  /// don't understand.
  static const int version = 1;

  /// All projects currently loaded into the workspace, in user
  /// presentation order (matches the project tab strip).
  final List<ProjectDescriptor> openProjects;

  /// Id of the active project (the project the dashboard currently
  /// shows). Always one of `openProjects`'s ids when non-null;
  /// becomes null only when `openProjects` is empty.
  final String? activeProjectId;

  /// MRU-ordered list of projects the user has closed but kept in
  /// the "Recent" list for one-click reopen. Capped at
  /// [recentProjectsCap]; oldest entries fall off when new entries
  /// arrive.
  final List<ProjectDescriptor> recentProjects;

  /// Convenience: is the workspace empty?
  bool get isEmpty => openProjects.isEmpty;

  /// Convenience: number of open projects.
  int get openCount => openProjects.length;

  /// Resolve the active descriptor when [activeProjectId] is set.
  /// Returns null when the workspace is empty or the active id no
  /// longer matches an open project (a defensive case that should
  /// never happen with a well-behaved registry but is cheap to
  /// guard against).
  ProjectDescriptor? get activeProject {
    if (activeProjectId == null) return null;
    for (final p in openProjects) {
      if (p.id == activeProjectId) return p;
    }
    return null;
  }

  /// Field-by-field copy with optional overrides. Pass
  /// `clearActive: true` to set [activeProjectId] to null explicitly
  /// (Dart's nullable parameter conventions otherwise make "no
  /// change" and "set to null" indistinguishable for nullable fields).
  ProjectWorkspace copyWith({
    List<ProjectDescriptor>? openProjects,
    String? activeProjectId,
    bool clearActive = false,
    List<ProjectDescriptor>? recentProjects,
  }) {
    return ProjectWorkspace(
      openProjects: openProjects ?? this.openProjects,
      activeProjectId: clearActive
          ? null
          : (activeProjectId ?? this.activeProjectId),
      recentProjects: recentProjects ?? this.recentProjects,
    );
  }

  /// JSON serialization for workspace persistence.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'open_projects': openProjects.map((p) => p.toJson()).toList(),
    'active_project_id': activeProjectId,
    'recent_projects': recentProjects.map((p) => p.toJson()).toList(),
  };

  /// Tolerant JSON parser. Unknown future schema versions return
  /// `null` so the caller can fall back to an empty workspace
  /// rather than crashing on a forward-incompatible file.
  ///
  /// ### Version policy
  ///
  /// This is **app-managed recoverable state**, not a user-authored artifact:
  /// the registry file is written by the app for itself, the user cannot
  /// hand-repair it, and a hard failure on load would brick launch. So it
  /// degrades — returns `null`, the caller substitutes an empty workspace —
  /// where the user-authored formats (`ThemePackCodec`, `KeymapCodec`) refuse
  /// loudly instead. Same policy, opposite side of the same line.
  ///
  /// Three cases, deliberately distinguished:
  ///
  /// - **`version` absent** → treated as a legacy pre-versioning document and
  ///   parsed field-by-field, which is what tolerance is for.
  /// - **`version` present but not an int** → unreadable. This used to fall
  ///   into the "absent" branch via a single `is! int` test, so a document
  ///   with `"version": "2"` was parsed as if it were legacy. That is the same
  ///   type-confusion `Workspace.fromJson` was hardened against — a string
  ///   version is corruption or a foreign format, not an old file.
  /// - **`version` newer than [version]** → unreadable.
  static ProjectWorkspace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['version'];
    if (v == null) return ProjectWorkspace.empty();
    if (v is! int) return null;
    if (v > version) return null;
    final openRaw = raw['open_projects'];
    final recentRaw = raw['recent_projects'];
    final open = <ProjectDescriptor>[];
    if (openRaw is List) {
      for (final entry in openRaw) {
        final d = ProjectDescriptor.fromJson(entry);
        if (d != null) open.add(d);
      }
    }
    final recent = <ProjectDescriptor>[];
    if (recentRaw is List) {
      for (final entry in recentRaw) {
        final d = ProjectDescriptor.fromJson(entry);
        if (d != null) recent.add(d);
      }
    }
    final activeRaw = raw['active_project_id'];
    final active = activeRaw is String && activeRaw.isNotEmpty
        ? activeRaw
        : null;
    // Defensive: clamp activeProjectId to an actually-open project.
    final activeClamped = active != null && open.any((p) => p.id == active)
        ? active
        : null;
    return ProjectWorkspace(
      openProjects: open,
      activeProjectId: activeClamped,
      recentProjects: recent,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProjectWorkspace) return false;
    if (other.activeProjectId != activeProjectId) return false;
    if (!_listEquals(openProjects, other.openProjects)) return false;
    if (!_listEquals(recentProjects, other.recentProjects)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    activeProjectId,
    Object.hashAll(openProjects),
    Object.hashAll(recentProjects),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
