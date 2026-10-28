// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_dock/src/dock_entry.dart';
import 'package:flutter/material.dart';

/// Height of the dock's tab strip / header row, in logical pixels.
const double kCruxDockStripHeight = 32;

/// Icon size inside dock tabs and the action cluster.
const double kCruxDockIconSize = 16;

/// Strip width reserved for the tab region before the action cluster may
/// take more: the active tab never disappears entirely, so tabs stay
/// switchable however narrow the dock is dragged.
const double _kTabSliverReserve = 72;

/// The least width the action cluster keeps when the reserve would squeeze
/// it below usability (roughly two 28 dp buttons) — at that point the
/// standard actions (collapse is the escape hatch) outrank tab labels.
const double _kClusterMinVisible = 56;

/// The layout floor for the dock's CONTENT region. When the region is
/// squeezed below these (the pane open/close animation sweeps the size
/// through zero, and resting pane minimums can sit below a panel's natural
/// minimum), the content is laid out AT the floor and clipped instead of
/// being squeezed — panels never see impossible constraints, so no panel
/// can transiently RenderFlex-overflow during an open/close in any app.
/// This is the VSCode behavior: a too-small panel crops, it doesn't crush.
const double _kContentFloorWidth = 150;
const double _kContentFloorHeight = 120;

/// Width of the draggable divider between the two panes of a split dock.
const double _kSplitDividerWidth = 6;

/// The narrowest a pane of a split dock can be dragged, as a fraction of the
/// dock's width.
const double _kSplitMinFraction = 0.2;

/// The dock width below which a split dock shows its active tab alone, as
/// plain tabs: two panes narrower than this half each are not readable.
const double _kDefaultSplitMinWidth = 640;

/// Which window edge a dock collapses toward — picks the hide glyph
/// (a double-arrow pointing INTO that edge, the JetBrains-familiar
/// "hide tool window" affordance, replacing the ambiguous single
/// down-chevron every region used to share).
enum CruxDockCollapseDirection {
  /// Bottom region — hides downward.
  down(Icons.keyboard_double_arrow_down),

  /// Left region — hides leftward.
  left(Icons.keyboard_double_arrow_left),

  /// Right region — hides rightward.
  right(Icons.keyboard_double_arrow_right);

  const CruxDockCollapseDirection(this.icon);

  /// The hide glyph for this direction.
  final IconData icon;
}

/// Pop-out configuration for a [CruxDock]'s action cluster.
///
/// The affordance exists in every dock so the suite's multi-window story is a
/// property of the shared chrome, not a per-app retrofit. Until Flutter
/// multi-window reaches stable (`crux_workspace`'s `kMultiWindowAvailable`),
/// hosts pass `enabled: false` and the button renders disabled with
/// [tooltip] explaining why — the same rendered-but-disabled contract as the
/// "Move to New Window" tab context menu item.
@immutable
class CruxDockPopOut {
  /// Creates the pop-out configuration.
  const CruxDockPopOut({
    required this.enabled,
    required this.tooltip,
    this.onPopOut,
  });

  /// Whether pop-out is currently available.
  final bool enabled;

  /// Tooltip for the button. When disabled, hosts pass the localized
  /// "available when multi-window reaches stable" explanation.
  final String tooltip;

  /// Detaches the tab with the given id into its own window. Receives the
  /// active entry's id. Ignored while [enabled] is false.
  final ValueChanged<String>? onPopOut;
}

/// Payload of a dock-tab drag: which entry left which dock. Hosts receive it
/// via [CruxDock.onTabMovedIn] and respond by re-homing the feature's tab
/// (usually a placement-override map keyed by entry id).
@immutable
class CruxDockDragData {
  /// Creates the drag payload.
  const CruxDockDragData({
    required this.dockId,
    required this.entryId,
    required this.icon,
    required this.label,
  });

  /// The source dock's [CruxDock.dockId].
  final String dockId;

  /// The dragged entry's id.
  final String entryId;

  /// Icon for the drag feedback chip.
  final IconData icon;

