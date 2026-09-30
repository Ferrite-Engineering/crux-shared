// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_theme/crux_theme.dart' show CruxChromeColors;
import 'package:crux_workspace/src/multi_window.dart';
import 'package:crux_workspace/src/pane_id.dart';
import 'package:crux_workspace/src/tab_id.dart';
import 'package:crux_workspace/src/widgets/viewer_tab_bar_strings.dart';
import 'package:crux_workspace/src/workspace.dart';
import 'package:crux_workspace/src/workspace_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identity of the per-tab payload required to drag a tab between panes
/// without forcing the host product to materialize the whole tab.
class _TabDragPayload {
  const _TabDragPayload({required this.tabId, required this.sourcePane});

  final TabId tabId;
  final PaneId sourcePane;
}

/// Standard built-in tab context-menu actions.
///
/// Products extend the menu by supplying additional items via
/// [ViewerTabBar.contextMenuItems]; those items use whatever value type the
/// product chooses (typically an enum or sentinel object).
enum TabContextAction {
  /// Close just this tab.
  closeTab,

  /// Close every other tab in the host pane.
  closeOtherTabs,

  /// Close tabs that come after this one in the host pane.
  closeTabsToTheRight,

  /// Detach this tab into its own window. Gated by [kMultiWindowAvailable].
  moveToNewWindow,
}

/// Builder for additional product-specific context-menu items rendered below
/// the built-in [TabContextAction] block.
typedef TabContextMenuItemsBuilder<P> =
    List<PopupMenuEntry<Object>> Function(WorkspaceTab<P> tab);

/// Builder for product-specific trailing affordances rendered after the
/// trailing "+" new-tab button. The host product decides what (if anything) to
/// render for the given [paneId] — e.g. a per-pane diagnostics button or a
/// split-pane button — and applies its own visibility gating. Return a
/// zero-size widget (`SizedBox.shrink()`) to render nothing.
///
/// Optional and `null` by default so products that don't need extra trailing
/// actions are unaffected.
typedef PaneTrailingActionsBuilder =
    Widget Function(BuildContext context, PaneId paneId);

/// Builder for the hover/long-press tooltip shown over a tab chip's label.
/// Receives the tab and returns the tooltip message — products that want to
/// surface the full file path (rather than just the display name) supply one.
/// Optional and `null` by default; when null the chip's display label is used.
typedef TabTooltipBuilder<P> = String Function(WorkspaceTab<P> tab);

/// Builder that fully composes a tab chip's context menu, replacing the
/// built-in [TabContextAction] block. Each returned [PopupMenuEntry] carries
/// its own `onTap` (the bar shows the menu and ignores the result), so the
/// host has total control over item set and order — e.g. to render a leading
/// full-path header, a platform-specific "Reveal" item, and the standard
/// close actions in a product-specific order. Optional and `null` by default;
/// when null the bar renders its built-in menu (plus any
/// [ViewerTabBar.contextMenuItems]).
typedef TabContextMenuBuilder<P> =
    List<PopupMenuEntry<Object>> Function(
      BuildContext context,
      WorkspaceTab<P> tab,
    );

/// Optional sizing overrides for [ViewerTabBar]. Every field is nullable; a
/// `null` field keeps the widget's built-in default so existing callers are
/// unaffected. Products with a touch-aware metrics system (e.g. WaveCrux's
/// `MobileMetrics`) supply concrete values so the bar honours the platform's
/// minimum touch-target sizing.
@immutable
class ViewerTabBarSizing {
  /// Creates a sizing override. All fields default to `null` (use built-ins).
  const ViewerTabBarSizing({this.barHeight, this.iconSize});

  /// Fixed height for the whole bar. When non-null the bar is wrapped in a
  /// `SizedBox(height: barHeight)`; when null the bar sizes to its content.
  final double? barHeight;

