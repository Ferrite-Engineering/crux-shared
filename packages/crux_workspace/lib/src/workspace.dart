// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/workspace_codec.dart';
import 'package:meta/meta.dart';

/// Current schema version for the workspace JSON document.
///
/// Bump whenever a non-backward-compatible field change is made; older
/// versions are rejected on load with [WorkspaceSchemaVersionException].
const int kWorkspaceSchemaVersion = 1;

/// Thrown when a workspace JSON document declares a [Workspace.version] that
/// the consumer does not understand.
class WorkspaceSchemaVersionException implements Exception {
  /// Creates the exception with the unsupported [version].
  const WorkspaceSchemaVersionException(this.version);

  /// The unsupported schema version encountered in the JSON document.
  final int version;

  @override
  String toString() =>
      'WorkspaceSchemaVersionException(version: $version, '
      'expected: $kWorkspaceSchemaVersion)';
}

/// Thrown when a workspace JSON document violates a structural invariant
/// (missing required fields, unknown pane references, duplicate ids, etc.).
class WorkspaceInvariantException implements Exception {
  /// Creates the exception with an explanatory [message].
  const WorkspaceInvariantException(this.message);

  /// Human-readable description of the invariant violation.
  final String message;

  @override
  String toString() => 'WorkspaceInvariantException($message)';
}

/// Workspace-level reference to one open tab.
///
/// Distinct from any product-specific live in-memory tab model: the workspace
/// stores the persistence-relevant subset — the tab id, the pane that hosts
/// it, the user-visible display name, and a product-specific [payload] (of
/// type [P]) that carries everything else (file path, sidecar export path,
/// per-product editor state, etc.).
///
/// [P] is serialized through a [WorkspaceCodec] supplied at load/save time.
///
/// Pure Dart — no Flutter imports.
@immutable
class WorkspaceTab<P> {
  /// Creates a workspace tab.
  const WorkspaceTab({
    required this.id,
    required this.displayName,
    required this.paneId,
    required this.payload,
  });

  /// Tab identity. Stable for the life of the tab and persisted in the
  /// workspace document.
  final TabId id;

  /// User-visible label rendered in the tab chip.
  final String displayName;

  /// Pane that hosts this tab.
  final PaneId paneId;

  /// Product-specific per-tab data.
  final P payload;