  /// Label for the drag feedback chip.
  final String label;
}

/// The cross-suite tabbed **dock**: a VSCode-style region container mounted
/// inside a `CruxIdeLayout` region.
///
/// Replaces the per-app "priority chain" (first-true-visibility-flag-wins)
/// that used to decide a region's content. Every surface that can occupy the
/// region is a [CruxDockEntry]; the strip shows what is available, the user
/// picks, and nothing is hidden behind an ordering only the source code knows.
///
/// ## Presentation
///
/// ```text
/// [ tab | tab | tab ...  (scrolls) ]  [maximize] [pop-out] [collapse]
/// ─────────────────────────────────────────────────────────────────────
/// [ active entry's content                                            ]
/// ```
///
/// - **Auto-hiding strip.** With exactly one pinned entry the strip renders as
///   a plain panel *header* — title + action cluster, no tab affordance. The
///   moment a second entry appears (an on-demand analysis activating), the
///   header becomes a tab strip. One widget, three regions, and the "left
///   panel rail" question answers itself: a single-surface region reads as a
///   titled panel, not a one-tab tab bar.
/// - **Badges.** [CruxDockEntry.badgeCount] renders a `Badge.count`, zero
///   suppressed.
/// - **Close.** Closable entries render an `×` that fires
///   [CruxDockEntry.onClose] — deactivating the feature, not just hiding UI.
///
/// ## Behavior contract (VSCode semantics)
///
/// - [activeId] not matching any entry falls back to the first entry — the
///   dock renders the fallback without writing anything back, so a closed
///   on-demand tab needs no state cleanup from the host.
/// - **Auto-reveal:** when a *new closable* entry appears in [entries] (the
///   user ran an analysis), the dock schedules [onAutoReveal] with its id
///   post-frame. The host responds by activating the tab and un-collapsing
///   the region. Never fired for the initial build, and never fired
///   synchronously (host notifiers must not be written mid-build).
/// - **Collapse** ([onCollapse]) hides the whole region via the host's
///   `CruxIdeLayout` visibility — a collapsed dock is *gone*, exactly like
///   VSCode's panel, and reopening any tab restores the full strip.
/// - **Maximize** ([onMaximize]) is a host-side size toggle (bottom dock
///   only); [isMaximized] flips the glyph between expand and restore.
/// - **Split** ([onSplitChanged]): the action cluster's split button keeps
///   the active tab open in a second pane on the right ([splitId]) and
///   activates another tab on the left, with a draggable divider between
///   them. Both tabs read as selected in the strip. Choosing the right
///   pane's tab swaps the two; the button again closes the split. Below
///   [splitMinWidth] the dock shows its active tab alone, as plain tabs, and
///   the split comes back when the dock widens.
class CruxDock extends StatefulWidget {
  /// Creates a dock. [entries] must be non-empty — a region with nothing to
  /// show should not be visible at all.
  const CruxDock({
    required this.entries,
    required this.onSelect,
    this.activeId,
    this.onCollapse,
    this.collapseTooltip,
    this.collapseDirection = CruxDockCollapseDirection.down,
    this.onMaximize,
    this.isMaximized = false,
    this.maximizeTooltip,
    this.restoreTooltip,
    this.popOut,
    this.onAutoReveal,
    this.dockId,
    this.onTabMovedIn,
    this.semanticsLabel,
    this.splitId,
    this.onSplitChanged,
    this.splitTooltip,
    this.unsplitTooltip,
    this.splitMinWidth = _kDefaultSplitMinWidth,
    super.key,
  }) : assert(entries.length > 0, 'A CruxDock needs at least one entry');

  /// The tabs, in strip order. Host-assembled each build; membership is
  /// presence (see [CruxDockEntry]).
  final List<CruxDockEntry> entries;

  /// The persisted active-tab id. Falls back to the first entry when null or
  /// no longer present.
  final String? activeId;

  /// Called when the user picks a tab. The host persists it as the region's
  /// active-tab id.
  final ValueChanged<String> onSelect;

