// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/src/crux_settings_category.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// A responsive master-detail Settings body.
///
/// The left pane is a category rail; the right pane scrolls the selected
/// category's content. At or above [dualPaneBreakpoint] the rail and detail
/// sit side by side; below it (phone, narrow split-view, a dialog on a small
/// screen) the panel collapses to a single column — the category list, which
/// swaps to the selected category's content with an in-pane back affordance
/// when a row is tapped.
///
/// This widget owns selection and narrow-collapse state but holds no domain
/// knowledge: the host supplies [categories] (rebuilding this widget with a
/// fresh list when its settings change) and wraps it in its own dialog or
/// route chrome.
class CruxSettingsMasterDetail extends StatefulWidget {
  /// Creates a master-detail settings body for [categories].
  const CruxSettingsMasterDetail({
    required this.categories,
    this.dualPaneBreakpoint = 620,
    this.railWidth = 236,
    this.scrollableDetail = true,
    this.showDetailTitle = true,
    super.key,
  });

  /// Categories shown in the rail, in display order. The first is selected
  /// by default.
  final List<CruxSettingsCategory> categories;

  /// Width at/above which the rail and detail pane render side by side.
  final double dualPaneBreakpoint;

  /// Width of the category rail in the side-by-side layout.
  final double railWidth;

  /// Whether the shell wraps the detail content in its own scroll view
  /// (default). Set `false` when each category's [CruxSettingsCategory.content]
  /// is already a scrollable (e.g. a `ListView`) and should scroll itself —
  /// the shell then renders it in an `Expanded` and adds no outer scroll view.
  final bool scrollableDetail;

  /// Whether the detail pane shows an icon + title header above the content
  /// (default). Set `false` when each category's content provides its own
  /// heading. The narrow back-bar always names the category regardless.
  final bool showDetailTitle;

  @override
  State<CruxSettingsMasterDetail> createState() =>
      _CruxSettingsMasterDetailState();
}

class _CruxSettingsMasterDetailState extends State<CruxSettingsMasterDetail> {
  // A dedicated controller bound to the detail Scrollbar so the thumb tracks
  // the detail pane (not an inner horizontal list), paired with the outer
  // ScrollConfiguration that opts every pointer kind into drag so a
  // two-finger trackpad pan still scrolls the pane.
  final ScrollController _detailController = ScrollController();

  /// One focus node per rail tile, so arrow keys can move focus between
  /// tiles that Tab skips.
  final List<FocusNode> _tileNodes = <FocusNode>[];

  /// Index into [CruxSettingsMasterDetail.categories].
  int _selected = 0;

  /// Narrow layout only: whether the detail (vs. the list) is showing.
  bool _detailOpenOnNarrow = false;