  /// Icon size for the close / new-tab / scroll-chevron buttons. When null the
  /// widget's built-in sizes apply.
  final double? iconSize;
}

/// Horizontal tab bar that filters the workspace's tabs by [paneId] and
/// renders one chip per tab, plus an optional trailing "+" new-tab button.
///
/// The widget is generic over the per-tab payload type `P`; products
/// instantiate `ViewerTabBar<MyPayload>` and hand in their workspace
/// provider plus an optional [defaultPayloadBuilder] that supplies the
/// payload for "+"-button-opened tabs (when null the "+" button hides).
///
/// Interactions:
/// * Tap a chip → `setActiveTab`.
/// * Tap a chip's × → `closeTab` (no confirmation; workspace auto-saves).
/// * Right-click on desktop / long-press on touch → context menu.
/// * Drag a chip → reorder within the same pane (drop on another chip, which
///   takes that tab's place, or on an insertion slot between chips) or move
///   across panes (drop on the other pane's bar). In the default handle mode
///   the drag starts from the chip's leading handle; with
///   [useDragHandle] false the whole chip is the drag source.
///
/// Colours follow the active theme's `tabBar.*` chrome tokens, which
/// `applyChromeTokens` resolves into [CruxChromeColors]: `tabBar.background`
/// fills the strip (transparent over its host when unset),
/// `tabBar.selected` fills the active tab (`surfaceContainerHighest` when
/// unset), and `tabBar.label` colours every tab title
/// (`TextTheme.bodyMedium`'s colour when unset).
class ViewerTabBar<P> extends ConsumerWidget {
  /// Creates a viewer tab bar.
  const ViewerTabBar({
    required this.paneId,
    required this.provider,
    this.strings = const ViewerTabBarStringsEn(),
    this.defaultPayloadBuilder,
    this.contextMenuItems,
    this.trailingActionsBuilder,
    this.tabTooltipBuilder,
    this.tabFilePath,
    this.onRevealTab,
    this.contextMenuBuilder,
    this.useDragHandle = true,
    this.sizing = const ViewerTabBarSizing(),
    this.leadingInset = 0,
    this.autoHideScrollChevrons = false,
    this.isActivePane = false,
    super.key,
  });

  /// Pane whose tabs this bar renders.
  final PaneId paneId;

  /// Workspace provider for the host product.
  final AsyncNotifierProvider<WorkspaceNotifier<P>, Workspace<P>> provider;

  /// Localized strings used by the bar and its menus.
  final ViewerTabBarStrings strings;

  /// Factory for the payload of a brand-new tab opened via the "+" button.
  /// When null the "+" button hides — products that don't support empty
  /// tabs simply omit this argument.
  final P Function()? defaultPayloadBuilder;

  /// Optional builder for product-specific context-menu items rendered
  /// below the built-in [TabContextAction] block.
  final TabContextMenuItemsBuilder<P>? contextMenuItems;

  /// Optional builder for product-specific trailing affordances rendered
  /// after the trailing "+" new-tab button (e.g. a per-pane diagnostics or
  /// split-pane button). Null (the default) renders nothing extra, so
  /// products that don't need it are unaffected.
  final PaneTrailingActionsBuilder? trailingActionsBuilder;

  /// Optional builder for the per-chip label tooltip. When null (the default)
  /// the chip's display label is used as its own tooltip.
  final TabTooltipBuilder<P>? tabTooltipBuilder;

  /// Resolves a tab's backing file path, or null for pathless tabs.
  ///
  /// When supplied it powers three built-in behaviors (WaveCrux-canonical,
  /// adopted suite-wide): the default hover
  /// tooltip shows the full path, the default context menu opens with a
  /// non-interactive monospace path header, and — when [onRevealTab] is also
  /// supplied — a "Reveal in Finder / Explorer / Files" item appears.
  final String? Function(WorkspaceTab<P> tab)? tabFilePath;