  /// Hides the region (VSCode panel-close). Null omits the button.
  final VoidCallback? onCollapse;

  /// Localized tooltip for the collapse button.
  final String? collapseTooltip;

  /// Which edge this dock hides toward — selects the hide glyph.
  final CruxDockCollapseDirection collapseDirection;

  /// Toggles the region's maximized size. Null omits the button.
  final VoidCallback? onMaximize;

  /// Whether the region is currently maximized — flips the maximize glyph to
  /// a restore glyph.
  final bool isMaximized;

  /// Localized tooltip for the maximize button while un-maximized.
  final String? maximizeTooltip;

  /// Localized tooltip for the maximize button while maximized.
  final String? restoreTooltip;

  /// Pop-out affordance configuration. Null omits the button entirely.
  final CruxDockPopOut? popOut;

  /// Fired post-frame with the id of a newly appeared closable entry, so the
  /// host can activate it and un-collapse the region. See the class docs.
  final ValueChanged<String>? onAutoReveal;

  /// Stable identity of this dock within the window ('bottom', 'right',
  /// 'left'). Required for drag-between-docks: it tags outgoing drags and
  /// rejects drops onto the dock they came from. Null disables dragging.
  final String? dockId;

  /// Accepts a tab dragged in from another dock: `(entryId, fromDockId)`.
  /// The host re-homes the feature (and typically reveals it here). Null
  /// makes this dock reject incoming drops.
  final void Function(String entryId, String fromDockId)? onTabMovedIn;

  /// Accessibility label announced for the dock region.
  final String? semanticsLabel;

  /// The tab shown in the right pane of a split dock, beside the active
  /// tab. Ignored while null, absent from [entries], or the active tab.
  final String? splitId;

  /// Called with the tab to keep open on the right when the user splits the
  /// dock, and with null when they close the split. The host persists it as
  /// [splitId]. Null omits the split button.
  final ValueChanged<String?>? onSplitChanged;

  /// Localized tooltip for the split button while the dock is not split.
  final String? splitTooltip;

  /// Localized tooltip for the split button while the dock is split.
  final String? unsplitTooltip;

  /// The dock width below which a split shows the active tab alone; 640 by
  /// default.
  final double splitMinWidth;

  @override
  State<CruxDock> createState() => _CruxDockState();
}

class _CruxDockState extends State<CruxDock> {
  late Set<String> _knownIds;

  @override
  void initState() {
    super.initState();
    // The initial entry set is baseline, not news — restoring a session with
    // an FSM tab present must not steal the user's persisted active tab.
    _knownIds = {for (final e in widget.entries) e.id};
  }