  @override
  void dispose() {
    _detailController.dispose();
    for (final node in _tileNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncTileNodes(int count) {
    while (_tileNodes.length < count) {
      _tileNodes.add(
        FocusNode(debugLabel: 'Settings category ${_tileNodes.length}'),
      );
    }
    while (_tileNodes.length > count) {
      _tileNodes.removeLast().dispose();
    }
  }

  void _open(int index) {
    setState(() {
      _selected = index;
      _detailOpenOnNarrow = true;
    });
    // A freshly opened category starts at the top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_detailController.hasClients) _detailController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = _selected.clamp(0, categories.length - 1);
    _syncTileNodes(categories.length);

    return ScrollConfiguration(
      behavior: const _AnyPointerScrollBehavior(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= widget.dualPaneBreakpoint;
          if (wide) {
            // Each pane is its own traversal group. Without the groups the
            // window-wide reading order sorts rail tiles and detail rows by
            // height, so Tab alternates between the two columns.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: widget.railWidth,
                  child: FocusTraversalGroup(
                    child: _CategoryRail(
                      categories: categories,
                      selected: selected,
                      focusNodes: _tileNodes,
                      selectionFollowsFocus: true,
                      onSelect: (i) => setState(() => _selected = i),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: FocusTraversalGroup(
                    child: _DetailPane(
                      category: categories[selected],
                      controller: _detailController,
                      showTitle: widget.showDetailTitle,
                      scrollable: widget.scrollableDetail,
                    ),
                  ),
                ),
              ],
            );
          }
          // Narrow: list → detail with a back affordance.
          if (!_detailOpenOnNarrow) {
            return _CategoryRail(
              categories: categories,
              selected: selected,
              focusNodes: _tileNodes,
              selectionFollowsFocus: false,
              onSelect: _open,
              showChevron: true,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailBackBar(
                title: categories[selected].title,
                onBack: () => setState(() => _detailOpenOnNarrow = false),
              ),
              const Divider(height: 1),
              Expanded(
                child: _DetailPane(
                  category: categories[selected],
                  controller: _detailController,
                  showTitle: false,
                  scrollable: widget.scrollableDetail,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Left pane: a vertical list of selectable category rows.
///
/// With [selectionFollowsFocus] (the side-by-side layout) the rail is one
/// Tab stop, the selected tile: Up, Down, Home and End move the selection
/// and the focus together, and Tab moves on into the detail pane. Without
/// it (the narrow layout, where selecting a tile navigates away) every tile
/// is a Tab stop and the arrow keys move focus only.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.categories,
    required this.selected,
    required this.focusNodes,
    required this.selectionFollowsFocus,
    required this.onSelect,
    this.showChevron = false,
  });

  final List<CruxSettingsCategory> categories;
  final int selected;
  final List<FocusNode> focusNodes;
  final bool selectionFollowsFocus;
  final ValueChanged<int> onSelect;
  final bool showChevron;

  void _move(int Function(int from) to) {
    final from = focusNodes.indexWhere((n) => n.hasPrimaryFocus);
    final target = to(
      from == -1 ? selected : from,
    ).clamp(0, categories.length - 1);
    if (selectionFollowsFocus) onSelect(target);
    focusNodes[target].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < focusNodes.length; i++) {
      focusNodes[i].skipTraversal = selectionFollowsFocus && i != selected;
    }
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _move((i) => i + 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _move((i) => i - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _move((_) => 0),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _move((_) => categories.length - 1),
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: categories.length,
        itemBuilder: (context, i) => _CategoryTile(
          category: categories[i],
          selected: i == selected,
          focusNode: focusNodes[i],
          showChevron: showChevron,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.focusNode,
    required this.showChevron,
    required this.onTap,
  });

  final CruxSettingsCategory category;
  final bool selected;
  final FocusNode focusNode;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        // The selection was colour and weight only; a screen reader heard
        // eleven identical names.
        child: MergeSemantics(
          child: Semantics(
            button: true,
            selected: selected,
            child: _tileInk(context, theme, fg),
          ),
        ),
      ),
    );
  }

  Widget _tileInk(BuildContext context, ThemeData theme, Color fg) => InkWell(
    focusNode: focusNode,
    // Opening Settings lands on the selected category, so a screen
    // reader has something to announce and Escape has a focused
    // control to start from.
    autofocus: selected,
    onTap: onTap,
    child: Padding(
      // 14 + 20 + 14: the tile is its own tap target now, and 48 is the floor.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Icon(category.icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.title,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (showChevron)
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    ),
  );
}

/// Right pane: the selected category's content, scrollable, with an optional
/// icon + title heading (suppressed on the narrow layout where the back bar
/// already names the category).
class _DetailPane extends StatelessWidget {
  const _DetailPane({
    required this.category,
    required this.controller,
    this.showTitle = true,
    this.scrollable = true,
  });

  final CruxSettingsCategory category;
  final ScrollController controller;
  final bool showTitle;
  final bool scrollable;

  Widget _titleHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Icon(category.icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(category.title, style: theme.textTheme.titleLarge),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Self-scrolling content (e.g. a ListView) scrolls itself: the header
    // stays pinned and the content fills the remaining space.
    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) _titleHeader(context),
          Expanded(child: category.content),
        ],
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      controller: controller,
      child: SingleChildScrollView(
        controller: controller,
        primary: false,
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle) _titleHeader(context),
            category.content,
          ],
        ),
      ),
    );
  }
}

/// Narrow layout: the bar above the detail content with a back button to the
/// category list and the current category's name.
class _DetailBackBar extends StatelessWidget {
  const _DetailBackBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// [ScrollBehavior] that allows every pointer kind — including macOS trackpad
/// gestures — to drive the surrounding scrollables. Flutter's default
/// MaterialScrollBehavior excludes [PointerDeviceKind.trackpad] for some
/// scrollables when an inner horizontal scrollable is mounted, which makes
/// two-finger vertical scrolling fail over those areas.
class _AnyPointerScrollBehavior extends MaterialScrollBehavior {
  const _AnyPointerScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}