  /// Reveals a tab's file in the platform file manager (hosts typically wire
  /// `crux_io`'s `revealInFileManager`; omit on web). Item label comes from
  /// `ViewerTabBarStrings.revealTabMenuItem`.
  final void Function(String filePath)? onRevealTab;

  /// Optional builder that fully replaces a chip's context menu. When null
  /// (the default) the bar renders its built-in [TabContextAction] block plus
  /// any [contextMenuItems].
  final TabContextMenuBuilder<P>? contextMenuBuilder;

  /// Whether each chip uses an explicit leading drag handle (the default) to
  /// initiate reorder, or — when false — makes the whole chip an immediate
  /// [Draggable] with no visible handle icon (matching a browser-style tab
  /// strip). When false the bar also renders insertion drop slots between and
  /// around the chips. Defaults to `true` so existing callers keep the
  /// drag-handle affordance.
  ///
  /// The two modes differ only in what *starts* a drag. What accepts a drop is
  /// the same in both: a chip (the dragged tab takes its place) and, in
  /// whole-chip mode, the insertion slots.
  final bool useDragHandle;

  /// Optional sizing overrides (bar height, icon size). Defaults to the
  /// built-in sizes when fields are null.
  final ViewerTabBarSizing sizing;

  /// Leading inset (in logical pixels) applied before the first tab chip.
  /// Products with a frameless window whose left resize-edge would otherwise
  /// swallow the leading drop slot pass a small positive value here; defaults
  /// to 0 (no inset).
  final double leadingInset;

  /// When true, each scroll chevron is shown only when the tab strip can
  /// actually scroll in that direction (matching a "hide when not needed"
  /// affordance). When false (the default) both chevrons render
  /// unconditionally, preserving the original behaviour for existing callers.
  final bool autoHideScrollChevrons;

