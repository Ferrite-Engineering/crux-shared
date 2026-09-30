// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_projects/crux_projects.dart';
import 'package:crux_projects_ui/src/crux_projects_ui_strings.dart';
import 'package:crux_projects_ui/src/project_activation_observer.dart';
import 'package:crux_projects_ui/src/recent_project_reopen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cross-suite project-switcher dialog.
///
/// Displays open projects (with an "active" indicator) and recently-closed
/// projects in two sections, both filterable through a search field that
/// matches on `displayName` and `projectPath`.
///
/// **Selection routing.**
/// - Selecting an *open* project → `setActiveProject(id)`, then dismiss.
/// - Selecting a *recent* project → `openProject(path)`, then dismiss. A
///   project the registry can no longer load is reported through
///   `recentProjectUnavailableReporterProvider` and forgotten.
///
/// **Per-row actions.** Open rows offer Close (which moves the project to
/// recents); recent rows offer Forget (which clears the entry).
///
/// **Keyboard.** Arrow keys cycle the visible rows, Enter activates,
/// Escape dismisses.
///
/// **Tier gating is the host's job, not this widget's.** The dialog renders
/// whatever badge `cruxProjectsUiBadgeBuilderProvider` supplies but does not
/// gate itself — the gate belongs in the opener that decides whether to
/// mount it, which is also the thing that can show an upgrade dialog
/// instead.
class CruxProjectSwitcherDialog extends ConsumerStatefulWidget {
  /// Creates the dialog.
  const CruxProjectSwitcherDialog({super.key});

  /// `showDialog` wrapper for action dispatchers.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(child: CruxProjectSwitcherDialog()),
    );
  }

  @override
  ConsumerState<CruxProjectSwitcherDialog> createState() =>
      _CruxProjectSwitcherDialogState();
}

