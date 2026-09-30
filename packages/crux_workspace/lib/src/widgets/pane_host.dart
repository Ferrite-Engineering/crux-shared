// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/src/pane_container_manager.dart';
import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_container_manager.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/widgets/viewer_tab_bar.dart';
import 'package:crux_workspace/src/widgets/viewer_tab_bar_strings.dart';
import 'package:crux_workspace/src/workspace.dart';
import 'package:crux_workspace/src/workspace_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builder for the per-tab content widget rendered inside the
/// [IndexedStack] that backs each pane.
typedef TabContentBuilder<P> =
    Widget Function(BuildContext context, WorkspaceTab<P> tab);

/// Builder for the stack widget that hosts a pane's per-tab content subtrees.
/// Receives the active [index] and the (already keyed) [children] list, and
/// returns the widget that shows [children]`[index]` while keeping the others
/// available.
///
/// Defaults to a lazy keep-alive stack: a tab's subtree is built the first
/// time that tab becomes active and then stays mounted (so its state survives
/// tab switches, exactly as an [IndexedStack] would), while tabs that have
/// never been activated cost nothing. Supply your own to change that policy —
/// e.g. a stack that also *unmounts* cold tabs to reclaim GPU surfaces.
///
/// The supplied [children] each carry a unique non-null `ValueKey`, so a
/// key-contract stack (lazy/keep-alive) works without further wrapping.
typedef PaneStackBuilder = Widget Function(int index, List<Widget> children);

/// Builder for the multi-pane layout. Receives the per-pane subtrees (already
/// wrapped in their pane scopes) and returns the row that arranges them.
/// Defaults to an even [Row] with a thin [VerticalDivider]; products that want
/// a drag-resizable splitter supply their own layout here.
typedef PaneSplitLayoutBuilder =
    Widget Function(BuildContext context, List<Widget> panes);

/// Builder for the border drawn around each pane's container. Receives whether
/// the pane [isActive] (the workspace's focused pane) and whether the workspace
/// is currently [isSplit] (more than one pane is being rendered), and returns
/// the [BoxBorder] to paint. Optional; when null the host uses the built-in
/// default (a thin translucent-primary border on the active pane, transparent
/// otherwise). Products that need a specific active/inactive treatment — e.g.
/// a full-strength accent on the focused pane plus a visible at-rest divider,
/// or suppressing the active indicator entirely when un-split (there is no
/// second pane to disambiguate) — supply their own.
typedef PaneBorderBuilder =
    BoxBorder Function(
      BuildContext context, {
      required bool isActive,
      required bool isSplit,
    });

/// Root layout widget for a workspace's pane region.
///
/// Renders the workspace's empty-canvas state when `workspace.tabs.isEmpty`
/// (the host product supplies the `emptyCanvasContent` widget — typically an
/// [`EmptyCanvasState`] with product-specific recent-files / actions). When
/// the workspace has tabs, renders one or two panes side-by-side per
/// `workspace.panes.length`.
///
/// Each pane:
/// * Hosts its own [ViewerTabBar] filtered to that pane's tabs.
/// * Wraps its content in an [IndexedStack] that swaps the visible tab
///   without rebuilding inactive tabs.
/// * Sits inside a per-pane `UncontrolledProviderScope` whose container is
///   supplied by [panes]. This lets the host product register per-pane
///   providers (render stats, focus, ...) that resolve from the active
///   pane's container.
/// * The product-supplied [tabContentBuilder] wraps its own subtree in an
///   `UncontrolledProviderScope` keyed on the active tab's container from
///   [tabs] so that per-tab providers (cursor, zoom, selection, ...) resolve
///   from the correct container.
///
/// Tapping anywhere in a non-active pane focuses it (no-op when the host
/// product gates split-pane on device class — pass `enableSplitPane: false`
/// to render only the active pane and ignore any second pane in the
/// workspace document).
class PaneHost<P> extends ConsumerWidget {
  /// Creates a pane host.
  const PaneHost({
    required this.provider,
    required this.tabContentBuilder,
    required this.emptyCanvasContent,
    this.tabs,
    this.panes,
    this.tabContainerFor,
    this.paneContainerFor,
    this.defaultPayloadBuilder,
    this.contextMenuItems,
    this.paneTrailingActionsBuilder,
    this.tabTooltipBuilder,
    this.tabFilePath,
    this.onRevealTab,
    this.contextMenuBuilder,
    this.paneBorderBuilder,
    this.useDragHandle = true,
    this.stackBuilder,
    this.splitLayoutBuilder,
    this.sizing = const ViewerTabBarSizing(),
    this.tabBarLeadingInset = 0,
    this.autoHideScrollChevrons = false,
    this.showTabBars = true,
    this.strings = const ViewerTabBarStringsEn(),
    this.enableSplitPane = true,
    super.key,
  }) : assert(
         tabs != null || tabContainerFor != null,
         'Provide either tabs (TabContainerManager) or tabContainerFor.',
       ),
       assert(
         panes != null || paneContainerFor != null,
         'Provide either panes (PaneContainerManager) or paneContainerFor.',
       );

