// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// How a project became active.
///
/// The distinction matters to a host counting feature usage: reopening
/// something from recents is a different act from switching between projects
/// already open, and a host that conflates them cannot tell whether its
/// recents list is earning its place.
enum ProjectActivationSource {
  /// Selected from the switcher's *open projects* section — a switch between
  /// projects already in the workspace.
  switcher,

  /// Reopened from the switcher's *recent* section.
  switcherRecents,

  /// Reopened from the standalone recents panel.
  recentsPanel,
}

/// A project activation that happened inside a `crux_projects_ui` widget.
@immutable
class ProjectActivation {
  /// Creates an activation record.
  const ProjectActivation({
    required this.source,
    required this.projectPath,
    required this.openProjectCount,
    this.projectId,
  });

  /// Which affordance the user used.
  final ProjectActivationSource source;

  /// Path of the project that became active.
  ///
  /// **Host responsibility:** this is a filesystem path. A host forwarding it
  /// into telemetry must hash or drop it — the suite's telemetry contract
  /// carries no user paths. It is supplied because a host may legitimately
  /// need it for a non-telemetry purpose (a recents reorder, a log line the
  /// user asked for).
  final String projectPath;

  /// Stable id of the project, when the activation was a switch between
  /// already-open projects. Null when reopening, because the id is assigned
  /// by the registry as part of the open.
  final String? projectId;

  /// How many projects were open at the moment of activation.
  ///
  /// This is the number worth counting: it answers how wide real
  /// multi-project workspaces actually get, which is the question the feature
  /// was built to serve.
  final int openProjectCount;
}

/// Called when a `crux_projects_ui` widget activates a project.
typedef ProjectActivationObserver = void Function(ProjectActivation activation);

/// Observer invoked on every project activation driven by this package.
///
/// ### Why this exists
///
/// The package deliberately has no `crux_telemetry` dependency — shared UI
/// must not decide what a host records. But without *any* seam, a host that
/// adopts these widgets silently loses instrumentation it previously had:
/// SimCrux's switcher fork emitted a catalogued `project.switched` event with
/// two tests and a catalog-conformance entry behind it, and migrating onto the
/// shared widgets would have deleted that event without a single test
/// failing. LintCrux, which adopted the package earlier, emitted nothing here
/// because it had no seam in crux-shared to emit through — the gap this
/// closes.
///
/// The default is a no-op, so a host that wants no instrumentation writes
/// nothing and pays nothing.
///
/// ```dart
/// projectActivationObserverProvider.overrideWithValue((activation) {
///   telemetry.record(
///     'project.switched',
///     properties: {'projects': activation.openProjectCount},
///   );
/// }),
/// ```
final Provider<ProjectActivationObserver> projectActivationObserverProvider =
    Provider<ProjectActivationObserver>(
      (ref) => _noopObserver,
      name: 'projectActivationObserverProvider',
    );

void _noopObserver(ProjectActivation _) {}

/// Reports an activation to the host's observer, swallowing anything it
/// throws.
///
/// Instrumentation must never break the interaction it is measuring: a host
/// whose telemetry sink is misconfigured should still get its project
/// switched. Kept here rather than inlined so both widgets share the
/// guarantee.
void reportProjectActivation(
  WidgetRef ref, {
  required ProjectActivationSource source,
  required String projectPath,
  required int openProjectCount,
  String? projectId,
}) {
  final ProjectActivationObserver observer;
  try {
    observer = ref.read(projectActivationObserverProvider);
  } on Object {
    return;
  }
  notifyProjectActivation(
    observer,
    source: source,
    projectPath: projectPath,
    openProjectCount: openProjectCount,
    projectId: projectId,
  );
}

/// [reportProjectActivation] for an [observer] read earlier, with the same
/// guarantee that nothing it throws escapes.
///
/// For a caller that learns the outcome after an await its widget may not
/// survive: reading the observer from a `ref` whose widget is gone throws,
/// and [reportProjectActivation] would swallow that and report nothing.
void notifyProjectActivation(
  ProjectActivationObserver observer, {
  required ProjectActivationSource source,
  required String projectPath,
  required int openProjectCount,
  String? projectId,
}) {
  try {
    observer(
      ProjectActivation(
        source: source,
        projectPath: projectPath,
        openProjectCount: openProjectCount,
        projectId: projectId,
      ),
    );
  } on Object {
    // Deliberately swallowed — see the doc comment.
  }
}
