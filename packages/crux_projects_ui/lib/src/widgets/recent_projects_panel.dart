// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:crux_projects_ui/src/crux_projects_ui_strings.dart';
import 'package:crux_projects_ui/src/project_activation_observer.dart';
import 'package:crux_projects_ui/src/recent_project_reopen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-suite recent-projects panel.
///
/// Lists the workspace's recently-closed projects with per-row Reopen and
/// Forget actions. Mounted on the empty-workspace state as a discovery
/// surface, and reachable from the switcher.
///
/// **Layout: crop, don't crush.** When the mounting surface gives the card
/// a bounded height, the rows list becomes the flexible scrolling region so
/// the header stays fixed and the card never overflows. When the height is
/// unbounded (inside an outer scroll view), the list stays non-scrolling
/// and the outer view handles it.
class CruxRecentProjectsPanel extends ConsumerWidget {
  /// Creates the panel.
  const CruxRecentProjectsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(cruxProjectsUiStringsProvider);
    final badgeBuilder = ref.watch(cruxProjectsUiBadgeBuilderProvider);
    final theme = Theme.of(context);
    final asyncWorkspace = ref.watch(projectWorkspaceProvider);
    final workspace = asyncWorkspace.maybeWhen(
      data: (ws) => ws,
      orElse: ProjectWorkspace.empty,
    );
    final badge = badgeBuilder(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final hasRecents = workspace.recentProjects.isNotEmpty;
            final body = hasRecents
                ? _RecentProjectsList(
                    descriptors: workspace.recentProjects,
                    strings: strings,
                    scrollable: bounded,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        strings.recentsPanelEmpty,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.history,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        strings.recentsPanelTitle,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...<Widget>[
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ],
                ),
                const Divider(height: 16),
                // Flexible (loose) keeps the card hugging its content when
                // the rows fit; it only clamps — and the list only scrolls
                // — once the rows would exceed the card bounds.
                if (bounded && hasRecents) Flexible(child: body) else body,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecentProjectsList extends StatefulWidget {
  const _RecentProjectsList({
    required this.descriptors,
    required this.strings,
    required this.scrollable,
  });

  final List<ProjectDescriptor> descriptors;
  final CruxProjectsUiStrings strings;
  final bool scrollable;

  @override
  State<_RecentProjectsList> createState() => _RecentProjectsListState();
}

class _RecentProjectsListState extends State<_RecentProjectsList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      controller: widget.scrollable ? _controller : null,
      shrinkWrap: true,
      physics: widget.scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: widget.descriptors.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _RecentProjectRow(
        descriptor: widget.descriptors[index],
        strings: widget.strings,
      ),
    );
    if (!widget.scrollable) return list;
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: list,
    );
  }
}

class _RecentProjectRow extends ConsumerWidget {
  const _RecentProjectRow({required this.descriptor, required this.strings});

  final ProjectDescriptor descriptor;
  final CruxProjectsUiStrings strings;

  /// Reopens [descriptor], reporting the activation only once it has opened.
  ///
  /// Everything is read from [ref] before the await: either way the entry
  /// leaves the recents list, and this row leaves the tree with it.
  Future<void> _reopen(BuildContext context, WidgetRef ref) async {
    final registry = ref.read(projectRegistryProvider);
    final report = ref.read(recentProjectUnavailableReporterProvider);
    final observer = ref.read(projectActivationObserverProvider);
    final openProjectCount = ref
        .read(projectWorkspaceProvider)
        .maybeWhen(data: (ws) => ws.openProjects.length, orElse: () => 0);
    final opened = await reopenRecentProject(
      registry: registry,
      recent: descriptor,
      context: context,
      report: report,
    );
    if (!opened) return;
    notifyProjectActivation(
      observer,
      source: ProjectActivationSource.recentsPanel,
      projectPath: descriptor.projectPath,
      openProjectCount: openProjectCount,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.folder_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  descriptor.displayName,
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Tooltip(
                  message: descriptor.projectPath,
                  child: Text(
                    descriptor.projectPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(strings.recentsPanelReopen),
            onPressed: () => unawaited(_reopen(context, ref)),
          ),
          TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text(strings.recentsPanelForget),
            onPressed: () {
              unawaited(
                ref
                    .read(projectRegistryProvider)
                    .clearRecentProject(descriptor.id),
              );
            },
          ),
        ],
      ),
    );
  }
}