  /// Workspace provider for the host product.
  final AsyncNotifierProvider<WorkspaceNotifier<P>, Workspace<P>> provider;

  /// Builds the per-tab content widget rendered inside the [IndexedStack].
  final TabContentBuilder<P> tabContentBuilder;

  /// Per-tab `ProviderContainer` manager owned by the host product. Optional
  /// when [tabContainerFor] is supplied (e.g. a product that wraps the manager
  /// with extra per-container setup resolves containers through the callback).
  final TabContainerManager? tabs;

  /// Per-pane `ProviderContainer` manager owned by the host product. Optional
  /// when [paneContainerFor] is supplied.
  final PaneContainerManager? panes;

  /// Optional override for resolving a tab's `ProviderContainer`. When
  /// supplied it takes precedence over [tabs]; lets a product run wrapper
  /// logic (e.g. arming a per-tab autosave on first access) that a bare
  /// [TabContainerManager] cannot.
  final ProviderContainer Function(TabId tabId)? tabContainerFor;

  /// Optional override for resolving a pane's `ProviderContainer`. When
  /// supplied it takes precedence over [panes]; lets a product run wrapper
  /// logic (e.g. allocating per-pane render-stats resources) before the
  /// container is created.
  final ProviderContainer Function(PaneId paneId)? paneContainerFor;

  /// Widget rendered when the workspace has zero tabs. Typically an
  /// [`EmptyCanvasState`] with product-specific recent-files / actions.
  final Widget emptyCanvasContent;

  /// Forwarded to each pane's [ViewerTabBar.defaultPayloadBuilder]; when
  /// null the "+" button is hidden.
  final P Function()? defaultPayloadBuilder;

  /// Forwarded to each pane's [ViewerTabBar.contextMenuItems].
  final TabContextMenuItemsBuilder<P>? contextMenuItems;

  /// Forwarded to each pane's [ViewerTabBar.trailingActionsBuilder]. Null
  /// (the default) renders no extra trailing affordances.
  final PaneTrailingActionsBuilder? paneTrailingActionsBuilder;

  /// Forwarded to each pane's [ViewerTabBar.tabTooltipBuilder].
  final TabTooltipBuilder<P>? tabTooltipBuilder;

  /// Forwarded to each pane's [ViewerTabBar.tabFilePath].
  final String? Function(WorkspaceTab<P> tab)? tabFilePath;

  /// Forwarded to each pane's [ViewerTabBar.onRevealTab].
  final void Function(String filePath)? onRevealTab;

  /// Forwarded to each pane's [ViewerTabBar.contextMenuBuilder].
  final TabContextMenuBuilder<P>? contextMenuBuilder;

  /// Optional override for the per-pane container border. When null the
  /// built-in default is used (thin translucent-primary on the active pane,
  /// transparent otherwise).
  final PaneBorderBuilder? paneBorderBuilder;

  /// Forwarded to each pane's [ViewerTabBar.useDragHandle].
  final bool useDragHandle;

  /// Optional override for the stack that hosts each pane's per-tab content.
  /// Defaults to a lazy keep-alive stack — see [PaneStackBuilder].
  final PaneStackBuilder? stackBuilder;