  @override
  void didUpdateWidget(CruxDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = {for (final e in widget.entries) e.id};
    if (widget.onAutoReveal != null) {
      // A newly appearing *closable* entry means the user just activated a
      // feature — reveal it. Pinned entries appearing (a host adding a slot)
      // are chrome changes, not user intent, and stay silent. When several
      // appear in one frame the last one wins, matching "the most recent
      // thing you asked for is what you see".
      String? revealed;
      for (final entry in widget.entries) {
        if (entry.closable && !_knownIds.contains(entry.id)) {
          revealed = entry.id;
        }
      }
      if (revealed != null) {
        final id = revealed;
        // Post-frame: the entry list changes during a host provider rebuild,
        // and responding by writing the host's dock-state notifier
        // synchronously would be a write-during-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onAutoReveal!(id);
        });
      }
    }
    _knownIds = current;
  }

  CruxDockEntry get _active => widget.entries.firstWhere(
    (e) => e.id == widget.activeId,
    orElse: () => widget.entries.first,
  );

  /// The right pane's entry, or null when the dock is not split.
  CruxDockEntry? get _split {
    final id = widget.splitId;
    if (id == null || widget.onSplitChanged == null) return null;
    final active = _active;
    for (final e in widget.entries) {
      if (e.id == id && e.id != active.id) return e;
    }
    return null;
  }

  /// Picks [id]. Picking the right pane's tab swaps the two panes, so both
  /// stay on screen.
  void _select(String id) {
    final split = _split;
    if (split != null && split.id == id) {
      widget.onSplitChanged!(_active.id);
    }
    widget.onSelect(id);
  }

  /// The split button: keeps the active tab on the right and activates the
  /// next tab on the left, or closes the split.
  void _toggleSplit() {
    if (_split != null) {
      widget.onSplitChanged!(null);
      return;
    }
    final active = _active;
    final index = widget.entries.indexOf(active);
    final others = [
      ...widget.entries.skip(index + 1),
      ...widget.entries.take(index),
    ];
    if (others.isEmpty) return;
    widget.onSplitChanged!(active.id);
    widget.onSelect(others.first.id);
  }

  /// [entry]'s content, laid out at the floor size when squeezed below it.
  Widget _pane(CruxDockEntry entry) => KeyedSubtree(
    // Keyed so switching tabs tears down the outgoing panel rather than
    // reusing its element for unrelated content.
    key: ValueKey('cruxDockContent-${entry.id}'),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final squeezedW = constraints.maxWidth < _kContentFloorWidth;
        final squeezedH = constraints.maxHeight < _kContentFloorHeight;
        if (!squeezedW && !squeezedH) {
          return entry.builder(context);
        }
        // Below the floor: lay the panel out at the floor size and crop
        // from the top-left, so mid-animation frames (and ultra-small
        // resting sizes) can never hand a panel constraints it cannot
        // satisfy.
        final width = squeezedW ? _kContentFloorWidth : constraints.maxWidth;
        final height = squeezedH ? _kContentFloorHeight : constraints.maxHeight;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: entry.builder(context),
          ),
        );
      },
    ),
  );

  /// Wraps a movable tab in a [Draggable] carrying [CruxDockDragData].
  /// Non-movable tabs (or a dock with no [CruxDock.dockId]) render as-is.
  Widget _maybeDraggable(CruxDockEntry entry, Widget tab) {
    final dockId = widget.dockId;
    if (dockId == null || !entry.movable) return tab;
    return Draggable<CruxDockDragData>(
      data: CruxDockDragData(
        dockId: dockId,
        entryId: entry.id,
        icon: entry.icon,
        label: entry.label,
      ),
      feedback: _DragFeedbackChip(icon: entry.icon, label: entry.label),
      childWhenDragging: Opacity(opacity: 0.35, child: tab),
      child: tab,
    );
  }

  /// Whether an incoming drag can drop here: from another dock, with a
  /// host willing to re-home it.
  bool _acceptsDrop(CruxDockDragData? data) =>
      data != null &&
      widget.onTabMovedIn != null &&
      widget.dockId != null &&
      data.dockId != widget.dockId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _active;
    final split = _split;
    // Auto-hide: one pinned entry reads as a titled panel, not a one-tab bar.
    final headerMode =
        widget.entries.length == 1 && !widget.entries.single.closable;

    return CruxRegionHintHost(
      // An empty panel inside describes the dock; the name stays the label.
      builder: (context, hint, child) => cruxRegionHintSemantics(
        label: widget.semanticsLabel,
        hint: hint,
        child: child,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kCruxDockStripHeight,
            child: DragTarget<CruxDockDragData>(
              onWillAcceptWithDetails: (details) => _acceptsDrop(details.data),
              onAcceptWithDetails: (details) => widget.onTabMovedIn!(
                details.data.entryId,
                details.data.dockId,
              ),
              builder: (context, candidates, _) => DecoratedBox(
                decoration: BoxDecoration(
                  // Hover cue while a compatible tab is over the strip.
                  color: candidates.isNotEmpty
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The action cluster takes its natural width — but capped,
                    // so a dock dragged narrower than the cluster can never
                    // overflow: past the cap the cluster scrolls, matching the
                    // tab strip's own overflow strategy. `reverse: true`
                    // anchors the right edge, so shrinking sheds the ACTIVE
                    // tab's view actions (leading) first while the standard
                    // cluster (maximize / collapse — the escape hatches) stays
                    // visible and tappable.
                    final clusterCap = math.max(
                      constraints.maxWidth - _kTabSliverReserve,
                      math.min(_kClusterMinVisible, constraints.maxWidth),
                    );
                    return Row(
                      children: [
                        Expanded(
                          child: headerMode
                              ? _DockHeaderTitle(entry: widget.entries.single)
                              : ScrollConfiguration(
                                  // The strip scrolls as its overflow strategy;
                                  // no scrollbar — it would collide with the
                                  // tabs at this height.
                                  behavior: ScrollConfiguration.of(
                                    context,
                                  ).copyWith(scrollbars: false),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        for (final entry in widget.entries)
                                          _maybeDraggable(
                                            entry,
                                            _DockTab(
                                              entry: entry,
                                              selected: entry.id == active.id,
                                              inSplit:
                                                  split != null &&
                                                  constraints.maxWidth >=
                                                      widget.splitMinWidth &&
                                                  entry.id == split.id,
                                              onSelect: () => _select(entry.id),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: clusterCap),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: _ActionCluster(
                                widget: widget,
                                split: split != null,
                                canSplit:
                                    widget.entries.length > 1 &&
                                    constraints.maxWidth >=
                                        widget.splitMinWidth,
                                onToggleSplit: _toggleSplit,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: split == null
                ? _pane(active)
                : LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth < widget.splitMinWidth
                        ? _pane(active)
                        : _SplitPanes(
                            left: _pane(active),
                            right: _pane(split),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Single-entry presentation: a plain titled header, no tab affordance.
class _DockHeaderTitle extends StatelessWidget {
  const _DockHeaderTitle({required this.entry});

  final CruxDockEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(
            entry.icon,
            size: kCruxDockIconSize,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              entry.label,
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (entry.badgeCount > 0) ...[
            const SizedBox(width: 6),
            _DockBadge(count: entry.badgeCount),
          ],
        ],
      ),
    );
  }
}

class _DockTab extends StatelessWidget {
  const _DockTab({
    required this.entry,
    required this.selected,
    required this.onSelect,
    this.inSplit = false,
  });

  final CruxDockEntry entry;
  final bool selected;
  final VoidCallback onSelect;

  /// Whether this tab is on screen in the right pane of a split dock: it
  /// reads as selected too, with a quieter underline.
  final bool inSplit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = selected || inSplit;
    final color = shown
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: color,
      fontWeight: shown ? FontWeight.w600 : FontWeight.w400,
    );
    // One node for the tab: a button named after the entry, with its
    // selected state and its badge count as the value. The visible label and
    // the badge are excluded so neither is announced a second time; the
    // close button stays a separate, named child.
    return Semantics(
      container: true,
      button: true,
      selected: shown,
      label: entry.label,
      value: entry.badgeCount > 0 ? '${entry.badgeCount}' : null,
      child: InkWell(
        key: ValueKey('cruxDockTab-${entry.id}'),
        onTap: onSelect,
        child: _content(theme, color, style),
      ),
    );
  }

  Widget _content(ThemeData theme, Color color, TextStyle? style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        // VSCode's active-tab treatment: a primary underline, content
        // stepping up to onSurface.
        border: Border(
          bottom: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : inSplit
                ? theme.colorScheme.outline
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                Icon(entry.icon, size: kCruxDockIconSize, color: color),
                const SizedBox(width: 6),
                Text(entry.label, style: style),
                if (entry.badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  _DockBadge(count: entry.badgeCount),
                ],
              ],
            ),
          ),
          if (entry.closable) ...[
            const SizedBox(width: 4),
            // The `×` has no visible text, so Semantics is the only thing
            // standing between it and being announced as an unnamed
            // "button". Falls back to the tab's own label rather than an
            // English default — the package carries no localizations. Its
            // own container, so it is not folded into the tab's node.
            Semantics(
              container: true,
              label: entry.closeSemanticLabel ?? entry.label,
              button: true,
              child: InkWell(
                key: ValueKey('cruxDockClose-${entry.id}'),
                onTap: entry.onClose,
                borderRadius: BorderRadius.circular(8),
                child: Icon(Icons.close, size: 14, color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Feedback chip rendered under the pointer during a tab drag.
class _DragFeedbackChip extends StatelessWidget {
  const _DragFeedbackChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: kCruxDockIconSize,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Tab badge — `Badge.count` self-clamps at 999+.
class _DockBadge extends StatelessWidget {
  const _DockBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Badge.count(count: count);
}

class _ActionCluster extends StatelessWidget {
  const _ActionCluster({
    required this.widget,
    required this.split,
    required this.canSplit,
    required this.onToggleSplit,
  });

  final CruxDock widget;

  /// Whether the dock is split now.
  final bool split;

  /// Whether the dock is wide enough, with tabs enough, to split.
  final bool canSplit;

  final VoidCallback onToggleSplit;

  @override
  Widget build(BuildContext context) {
    final popOut = widget.popOut;
    final active = widget.entries.firstWhere(
      (e) => e.id == widget.activeId,
      orElse: () => widget.entries.first,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The ACTIVE entry's view-specific actions — VSCode's panel-title-bar
        // actions (the terminal's `+`). They precede the standard cluster and
        // swap when the active tab changes.
        ...active.actions,
        if (widget.onSplitChanged != null)
          _DockActionButton(
            key: const ValueKey('cruxDockSplit'),
            icon: split ? Icons.view_agenda_outlined : Icons.vertical_split,
            tooltip: split ? widget.unsplitTooltip : widget.splitTooltip,
            onPressed: split || canSplit ? onToggleSplit : null,
          ),
        if (widget.onMaximize != null)
          _DockActionButton(
            key: const ValueKey('cruxDockMaximize'),
            icon: widget.isMaximized
                ? Icons.close_fullscreen
                : Icons.open_in_full,
            tooltip: widget.isMaximized
                ? widget.restoreTooltip
                : widget.maximizeTooltip,
            onPressed: widget.onMaximize,
          ),
        if (popOut != null)
          _DockActionButton(
            key: const ValueKey('cruxDockPopOut'),
            icon: Icons.open_in_new,
            tooltip: popOut.tooltip,
            onPressed: popOut.enabled && popOut.onPopOut != null
                ? () {
                    final entries = widget.entries;
                    final active = entries.firstWhere(
                      (e) => e.id == widget.activeId,
                      orElse: () => entries.first,
                    );
                    popOut.onPopOut!(active.id);
                  }
                : null,
          ),
        if (widget.onCollapse != null)
          _DockActionButton(
            key: const ValueKey('cruxDockCollapse'),
            icon: widget.collapseDirection.icon,
            tooltip: widget.collapseTooltip,
            onPressed: widget.onCollapse,
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: kCruxDockIconSize),
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
  );
}

/// The two panes of a split dock, with a divider dragged to resize them.
/// The divider's position is the widget's own state: a resize is a
/// moment's adjustment, not part of the saved arrangement.
class _SplitPanes extends StatefulWidget {
  const _SplitPanes({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  State<_SplitPanes> createState() => _SplitPanesState();
}

class _SplitPanesState extends State<_SplitPanes> {
  double _fraction = 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = math.max<double>(
          0,
          constraints.maxWidth - _kSplitDividerWidth,
        );
        final leftWidth = usable * _fraction;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: leftWidth, child: widget.left),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: const ValueKey('cruxDockSplitDivider'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) {
                  if (usable <= 0) return;
                  setState(() {
                    _fraction = ((leftWidth + details.delta.dx) / usable).clamp(
                      _kSplitMinFraction,
                      1 - _kSplitMinFraction,
                    );
                  });
                },
                // Double-click puts the divider back in the middle.
                onDoubleTap: () => setState(() => _fraction = 0.5),
                child: SizedBox(
                  width: _kSplitDividerWidth,
                  child: Center(
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: theme.dividerColor,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