  /// Whether the hosting pane is the workspace's active pane. The bar
  /// renders a subtle accent so the user can tell which pane will receive
  /// the next action.
  final bool isActivePane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncWs = ref.watch(provider);
    return asyncWs.when(
      data: (ws) => _ViewerTabBarBody<P>(
        workspace: ws,
        paneId: paneId,
        notifier: ref.read(provider.notifier),
        strings: strings,
        defaultPayloadBuilder: defaultPayloadBuilder,
        contextMenuItems: contextMenuItems,
        trailingActionsBuilder: trailingActionsBuilder,
        tabTooltipBuilder: tabTooltipBuilder,
        tabFilePath: tabFilePath,
        onRevealTab: onRevealTab,
        contextMenuBuilder: contextMenuBuilder,
        useDragHandle: useDragHandle,
        sizing: sizing,
        leadingInset: leadingInset,
        autoHideScrollChevrons: autoHideScrollChevrons,
        isActivePane: isActivePane,
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _ViewerTabBarBody<P> extends StatefulWidget {
  const _ViewerTabBarBody({
    required this.workspace,
    required this.paneId,
    required this.notifier,
    required this.strings,
    required this.defaultPayloadBuilder,
    required this.contextMenuItems,
    required this.trailingActionsBuilder,
    required this.tabTooltipBuilder,
    required this.tabFilePath,
    required this.onRevealTab,
    required this.contextMenuBuilder,
    required this.useDragHandle,
    required this.sizing,
    required this.leadingInset,
    required this.autoHideScrollChevrons,
    required this.isActivePane,
  });

  final Workspace<P> workspace;
  final PaneId paneId;
  final WorkspaceNotifier<P> notifier;
  final ViewerTabBarStrings strings;
  final P Function()? defaultPayloadBuilder;
  final TabContextMenuItemsBuilder<P>? contextMenuItems;
  final PaneTrailingActionsBuilder? trailingActionsBuilder;
  final TabTooltipBuilder<P>? tabTooltipBuilder;

  final String? Function(WorkspaceTab<P> tab)? tabFilePath;

  final void Function(String filePath)? onRevealTab;
  final TabContextMenuBuilder<P>? contextMenuBuilder;
  final bool useDragHandle;
  final ViewerTabBarSizing sizing;
  final double leadingInset;
  final bool autoHideScrollChevrons;
  final bool isActivePane;

  @override
  State<_ViewerTabBarBody<P>> createState() => _ViewerTabBarBodyState<P>();
}

class _ViewerTabBarBodyState<P> extends State<_ViewerTabBarBody<P>> {
  final ScrollController _scroll = ScrollController();

  // Only meaningful when [widget.autoHideScrollChevrons] is true; otherwise the
  // chevrons render unconditionally and these flags are ignored.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoHideScrollChevrons) _attachScrollListener();
  }

  @override
  void didUpdateWidget(_ViewerTabBarBody<P> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // autoHideScrollChevrons can flip on a live element (a product gating the
    // affordance on window width or device class). Without this, flipping it
    // false -> true left the listener unattached and both chevrons hidden
    // forever, because initState had already run.
    if (widget.autoHideScrollChevrons != oldWidget.autoHideScrollChevrons) {
      if (widget.autoHideScrollChevrons) {
        _attachScrollListener();
      } else {
        _scroll.removeListener(_updateScrollFlags);
      }
      return;
    }
    if (!widget.autoHideScrollChevrons) return;
    // Adding or removing a tab changes maxScrollExtent without producing a
    // scroll notification, so the listener alone would leave the chevrons
    // stale. Re-probe on a tab-set change only — once per workspace mutation,
    // not once per frame like the post-frame callback this replaced.
    if (!identical(widget.workspace, oldWidget.workspace) &&
        widget.workspace.tabsForPane(widget.paneId).length !=
            oldWidget.workspace.tabsForPane(oldWidget.paneId).length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollFlags());
    }
  }

  void _attachScrollListener() {
    _scroll.addListener(_updateScrollFlags);
    // One post-frame probe to seed the flags: the scroll position does not
    // exist until the viewport has been laid out once. This is the ONLY
    // place a post-frame callback is scheduled — build() must never schedule
    // one, since the enclosing DragTarget rebuilds every frame of a tab drag.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollFlags());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateScrollFlags)
      ..dispose();
    super.dispose();
  }

  void _updateScrollFlags() {
    // Reached from a post-frame callback and from scroll notifications, both
    // of which can outlive the element (a pane closing mid-scroll). setState
    // after unmount throws.
    if (!mounted) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final left = pos.pixels > pos.minScrollExtent;
    final right = pos.pixels < pos.maxScrollExtent;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  WorkspacePane get _pane =>
      widget.workspace.panes.firstWhere((p) => p.id == widget.paneId);

  List<WorkspaceTab<P>> get _tabs =>
      widget.workspace.tabsForPane(widget.paneId);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeTabId = _pane.activeTabId;
    final tabs = _tabs;

    final accent = widget.isActivePane
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    final iconSize = widget.sizing.iconSize;
    final showLeftChevron = !widget.autoHideScrollChevrons || _canScrollLeft;
    final showRightChevron = !widget.autoHideScrollChevrons || _canScrollRight;

    return DragTarget<_TabDragPayload>(
      onWillAcceptWithDetails: (details) =>
          details.data.sourcePane != widget.paneId,
      onAcceptWithDetails: (details) {
        unawaited(
          widget.notifier.moveTabToPane(details.data.tabId, widget.paneId),
        );
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        Widget bar = DecoratedBox(
          decoration: BoxDecoration(
            color: CruxChromeColors.of(context)?.tabBarBackground,
            border: Border(
              bottom: BorderSide(
                color: highlighted ? colorScheme.primary : accent,
                width: highlighted ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              if (widget.leadingInset > 0) SizedBox(width: widget.leadingInset),
              if (showLeftChevron)
                _Chevron(
                  icon: Icons.chevron_left,
                  scroll: _scroll,
                  direction: -1,
                  iconSize: iconSize,
                  tooltip: widget.strings.scrollTabsLeftTooltip,
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildRowChildren(tabs, activeTabId, iconSize),
                  ),
                ),
              ),
              if (showRightChevron)
                _Chevron(
                  icon: Icons.chevron_right,
                  scroll: _scroll,
                  direction: 1,
                  iconSize: iconSize,
                  tooltip: widget.strings.scrollTabsRightTooltip,
                ),
              if (widget.defaultPayloadBuilder != null)
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize: iconSize,
                  tooltip: widget.strings.newTabTooltip,
                  onPressed: _onNewTab,
                ),
              if (widget.trailingActionsBuilder != null)
                widget.trailingActionsBuilder!(context, widget.paneId),
            ],
          ),
        );
        if (widget.sizing.barHeight != null) {
          bar = SizedBox(height: widget.sizing.barHeight, child: bar);
        }
        return Semantics(
          label: widget.isActivePane
              ? widget.strings.activePaneAccessibilityLabel
              : null,
          container: true,
          child: bar,
        );
      },
    );
  }

  Future<void> _onNewTab() async {
    final builder = widget.defaultPayloadBuilder;
    if (builder == null) return;
    await widget.notifier.openTab(
      displayName: widget.strings.newTabDefaultDisplayName,
      payload: builder(),
      paneId: widget.paneId,
    );
  }

  /// Builds the ordered chip row. In the default handle-drag mode this is just
  /// the chips (each chip is its own drop target). In whole-chip drag mode it
  /// interleaves keyed insertion drop slots before/after every chip — the
  /// reorder mechanism a browser-style tab strip uses — and keys each chip by
  /// its tab id so the slot-walk and chip lookups are addressable.
  List<Widget> _buildRowChildren(
    List<WorkspaceTab<P>> tabs,
    TabId? activeTabId,
    double? iconSize,
  ) {
    _TabChip<P> chip(int i) => _TabChip<P>(
      key: widget.useDragHandle ? null : ValueKey(tabs[i].id),
      tab: tabs[i],
      index: i,
      active: tabs[i].id == activeTabId,
      notifier: widget.notifier,
      paneId: widget.paneId,
      strings: widget.strings,
      contextMenuItems: widget.contextMenuItems,
      contextMenuBuilder: widget.contextMenuBuilder,
      tabTooltipBuilder: widget.tabTooltipBuilder,
      tabFilePath: widget.tabFilePath,
      onRevealTab: widget.onRevealTab,
      useDragHandle: widget.useDragHandle,
      allTabsInPane: tabs,
      iconSize: iconSize,
    );

    if (widget.useDragHandle) {
      return [for (var i = 0; i < tabs.length; i++) chip(i)];
    }
    return [
      for (var i = 0; i < tabs.length; i++) ...[
        _insertionSlot(i, tabs),
        chip(i),
      ],
      if (tabs.isNotEmpty) _insertionSlot(tabs.length, tabs),
    ];
  }

  /// Keyed insertion drop slot at pane-local [index] (whole-chip drag mode).
  /// Accepts a same-pane reorder to that position and a cross-pane move into
  /// this pane. The leading slot (`index == 0`) sits past any
  /// [ViewerTabBar.leadingInset] so "drop a tab before the first tab" is
  /// reachable under frameless chrome.
  Widget _insertionSlot(int index, List<WorkspaceTab<P>> tabs) {
    return DragTarget<_TabDragPayload>(
      key: ValueKey('tabInsertionSlot_${widget.paneId.value}_$index'),
      onWillAcceptWithDetails: (details) {
        if (details.data.sourcePane != widget.paneId) return true;
        final fromIndex = tabs.indexWhere((t) => t.id == details.data.tabId);
        if (fromIndex == -1) return false;
        return fromIndex != index && fromIndex + 1 != index;
      },
      onAcceptWithDetails: (details) {
        if (details.data.sourcePane != widget.paneId) {
          unawaited(
            widget.notifier.moveTabToPane(details.data.tabId, widget.paneId),
          );
        } else {
          unawaited(
            widget.notifier.reorderTabInPane(
              details.data.tabId,
              widget.paneId,
              index,
            ),
          );
        }
      },
      builder: (context, candidate, _) {
        final hovered = candidate.isNotEmpty;
        return SizedBox(
          width: 8,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: hovered ? 4 : 0,
              color: hovered
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
        );
      },
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.icon,
    required this.scroll,
    required this.direction,
    required this.tooltip,
    this.iconSize,
  });

  final IconData icon;
  final ScrollController scroll;
  final int direction;
  final double? iconSize;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      iconSize: iconSize ?? 18,
      // Without this the chevron has no accessible name at all — a screen
      // reader announces it as "button". It is on the primary navigation
      // surface of every product, so it is the highest-traffic control in
      // the suite.
      tooltip: tooltip,
      onPressed: _onTap,
    );
  }

  void _onTap() {
    if (!scroll.hasClients) return;
    final pos = scroll.position;
    final current = pos.pixels;
    if (direction < 0 && current <= pos.minScrollExtent) return;
    if (direction > 0 && current >= pos.maxScrollExtent) return;
    final delta = direction * 120.0;
    scroll.animateTo(
      (current + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
}

class _TabChip<P> extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.index,
    required this.active,
    required this.notifier,
    required this.paneId,
    required this.strings,
    required this.contextMenuItems,
    required this.contextMenuBuilder,
    required this.tabTooltipBuilder,
    required this.tabFilePath,
    required this.onRevealTab,
    required this.useDragHandle,
    required this.allTabsInPane,
    this.iconSize,
    super.key,
  });

  final WorkspaceTab<P> tab;
  final int index;
  final bool active;
  final WorkspaceNotifier<P> notifier;
  final PaneId paneId;
  final ViewerTabBarStrings strings;
  final TabContextMenuItemsBuilder<P>? contextMenuItems;
  final TabContextMenuBuilder<P>? contextMenuBuilder;
  final TabTooltipBuilder<P>? tabTooltipBuilder;

  final String? Function(WorkspaceTab<P> tab)? tabFilePath;

  final void Function(String filePath)? onRevealTab;
  final bool useDragHandle;
  final List<WorkspaceTab<P>> allTabsInPane;
  final double? iconSize;

  static const double _chipHeight = 36;
  static const double _maxLabelWidth = 180;

  @override
  Widget build(BuildContext context) {
    final displayLabel = tab.displayName.isEmpty
        ? strings.unnamedTabFallback
        : tab.displayName;
    final tooltipMessage =
        tabTooltipBuilder?.call(tab) ?? tabFilePath?.call(tab) ?? displayLabel;
    final dragPayload = _TabDragPayload(tabId: tab.id, sourcePane: paneId);

    // Whole-chip drag mode (browser-style): the entire chip is an immediate
    // Draggable with no handle icon, and — like handle mode — it is also its
    // own drop target.
    //
    // The insertion slots between chips stay, because they are the only way to
    // say "before the first" and "after the last". They cannot be the *only*
    // way: each is 8 logical pixels wide and draws nothing until a drag is
    // already over it, so a drop aimed at a tab — the gesture every browser
    // and editor accepts — landed on nothing and the tab did not move. Making
    // the chip a target is what a user is actually aiming at.
    //
    // Dropping on a chip means "take that tab's place", which reads correctly
    // in both directions without asking where inside the chip the pointer was:
    // [WorkspaceNotifier.reorderTabInPane] resolves the target's index before
    // removing the dragged tab, so a left-to-right drag lands after the target
    // and a right-to-left drag lands before it.
    if (!useDragHandle) {
      return SizedBox(
        height: _chipHeight,
        child: DragTarget<_TabDragPayload>(
          onWillAcceptWithDetails: (details) =>
              details.data.sourcePane == paneId && details.data.tabId != tab.id,
          onAcceptWithDetails: (details) {
            unawaited(
              notifier.reorderTabInPane(details.data.tabId, paneId, index),
            );
          },
          builder: (context, candidate, _) {
            final body = _buildChipBody(
              context,
              highlighted: candidate.isNotEmpty,
              displayLabel: displayLabel,
              tooltipMessage: tooltipMessage,
            );
            return Draggable<_TabDragPayload>(
              data: dragPayload,
              feedback: Material(
                color: Colors.transparent,
                child: _FeedbackChip(label: displayLabel),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: body),
              child: body,
            );
          },
        ),
      );
    }

    // Handle-drag mode (default): each chip is its own drop target and the
    // body carries an explicit leading drag handle.
    return SizedBox(
      height: _chipHeight,
      child: DragTarget<_TabDragPayload>(
        // Only accept reorders from the same pane; cross-pane drops bubble
        // to the outer DragTarget that owns the whole bar.
        onWillAcceptWithDetails: (details) =>
            details.data.sourcePane == paneId && details.data.tabId != tab.id,
        onAcceptWithDetails: (details) {
          // Translate the pane-local [index] into the correct global tab-list
          // index so reorders land correctly in the second pane of a split.
          unawaited(
            notifier.reorderTabInPane(details.data.tabId, paneId, index),
          );
        },
        builder: (context, candidate, _) => _buildChipBody(
          context,
          highlighted: candidate.isNotEmpty,
          displayLabel: displayLabel,
          tooltipMessage: tooltipMessage,
        ),
      ),
    );
  }

  Widget _buildChipBody(
    BuildContext context, {
    required bool highlighted,
    required String displayLabel,
    required String tooltipMessage,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dragPayload = _TabDragPayload(tabId: tab.id, sourcePane: paneId);

    // One node for the chip: a button named after the tab, with its selected
    // state, and the full path as the description when it says more than the
    // name. The visible label and its tooltip are excluded so the name is not
    // announced twice; the close button stays a separate, named child.
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: displayLabel,
      tooltip: tooltipMessage == displayLabel ? null : tooltipMessage,
      child: _chipInk(
        context,
        theme: theme,
        colorScheme: colorScheme,
        highlighted: highlighted,
        displayLabel: displayLabel,
        tooltipMessage: tooltipMessage,
        dragPayload: dragPayload,
      ),
    );
  }

  Widget _chipInk(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme colorScheme,
    required bool highlighted,
    required String displayLabel,
    required String tooltipMessage,
    required _TabDragPayload dragPayload,
  }) {
    final chrome = CruxChromeColors.of(context);
    final labelColor = chrome?.tabBarLabel;
    return InkWell(
      onTap: () => notifier.setActiveTab(tab.id),
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      onLongPress: () => _showContextMenuAtCenter(context),
      child: Container(
        decoration: BoxDecoration(
          color: active
              ? chrome?.tabBarSelected ?? colorScheme.surfaceContainerHighest
              : highlighted
              ? colorScheme.primaryContainer
              : null,
          border: Border(
            bottom: BorderSide(
              color: active ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (useDragHandle)
              LongPressDraggable<_TabDragPayload>(
                data: dragPayload,
                feedback: Material(
                  color: Colors.transparent,
                  child: _FeedbackChip(label: displayLabel),
                ),
                childWhenDragging: const SizedBox(width: 24),
                child: Tooltip(
                  message: strings.reorderHandleTooltip,
                  triggerMode: TooltipTriggerMode.manual,
                  excludeFromSemantics: true,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_indicator, size: 16),
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxLabelWidth),
              child: Tooltip(
                message: tooltipMessage,
                triggerMode: TooltipTriggerMode.manual,
                excludeFromSemantics: true,
                child: ExcludeSemantics(
                  child: Text(
                    displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelColor == null
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: labelColor,
                          ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: iconSize ?? 14),
              visualDensity: VisualDensity.compact,
              tooltip: strings.closeTabTooltipFor(displayLabel),
              onPressed: () => notifier.closeTab(tab.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position2 = RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    );
    await _showMenuAt(context, position2);
  }

  Future<void> _showContextMenuAtCenter(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(box.size.center(Offset.zero));
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy,
      overlay.size.width - origin.dx,
      overlay.size.height - origin.dy,
    );
    await _showMenuAt(context, position);
  }

  Future<void> _showMenuAt(
    BuildContext context,
    RelativeRect position,
  ) async {
    // When the host fully composes the menu, render those entries verbatim
    // (each carries its own onTap) and skip the built-in action block.
    final fullMenu = contextMenuBuilder;
    if (fullMenu != null) {
      await showMenu<Object>(
        context: context,
        position: position,
        items: fullMenu(context, tab),
      );
      return;
    }
    final filePath = tabFilePath?.call(tab);
    final reveal = onRevealTab;
    final colorScheme = Theme.of(context).colorScheme;
    final items = <PopupMenuEntry<Object>>[
      // Non-interactive monospace full-path header (WaveCrux-canonical,
      // promoted suite-wide).
      if (filePath != null) ...[
        PopupMenuItem<Object>(
          enabled: false,
          height: 36,
          child: Text(
            filePath,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const PopupMenuDivider(),
      ],
      if (filePath != null && reveal != null)
        PopupMenuItem<Object>(
          onTap: () => reveal(filePath),
          child: Text(strings.revealTabMenuItem),
        ),
      if (filePath != null && reveal != null) const PopupMenuDivider(),
      PopupMenuItem<Object>(
        value: TabContextAction.closeTab,
        child: Text(strings.closeTabMenuItem),
      ),
      PopupMenuItem<Object>(
        value: TabContextAction.closeOtherTabs,
        enabled: allTabsInPane.length > 1,
        child: Text(strings.closeOtherTabsMenuItem),
      ),
      PopupMenuItem<Object>(
        value: TabContextAction.closeTabsToTheRight,
        enabled: index < allTabsInPane.length - 1,
        child: Text(strings.closeTabsToTheRightMenuItem),
      ),
      PopupMenuItem<Object>(
        value: TabContextAction.moveToNewWindow,
        enabled: kMultiWindowAvailable,
        child: Tooltip(
          message: kMultiWindowAvailable
              ? ''
              : strings.multiWindowUnavailableTooltip,
          triggerMode: TooltipTriggerMode.manual,
          child: Text(strings.moveToNewWindowMenuItem),
        ),
      ),
      if (contextMenuItems != null) ...[
        const PopupMenuDivider(),
        ...contextMenuItems!.call(tab),
      ],
    ];
    final selected = await showMenu<Object>(
      context: context,
      position: position,
      items: items,
    );
    if (selected == null) return;
    if (selected is TabContextAction) {
      switch (selected) {
        case TabContextAction.closeTab:
          await notifier.closeTab(tab.id);
        case TabContextAction.closeOtherTabs:
          for (final t in [...allTabsInPane]) {
            if (t.id != tab.id) await notifier.closeTab(t.id);
          }
        case TabContextAction.closeTabsToTheRight:
          for (final t in allTabsInPane.skip(index + 1).toList()) {
            await notifier.closeTab(t.id);
          }
        case TabContextAction.moveToNewWindow:
          // Disabled in this build; products override via proOverrides when
          // kMultiWindowAvailable flips to true.
          break;
      }
    }
  }
}

class _FeedbackChip extends StatelessWidget {
  const _FeedbackChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Text(label, style: theme.textTheme.bodyMedium),
      ),
    );
  }
}