  /// Optional override for the multi-pane layout. Defaults to an even [Row]
  /// with a thin [VerticalDivider]; supply a drag-resizable splitter here.
  final PaneSplitLayoutBuilder? splitLayoutBuilder;

  /// Forwarded to each pane's [ViewerTabBar.sizing].
  final ViewerTabBarSizing sizing;

  /// Forwarded to each pane's [ViewerTabBar.leadingInset].
  final double tabBarLeadingInset;

  /// Forwarded to each pane's [ViewerTabBar.autoHideScrollChevrons].
  final bool autoHideScrollChevrons;

  /// Whether to render each pane's [ViewerTabBar]. Products that hide the tab
  /// strip on narrow layouts (e.g. phone) pass `false`; the pane content still
  /// renders. Defaults to `true`.
  final bool showTabBars;

  /// Forwarded to each pane's [ViewerTabBar.strings].
  final ViewerTabBarStrings strings;

  /// When false, only the active pane is rendered even if the workspace has
  /// two panes. Used by host products to gate split-pane on device class
  /// (phone / phone-landscape / narrow tablet) without forcing the
  /// workspace document into a single-pane shape.
  final bool enableSplitPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncWs = ref.watch(provider);
    return asyncWs.when(
      data: (ws) => _build(context, ref, ws),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _build(BuildContext context, WidgetRef ref, Workspace<P> ws) {
    if (ws.tabs.isEmpty) return emptyCanvasContent;

    final notifier = ref.read(provider.notifier);
    final panesToRender = enableSplitPane
        ? ws.panes
        : ws.panes.where((p) => p.id == ws.activePaneId).toList();

    if (panesToRender.length <= 1) {
      return _buildSinglePane(
        context: context,
        ws: ws,
        pane: panesToRender.single.id,
        notifier: notifier,
        isSplit: false,
      );
    }

    final paneWidgets = [
      for (final pane in panesToRender)
        _buildSinglePane(
          context: context,
          ws: ws,
          pane: pane.id,
          notifier: notifier,
          isSplit: true,
        ),
    ];

    final splitBuilder = splitLayoutBuilder;
    if (splitBuilder != null) {
      return splitBuilder(context, paneWidgets);
    }

    return Row(
      children: [
        for (var i = 0; i < paneWidgets.length; i++) ...[
          Expanded(child: paneWidgets[i]),
          if (i < paneWidgets.length - 1)
            const VerticalDivider(width: 1, thickness: 1),
        ],
      ],
    );
  }

  Widget _buildSinglePane({
    required BuildContext context,
    required Workspace<P> ws,
    required PaneId pane,
    required WorkspaceNotifier<P> notifier,
    required bool isSplit,
  }) {
    final isActive = ws.activePaneId == pane;
    final paneContainer = _resolvePaneContainer(pane);
    final paneTabs = ws.tabsForPane(pane);
    final activeIdx = _activeIndexFor(paneTabs, ws, pane);

    return UncontrolledProviderScope(
      container: paneContainer,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!isActive) unawaited(notifier.setActivePane(pane));
        },
        child: Container(
          decoration: BoxDecoration(
            border:
                paneBorderBuilder?.call(
                  context,
                  isActive: isActive,
                  isSplit: isSplit,
                ) ??
                Border.all(
                  color: isActive
                      ? Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.4)
                      : Colors.transparent,
                  width: 2,
                ),
          ),
          child: Column(
            children: [
              if (showTabBars)
                ViewerTabBar<P>(
                  paneId: pane,
                  provider: provider,
                  strings: strings,
                  defaultPayloadBuilder: defaultPayloadBuilder,
                  contextMenuItems: contextMenuItems,
                  contextMenuBuilder: contextMenuBuilder,
                  tabTooltipBuilder: tabTooltipBuilder,
                  tabFilePath: tabFilePath,
                  onRevealTab: onRevealTab,
                  trailingActionsBuilder: paneTrailingActionsBuilder,
                  useDragHandle: useDragHandle,
                  sizing: sizing,
                  leadingInset: tabBarLeadingInset,
                  autoHideScrollChevrons: autoHideScrollChevrons,
                  isActivePane: isActive,
                ),
              Expanded(
                child: paneTabs.isEmpty
                    ? const SizedBox.expand()
                    : _buildStack(activeIdx, [
                        for (final tab in paneTabs)
                          RepaintBoundary(
                            // Every child carries a unique, namespaced key so
                            // a key-contract stack (the default lazy one, or a
                            // product's own) tracks slots across reorders.
                            key: ValueKey('paneContent_${tab.id.value}'),
                            // A tab's content is a waveform canvas, schematic
                            // or netlist view — isolate each one's painting so
                            // a repaint in the active tab cannot dirty the
                            // layer of a keep-alive sibling.
                            child: UncontrolledProviderScope(
                              container: _resolveTabContainer(tab.id),
                              child: Builder(
                                builder: (ctx) => tabContentBuilder(ctx, tab),
                              ),
                            ),
                          ),
                      ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ProviderContainer _resolveTabContainer(TabId id) =>
      tabContainerFor?.call(id) ?? tabs!.containerFor(id);

  ProviderContainer _resolvePaneContainer(PaneId id) =>
      paneContainerFor?.call(id) ?? panes!.containerFor(id);

  Widget _buildStack(int index, List<Widget> children) {
    final builder = stackBuilder;
    if (builder != null) return builder(index, children);
    return _LazyKeepAliveStack(index: index, children: children);
  }

  int _activeIndexFor(
    List<WorkspaceTab<P>> paneTabs,
    Workspace<P> ws,
    PaneId pane,
  ) {
    final activeTabId = ws.panes.firstWhere((p) => p.id == pane).activeTabId;
    if (activeTabId == null) return 0;
    final idx = paneTabs.indexWhere((t) => t.id == activeTabId);
    return idx == -1 ? 0 : idx;
  }
}

/// Default pane content stack: an [IndexedStack] whose slots are populated
/// lazily.
///
/// A plain `IndexedStack` builds and mounts **every** child, so opening a
/// session with eight restored tabs constructs eight waveform canvases /
/// schematics before the user has looked at any of them, and any rebuild of
/// the pane walks all eight subtrees. This variant substitutes a zero-cost
/// placeholder for slots whose tab has never been activated, and keeps a slot
/// real once it has been — so switching away from a tab and back preserves its
/// state exactly as `IndexedStack` did.
///
/// The children list keeps its length and order (placeholders occupy the
/// unvisited slots), so [IndexedStack]'s sizing and index semantics are
/// unchanged and the caller's keys still line up with tabs.
class _LazyKeepAliveStack extends StatefulWidget {
  const _LazyKeepAliveStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_LazyKeepAliveStack> createState() => _LazyKeepAliveStackState();
}

class _LazyKeepAliveStackState extends State<_LazyKeepAliveStack> {
  /// Keys of the tabs that have been activated at least once. Keyed rather
  /// than indexed so a reorder, an insertion or a close cannot make one tab
  /// inherit another's "already built" status.
  final Set<Key> _realized = <Key>{};

  @override
  void initState() {
    super.initState();
    _realizeCurrent();
  }

  @override
  void didUpdateWidget(_LazyKeepAliveStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Drop keys of tabs that have gone away, so a long session that opens and
    // closes many tabs doesn't accumulate their keys forever.
    final present = {
      for (final c in widget.children)
        if (c.key != null) c.key!,
    };
    _realized.retainWhere(present.contains);
    _realizeCurrent();
  }

  void _realizeCurrent() {
    final children = widget.children;
    if (children.isEmpty) return;
    final i = widget.index.clamp(0, children.length - 1);
    final key = children[i].key;
    if (key != null) _realized.add(key);
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    return IndexedStack(
      index: widget.index,
      children: <Widget>[
        for (final child in children)
          // A null key can't be tracked, so fall back to eager mounting
          // rather than silently never building the child. PaneHost always
          // supplies one; this only guards a future caller that doesn't.
          if (child.key == null || _realized.contains(child.key))
            child
          else
            SizedBox.shrink(key: child.key),
      ],
    );
  }
}
