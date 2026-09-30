// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/src/toolbar_button.dart';
import 'package:crux_toolbar/src/toolbar_item.dart';
import 'package:crux_toolbar/src/toolbar_metrics.dart';
import 'package:crux_toolbar/src/toolbar_split_button.dart';
import 'package:flutter/material.dart';

/// The application toolbar every EDACrux product renders.
///
/// ## The shape
///
/// `[ common ] │ [ app-specific ]` — a left-hand block of the buttons that
/// mean the same thing in all four products, a divider, then the buttons that
/// are that product's own. A user moving between the apps finds Open, Save,
/// Close, Search, Cross-Probe and Settings in the same place every time.
///
/// ## What this owns, so the products don't
///
/// - **Geometry** — [CruxToolbarMetrics]. The four products previously carried
///   three different bar heights, two divider footprints, two background
///   roles, two border edges, and one specified no height at all.
/// - **Overflow** — the strip scrolls horizontally and an overflow button
///   stays pinned to the trailing edge. Three of the four products had no
///   overflow affordance at all: their strip scrolled silently, with no
///   chevron and no fade, and Settings — the last button in each — simply
///   vanished on a narrow window.
/// - **Enablement** — every button's enabled state comes from [isEnabled],
///   which products wire to their descriptor table, so the toolbar cannot
///   drift from the menu bar and palette.
/// - **Keys** — each button carries `ValueKey(action)`, so a conformance test
///   can find it by action rather than by glyph.
/// - **Accessibility** — the whole strip is one labelled [Semantics] region.
///   Only one product had this.
///
/// ## Overflow stability
///
/// The trailing slot is *always reserved* when [overflow] is supplied, and the
/// button inside it is only painted once the strip actually scrolls. Showing
/// and hiding the slot itself would change the available width, which changes
/// whether the strip overflows, which changes the slot — an oscillation. A
/// permanently reserved slot costs one button width of empty space at the far
/// right of a left-packed row, which is invisible, and is stable.
class CruxToolbar<A extends Object> extends StatefulWidget {
  /// Creates a toolbar.
  const CruxToolbar({
    required this.common,
    required this.specific,
    required this.isEnabled,
    required this.onAction,
    required this.shortcutOf,
    required this.semanticsLabel,
    this.metrics = CruxToolbarMetrics.desktop,
    this.overflow,
    this.trailing = const <Widget>[],
    this.splitVariantOf,
    this.onSplitVariantChanged,
    super.key,
  });

  /// The buttons shared by every product, in canonical order.
  final List<CruxToolbarItem<A>> common;

  /// This product's own buttons, rendered after the section divider.
  final List<CruxToolbarItem<A>> specific;

  /// Whether an action is currently invocable. Wire this to the product's
  /// `isActionEnabled(action, context)`.
  final bool Function(A) isEnabled;

  /// Dispatches an action.
  final void Function(A) onAction;

  /// The user's current binding for an action, for the live tooltip.
  final ShortcutActivator? Function(A) shortcutOf;

  /// Screen-reader label for the toolbar region.
  final String semanticsLabel;

  /// Geometry tokens. Hosts pass [CruxToolbarMetrics.touch] on touch device
  /// classes.
  final CruxToolbarMetrics metrics;

  /// The overflow affordance pinned to the trailing edge — typically the
  /// product's overflow action menu. Null reserves no slot.
  final Widget? overflow;

  /// Extra widgets after the overflow slot, e.g. debug-only affordances.
  final List<Widget> trailing;

  /// The persisted last-used variant for a split-button cluster, by cluster id.
  final A? Function(String clusterId)? splitVariantOf;

  /// Called when the user picks a different variant in a split cluster, so the
  /// host can persist it.
  final void Function(String clusterId, A variant)? onSplitVariantChanged;

  @override
  State<CruxToolbar<A>> createState() => _CruxToolbarState<A>();
}

class _CruxToolbarState<A extends Object> extends State<CruxToolbar<A>> {
  bool _overflowing = false;

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    final overflowing = notification.metrics.maxScrollExtent > 0;
    if (overflowing != _overflowing) {
      // Deferred: the notification arrives during layout, and flipping the
      // fade/overflow paint synchronously would rebuild mid-layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflowing = overflowing);
      });
    }
    return false;
  }

  List<Widget> _render(List<CruxToolbarItem<A>> items) => [
    for (final item in items)
      switch (item) {
        CruxToolbarSeparatorItem<A>() => CruxToolbarDivider(
          metrics: widget.metrics,
        ),
        CruxToolbarWidgetItem<A>(:final child, :final id) => KeyedSubtree(
          key: id == null ? null : ValueKey<String>(id),
          child: child,
        ),
        CruxToolbarSplitItem<A>() => CruxToolbarSplitButton<A>(
          key: ValueKey<String>(item.id),
          item: item,
          metrics: widget.metrics,
          isEnabled: widget.isEnabled,
          onAction: widget.onAction,
          shortcutOf: widget.shortcutOf,
          initialVariant: widget.splitVariantOf?.call(item.id),
          onVariantChanged: widget.onSplitVariantChanged == null
              ? null
              : (variant) => widget.onSplitVariantChanged!(item.id, variant),
        ),
        CruxToolbarButtonItem<A>(
          :final action,
          :final icon,
          :final selectedIcon,
          :final tooltip,
          :final isSelected,
          :final tintWhenSelected,
          :final badgeCount,
        ) =>
          CruxToolbarButton(
            key: ValueKey<A>(action),
            icon: isSelected && selectedIcon != null ? selectedIcon : icon,
            tooltip: cruxToolbarTooltip(tooltip, widget.shortcutOf(action)),
            onPressed: widget.isEnabled(action)
                ? () => widget.onAction(action)
                : null,
            metrics: widget.metrics,
            isSelected: isSelected,
            tintWhenSelected: tintWhenSelected,
            badgeCount: badgeCount,
          ),
      },
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final strip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: widget.metrics.horizontalPadding),
        ..._render(widget.common),
        // The section divider the whole layout is built around. Drawn only
        // when both sides have content, so a product with no specific buttons
        // does not end on a dangling rule.
        if (widget.common.isNotEmpty && widget.specific.isNotEmpty)
          CruxToolbarDivider(metrics: widget.metrics),
        ..._render(widget.specific),
        SizedBox(width: widget.metrics.horizontalPadding),
      ],
    );

    return Semantics(
      label: widget.semanticsLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SizedBox(
          height: widget.metrics.height,
          child: Row(
            children: [
              Expanded(
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _onScrollMetrics,
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: strip,
                      ),
                      // A fade on the trailing edge so a partially-scrolled
                      // button is visibly cut off rather than looking like the
                      // strip simply ends there.
                      if (_overflowing)
                        PositionedDirectional(
                          top: 0,
                          bottom: 0,
                          end: 0,
                          child: IgnorePointer(
                            child: SizedBox(
                              width: 12,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: AlignmentDirectional.centerStart,
                                    end: AlignmentDirectional.centerEnd,
                                    colors: [
                                      scheme.surfaceContainerHigh.withValues(
                                        alpha: 0,
                                      ),
                                      scheme.surfaceContainerHigh,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (widget.overflow case final Widget overflow)
                SizedBox(
                  width: widget.metrics.buttonSize,
                  child: _overflowing ? overflow : null,
                ),
              ...widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