class _CruxProjectSwitcherDialogState
    extends ConsumerState<CruxProjectSwitcherDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final next = _searchController.text;
      if (next != _searchQuery) {
        setState(() {
          _searchQuery = next;
          // Reset the cursor: keeping an index across a filter change
          // points it at a different project than the one the user was
          // looking at, and Enter would then open the wrong thing.
          _highlightedIndex = 0;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(cruxProjectsUiStringsProvider);
    final badgeBuilder = ref.watch(cruxProjectsUiBadgeBuilderProvider);
    final searchOpener = ref.watch(crossProjectSearchOpenerProvider);
    final asyncWorkspace = ref.watch(projectWorkspaceProvider);
    final workspace = asyncWorkspace.maybeWhen(
      data: (ws) => ws,
      orElse: ProjectWorkspace.empty,
    );
    final filtered = _filter(workspace);

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event, filtered),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(
              title: strings.switcherTitle,
              tooltip: strings.switcherDismissTooltip,
              badge: badgeBuilder(context),
              onDismiss: () => Navigator.of(context).maybePop(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: strings.switcherSearchHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Flexible(
              child: _ListBody(
                filtered: filtered,
                workspace: workspace,
                strings: strings,
                searchQuery: _searchQuery,
                highlightedIndex: _highlightedIndex,
                onHover: (i) => setState(() => _highlightedIndex = i),
                onSelect: _selectAt,
              ),
            ),
            // Only advertise cross-project search when the host actually
            // installed it.
            if (searchOpener != null) ...<Widget>[
              const Divider(height: 1),
              _Footer(
                label: strings.switcherFooterSearchAcrossProjects,
                onPressed: () async {
                  // Capture the root navigator: the local BuildContext is
                  // gone after the switcher pops, and the search dialog has
                  // to route through the same Navigator.
                  final navContext = Navigator.of(context).context;
                  await Navigator.of(context).maybePop();
                  if (!navContext.mounted) return;
                  searchOpener(navContext);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKey(KeyEvent event, _FilteredEntries filtered) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    final totalRows = filtered.totalCount;
    if (totalRows == 0) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1) % totalRows;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1 + totalRows) % totalRows;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_selectAt(_highlightedIndex));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _selectAt(int index) async {
    final asyncWorkspace = ref.read(projectWorkspaceProvider);
    final workspace = asyncWorkspace.maybeWhen(
      data: (ws) => ws,
      orElse: ProjectWorkspace.empty,
    );
    final filtered = _filter(workspace);
    if (index < 0 || index >= filtered.totalCount) return;
    final registry = ref.read(projectRegistryProvider);
    final openCount = workspace.openProjects.length;
    if (index < filtered.open.length) {
      final target = filtered.open[index];
      await registry.setActiveProject(target.id);
      reportProjectActivation(
        ref,
        source: ProjectActivationSource.switcher,
        projectPath: target.projectPath,
        projectId: target.id,
        openProjectCount: openCount,
      );
    } else {
      final descriptor = filtered.recent[index - filtered.open.length];
      final opened = await reopenRecentProject(
        registry: registry,
        recent: descriptor,
        context: context,
        report: ref.read(recentProjectUnavailableReporterProvider),
      );
      if (opened) {
        reportProjectActivation(
          ref,
          source: ProjectActivationSource.switcherRecents,
          projectPath: descriptor.projectPath,
          openProjectCount: openCount,
        );
      }
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  _FilteredEntries _filter(ProjectWorkspace workspace) {
    final q = _searchQuery.trim().toLowerCase();
    bool matches(ProjectDescriptor d) {
      if (q.isEmpty) return true;
      return d.displayName.toLowerCase().contains(q) ||
          d.projectPath.toLowerCase().contains(q);
    }

    return _FilteredEntries(
      open: workspace.openProjects.where(matches).toList(growable: false),
      recent: workspace.recentProjects.where(matches).toList(growable: false),
    );
  }
}

class _FilteredEntries {
  const _FilteredEntries({required this.open, required this.recent});

  final List<ProjectDescriptor> open;
  final List<ProjectDescriptor> recent;

  int get totalCount => open.length + recent.length;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.tooltip,
    required this.badge,
    required this.onDismiss,
  });

  final String title;
  final String tooltip;
  final Widget? badge;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (badge != null) ...<Widget>[
            const SizedBox(width: 8),
            badge!,
          ],
          const Spacer(),
          IconButton(
            tooltip: tooltip,
            icon: const Icon(Icons.close),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _ListBody extends ConsumerWidget {
  const _ListBody({
    required this.filtered,
    required this.workspace,
    required this.strings,
    required this.searchQuery,
    required this.highlightedIndex,
    required this.onHover,
    required this.onSelect,
  });

  final _FilteredEntries filtered;
  final ProjectWorkspace workspace;
  final CruxProjectsUiStrings strings;
  final String searchQuery;
  final int highlightedIndex;
  final ValueChanged<int> onHover;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filtered.totalCount == 0) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            searchQuery.isEmpty
                ? strings.switcherEmptyOpen
                : strings.switcherEmptySearch,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        _SectionHeader(label: strings.switcherSectionOpen),
        if (filtered.open.isEmpty)
          _SectionEmpty(text: strings.switcherEmptyOpen)
        else
          for (var i = 0; i < filtered.open.length; i++)
            _ProjectRow(
              descriptor: filtered.open[i],
              isHighlighted: highlightedIndex == i,
              onHover: () => onHover(i),
              onTap: () => onSelect(i),
              trailing: _RowAction(
                label: strings.switcherActionClose,
                icon: Icons.close,
                onPressed: () async {
                  await ref
                      .read(projectRegistryProvider)
                      .closeProject(filtered.open[i].id);
                },
              ),
              indicator: filtered.open[i].id == workspace.activeProjectId
                  ? _ActiveChip(label: strings.switcherActiveIndicator)
                  : null,
            ),
        const SizedBox(height: 8),
        _SectionHeader(label: strings.switcherSectionRecent),
        if (filtered.recent.isEmpty)
          _SectionEmpty(text: strings.switcherEmptyRecent)
        else
          for (var i = 0; i < filtered.recent.length; i++)
            _ProjectRow(
              descriptor: filtered.recent[i],
              isHighlighted: highlightedIndex == filtered.open.length + i,
              onHover: () => onHover(filtered.open.length + i),
              onTap: () => onSelect(filtered.open.length + i),
              trailing: _RowAction(
                label: strings.switcherActionForget,
                icon: Icons.delete_outline,
                onPressed: () async {
                  await ref
                      .read(projectRegistryProvider)
                      .clearRecentProject(filtered.recent[i].id);
                },
              ),
              indicator: null,
            ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.descriptor,
    required this.isHighlighted,
    required this.onHover,
    required this.onTap,
    required this.trailing,
    required this.indicator,
  });

  final ProjectDescriptor descriptor;
  final bool isHighlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final Widget trailing;
  final Widget? indicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: isHighlighted
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  descriptor.isPinned ? Icons.push_pin : Icons.folder,
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
                      Text(
                        descriptor.projectPath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (indicator != null) ...<Widget>[
                  const SizedBox(width: 8),
                  indicator!,
                ],
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.travel_explore, size: 16),
          label: Text(label),
          onPressed: onPressed,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ),
    );
  }
}