  /// Returns a copy of this tab with the given fields replaced. Fields not
  /// supplied default to the existing value.
  WorkspaceTab<P> copyWith({
    TabId? id,
    String? displayName,
    PaneId? paneId,
    P? payload,
  }) {
    return WorkspaceTab<P>(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      paneId: paneId ?? this.paneId,
      payload: payload ?? this.payload,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceTab<P> &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          displayName == other.displayName &&
          paneId == other.paneId &&
          payload == other.payload;

  @override
  int get hashCode => Object.hash(id, displayName, paneId, payload);

  @override
  String toString() =>
      'WorkspaceTab(id: $id, displayName: $displayName, paneId: $paneId, '
      'payload: $payload)';
}

/// Workspace-level pane descriptor.
///
/// A pane is a side-by-side viewing region inside the host product's center
/// area. The workspace currently allows 1 or 2 panes; 3+ is out of scope for
/// the v1 schema.
///
/// Pure Dart — no Flutter imports.
@immutable
class WorkspacePane {
  /// Creates a workspace pane.
  const WorkspacePane({required this.id, this.activeTabId});

  /// Deserializes from the JSON map stored inside a [Workspace] document.
  factory WorkspacePane.fromJson(Map<String, Object?> json) {
    // Type-test rather than cast throughout: a cast raises a `TypeError`,
    // which is an Error and not an Exception, so it slips past every typed
    // recovery handler in WorkspaceService and crashes the launch it was
    // supposed to degrade gracefully. A malformed document must surface as a
    // WorkspaceInvariantException that names the offending field.
    final id = json['id'];
    if (id is! String) {
      throw const WorkspaceInvariantException(
        'WorkspacePane requires a string id',
      );
    }
    final activeTabValue = json['activeTabId'];
    if (activeTabValue != null && activeTabValue is! String) {
      throw const WorkspaceInvariantException(
        'WorkspacePane activeTabId must be a string when present',
      );
    }
    final activeTabRaw = activeTabValue as String?;
    return WorkspacePane(
      id: PaneId.fromString(id),
      activeTabId: activeTabRaw == null ? null : TabId.fromString(activeTabRaw),
    );
  }

  /// Pane identity. Stable for the life of the pane and persisted in the
  /// workspace document.
  final PaneId id;

  /// Tab currently focused inside this pane, or null when the pane is empty.
  final TabId? activeTabId;

  /// Returns a copy with the given fields replaced.
  WorkspacePane copyWith({PaneId? id, TabId? activeTabId}) {
    return WorkspacePane(
      id: id ?? this.id,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }

  /// Returns a pane with [activeTabId] cleared.
  WorkspacePane withoutActiveTab() => WorkspacePane(id: id);

  /// Serializes the pane to a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'id': id.value,
    if (activeTabId != null) 'activeTabId': activeTabId!.value,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspacePane &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          activeTabId == other.activeTabId;

  @override
  int get hashCode => Object.hash(id, activeTabId);

  @override
  String toString() => 'WorkspacePane(id: $id, activeTabId: $activeTabId)';
}

/// Root persistence object capturing an entire product session.
///
/// Holds the ordered list of [WorkspaceTab]s, the pane layout (1 or 2 panes),
/// the active pane pointer, and a free-form `extras` map that products use
/// for top-level layout/ambient flags (panel visibility, statistics-strip
/// visibility, etc.) without needing a schema-version bump.
///
/// Invariants enforced by the constructor and `fromJson`:
/// * `version == kWorkspaceSchemaVersion` (`fromJson` throws otherwise).
/// * `panes.length` ∈ {1, 2}.
/// * `activePaneId` references one of `panes`.
/// * Every `tabs[i].paneId` references one of `panes`.
/// * Tab ids are unique across the workspace.
/// * For every [WorkspacePane.activeTabId], that tab exists in `tabs` and is
///   hosted by that pane.
///
/// Pure Dart — no Flutter imports.
@immutable
class Workspace<P> {
  /// Creates a workspace, validating its structural invariants.
  Workspace({
    required this.tabs,
    required this.panes,
    required this.activePaneId,
    this.extras = const <String, Object?>{},
    this.version = kWorkspaceSchemaVersion,
  }) {
    _validate(
      tabs: tabs,
      panes: panes,
      activePaneId: activePaneId,
      version: version,
    );
  }

  /// Returns the canonical empty workspace: zero tabs, one empty pane.
  factory Workspace.empty() {
    final pane = WorkspacePane(id: PaneId.generate());
    return Workspace<P>(
      tabs: const [],
      panes: [pane],
      activePaneId: pane.id,
    );
  }

  /// Deserializes from a JSON document using [codec] to materialize each
  /// tab's [WorkspaceTab.payload].
  ///
  /// Rejects unknown `version` values with [WorkspaceSchemaVersionException];
  /// silently ignores unknown top-level fields for forward compatibility.
  factory Workspace.fromJson(
    Map<String, Object?> json,
    WorkspaceCodec<P> codec,
  ) {
    // Type-test, never cast — see the note in [WorkspacePane.fromJson]. A
    // `"version": "1"` string used to raise a TypeError that bypassed
    // WorkspaceService's quarantine entirely; now it lands on the
    // schema-version branch and gets quarantined like any other bad document.
    final versionRaw = json['version'];
    final version = versionRaw is num ? versionRaw.toInt() : -1;
    if (version != kWorkspaceSchemaVersion) {
      throw WorkspaceSchemaVersionException(version);
    }

    final rawPanes = json['panes'];
    if (rawPanes is! List || rawPanes.isEmpty) {
      throw const WorkspaceInvariantException(
        'Workspace requires at least one pane',
      );
    }
    final panes = <WorkspacePane>[
      for (final raw in rawPanes)
        if (raw is Map<String, Object?>) WorkspacePane.fromJson(raw),
    ];

    final rawTabs = json['tabs'];
    final tabs = <WorkspaceTab<P>>[
      if (rawTabs is List)
        for (final raw in rawTabs)
          if (raw is Map<String, Object?>) _tabFromJson(raw, codec),
    ];

    final activePaneIdRaw = json['activePaneId'];
    if (activePaneIdRaw is! String) {
      throw const WorkspaceInvariantException(
        'Workspace requires a string activePaneId',
      );
    }

    final extrasRaw = json['extras'];
    final extras = extrasRaw is Map<String, Object?>
        ? Map<String, Object?>.unmodifiable(extrasRaw)
        : const <String, Object?>{};

    return Workspace<P>(
      tabs: List.unmodifiable(tabs),
      panes: List.unmodifiable(panes),
      activePaneId: PaneId.fromString(activePaneIdRaw),
      extras: extras,
      version: version,
    );
  }

  /// Schema version. Always equal to [kWorkspaceSchemaVersion] for accepted
  /// documents.
  final int version;

  /// Ordered list of open tabs across all panes.
  final List<WorkspaceTab<P>> tabs;

  /// Open panes (1 or 2 entries).
  final List<WorkspacePane> panes;

  /// Pane that currently has focus. The active tab of this pane receives the
  /// next user action.
  final PaneId activePaneId;

  /// Free-form per-product extras (top-level layout/ambient flags). Stored as
  /// JSON-natural scalar values so unknown keys round-trip safely.
  final Map<String, Object?> extras;

  /// `true` when no tabs are open. Products use this to trigger an empty-
  /// canvas UI state.
  bool get isEmpty => tabs.isEmpty;

  /// Returns the [WorkspacePane] matching [activePaneId].
  WorkspacePane get activePane => panes.firstWhere((p) => p.id == activePaneId);

  /// The active tab id for the active pane, if any.
  TabId? get activeTabId => activePane.activeTabId;

  /// Tabs that belong to the pane identified by [paneId], preserving the
  /// workspace ordering.
  List<WorkspaceTab<P>> tabsForPane(PaneId paneId) => [
    for (final t in tabs)
      if (t.paneId == paneId) t,
  ];

  /// Returns a copy with the given fields replaced.
  Workspace<P> copyWith({
    List<WorkspaceTab<P>>? tabs,
    List<WorkspacePane>? panes,
    PaneId? activePaneId,
    Map<String, Object?>? extras,
  }) {
    return Workspace<P>(
      tabs: tabs ?? this.tabs,
      panes: panes ?? this.panes,
      activePaneId: activePaneId ?? this.activePaneId,
      extras: extras ?? this.extras,
      version: version,
    );
  }

  /// Serializes the workspace to a JSON-compatible map using [codec] to
  /// flatten each tab's payload.
  Map<String, Object?> toJson(WorkspaceCodec<P> codec) => {
    'version': version,
    'tabs': [
      for (final tab in tabs) _tabToJson(tab, codec),
    ],
    'panes': panes.map((p) => p.toJson()).toList(growable: false),
    'activePaneId': activePaneId.value,
    'extras': extras,
  };

  static WorkspaceTab<P> _tabFromJson<P>(
    Map<String, Object?> json,
    WorkspaceCodec<P> codec,
  ) {
    final id = json['id'];
    final paneId = json['paneId'];
    if (id is! String || paneId is! String) {
      throw const WorkspaceInvariantException(
        'WorkspaceTab requires string id and paneId',
      );
    }
    final payload = codec.payloadFromJson(json);
    final displayNameRaw = json['displayName'];
    final displayName = displayNameRaw is String
        ? displayNameRaw
        : codec.displayNameFor(payload);
    return WorkspaceTab<P>(
      id: TabId.fromString(id),
      displayName: displayName,
      paneId: PaneId.fromString(paneId),
      payload: payload,
    );
  }

  static Map<String, Object?> _tabToJson<P>(
    WorkspaceTab<P> tab,
    WorkspaceCodec<P> codec,
  ) {
    final payloadJson = codec.payloadToJson(tab.payload);
    return <String, Object?>{
      'id': tab.id.value,
      'displayName': tab.displayName,
      'paneId': tab.paneId.value,
      ...payloadJson,
    };
  }

  static void _validate<P>({
    required List<WorkspaceTab<P>> tabs,
    required List<WorkspacePane> panes,
    required PaneId activePaneId,
    required int version,
  }) {
    if (version != kWorkspaceSchemaVersion) {
      throw WorkspaceSchemaVersionException(version);
    }
    if (panes.isEmpty) {
      throw const WorkspaceInvariantException(
        'Workspace requires at least one pane',
      );
    }
    if (panes.length > 2) {
      throw WorkspaceInvariantException(
        'Workspace supports at most 2 panes (got ${panes.length})',
      );
    }
    final paneIds = {for (final p in panes) p.id};
    if (paneIds.length != panes.length) {
      throw const WorkspaceInvariantException(
        'Workspace pane ids must be unique',
      );
    }
    if (!paneIds.contains(activePaneId)) {
      throw WorkspaceInvariantException(
        'activePaneId $activePaneId does not match any pane',
      );
    }
    final tabIds = <TabId>{};
    final tabsByPane = <PaneId, Set<TabId>>{};
    for (final t in tabs) {
      if (!tabIds.add(t.id)) {
        throw WorkspaceInvariantException(
          'Workspace tab ids must be unique (duplicate: ${t.id})',
        );
      }
      if (!paneIds.contains(t.paneId)) {
        throw WorkspaceInvariantException(
          'Tab ${t.id} references unknown pane ${t.paneId}',
        );
      }
      tabsByPane.putIfAbsent(t.paneId, () => <TabId>{}).add(t.id);
    }
    for (final pane in panes) {
      final activeId = pane.activeTabId;
      if (activeId == null) continue;
      final inPane = tabsByPane[pane.id] ?? const <TabId>{};
      if (!inPane.contains(activeId)) {
        throw WorkspaceInvariantException(
          'Pane ${pane.id} activeTabId $activeId is not hosted in this pane',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Workspace<P>) return false;
    if (version != other.version) return false;
    if (activePaneId != other.activePaneId) return false;
    if (tabs.length != other.tabs.length) return false;
    if (panes.length != other.panes.length) return false;
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i] != other.tabs[i]) return false;
    }
    for (var i = 0; i < panes.length; i++) {
      if (panes[i] != other.panes[i]) return false;
    }
    if (extras.length != other.extras.length) return false;
    for (final entry in extras.entries) {
      if (other.extras[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    version,
    activePaneId,
    Object.hashAll(tabs),
    Object.hashAll(panes),
    Object.hashAllUnordered(extras.entries.map((e) => e.key)),
  );

  @override
  String toString() =>
      'Workspace(version: $version, tabs: ${tabs.length}, '
      'panes: ${panes.length}, activePaneId: $activePaneId)';
}
