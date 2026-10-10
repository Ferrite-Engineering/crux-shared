// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/src/toolbar_button.dart';
import 'package:crux_toolbar/src/toolbar_item.dart';
import 'package:crux_toolbar/src/toolbar_metrics.dart';
import 'package:flutter/material.dart';

/// A Photoshop-style grouped tool button.
///
/// One slot in the strip stands for a family of related actions — the four
/// LintCrux export formats, WaveCrux's export targets, NetCrux's fan-in /
/// fan-out / clear-overlay trio. Tapping fires the currently-faced variant;
/// **long-press, right-click, or tapping the corner triangle** opens the
/// sibling menu, and the chosen variant becomes the new face.
///
/// This is what lets a cluster of four menu-only commands earn a single
/// toolbar slot instead of none.
class CruxToolbarSplitButton<A extends Object> extends StatefulWidget {
  /// Creates a split button.
  const CruxToolbarSplitButton({
    required this.item,
    required this.metrics,
    required this.isEnabled,
    required this.onAction,
    required this.shortcutOf,
    this.initialVariant,
    this.onVariantChanged,
    super.key,
  });

  /// The cluster this button stands for.
  final CruxToolbarSplitItem<A> item;

  /// Geometry tokens.
  final CruxToolbarMetrics metrics;

  /// Whether a given variant is currently invocable.
  final bool Function(A) isEnabled;

  /// Dispatches the chosen variant.
  final void Function(A) onAction;

  /// The user's current binding for a variant, for the menu's trailing
  /// accelerator column.
  final ShortcutActivator? Function(A) shortcutOf;

  /// The variant to show on the face initially. Hosts pass the persisted
  /// last-used choice; null means the cluster's first variant.
  final A? initialVariant;

  /// Called when the user picks a different variant, so the host can persist
  /// it and restore it on next launch.
  final void Function(A)? onVariantChanged;

  @override
  State<CruxToolbarSplitButton<A>> createState() =>
      _CruxToolbarSplitButtonState<A>();
}

class _CruxToolbarSplitButtonState<A extends Object>
    extends State<CruxToolbarSplitButton<A>> {
  final MenuController _menu = MenuController();
  late A _current = _resolveInitial();

  /// A focus target inside the sibling menu, focused when the menu opens.
  ///
  /// A `MenuAnchor` opened by the pointer (long-press, right-click, the
  /// corner triangle) leaves focus where it was, outside the menu, so the
  /// menu's own Escape handling never saw the key: Escape did nothing and
  /// macOS beeped. Focusing a node inside the menu routes Escape (and the
  /// arrow keys) to the menu. It is not one of the items, so opening with the
  /// pointer highlights nothing, as a desktop menu opened by the mouse
  /// should look.
  final FocusNode _menuFocus = FocusNode(
    debugLabel: 'CruxToolbarSplitButton menu',
    skipTraversal: true,
  );

  @override
  void dispose() {
    _menuFocus.dispose();
    super.dispose();
  }

  void _openMenu() {
    _menu.open();
    // After the frame that mounts the menu's overlay.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu.isOpen) _menuFocus.requestFocus();
    });
  }

  A _resolveInitial() {
    final initial = widget.initialVariant;
    if (initial != null &&
        widget.item.variants.any((v) => v.action == initial)) {
      return initial;
    }
    return widget.item.variants.first.action;
  }

  @override
  void didUpdateWidget(CruxToolbarSplitButton<A> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The cluster's contents can change with license tier or app state; if the
    // faced variant is gone, fall back rather than render a dangling face.
    if (!widget.item.variants.any((v) => v.action == _current)) {
      _current = _resolveInitial();
    }
  }

  CruxToolbarButtonItem<A> get _face =>
      widget.item.variants.firstWhere((v) => v.action == _current);

  void _select(CruxToolbarButtonItem<A> variant) {
    if (variant.action != _current) {
      setState(() => _current = variant.action);
      widget.onVariantChanged?.call(variant.action);
    }
    widget.onAction(variant.action);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final face = _face;
    final faceEnabled = widget.isEnabled(face.action);

    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        Focus(
          focusNode: _menuFocus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final variant in widget.item.variants)
                MenuItemButton(
                  key: ValueKey<A>(variant.action),
                  leadingIcon: Icon(
                    variant.icon,
                    size: widget.metrics.iconSize,
                  ),
                  shortcut: switch (widget.shortcutOf(variant.action)) {
                    final SingleActivator a => a,
                    _ => null,
                  },
                  onPressed: widget.isEnabled(variant.action)
                      ? () => _select(variant)
                      : null,
                  child: Text(variant.tooltip),
                ),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onLongPress: _openMenu,
        onSecondaryTap: _openMenu,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CruxToolbarButton(
              key: ValueKey<A>(face.action),
              icon: face.isSelected && face.selectedIcon != null
                  ? face.selectedIcon!
                  : face.icon,
              tooltip: cruxToolbarTooltip(
                widget.item.faceTooltip?.call(face.action) ?? face.tooltip,
                widget.shortcutOf(face.action),
              ),
              onPressed: faceEnabled
                  ? () => widget.onAction(face.action)
                  : null,
              metrics: widget.metrics,
              isSelected: face.isSelected,
              tintWhenSelected: face.tintWhenSelected,
              badgeCount: face.badgeCount,
              // Frees the long-press for the sibling menu; hover still shows
              // the tooltip on desktop.
              tooltipOnHoverOnly: true,
            ),
            // The corner affordance: a small triangle marking "there is more
            // here", and a tap target of its own so the sibling menu is
            // reachable without knowing about long-press.
            PositionedDirectional(
              end: 1,
              bottom: 1,
              child: Semantics(
                label: widget.item.tooltip,
                button: true,
                child: GestureDetector(
                  onTap: _openMenu,
                  child: CustomPaint(
                    size: const Size(6, 6),
                    painter: _CornerTrianglePainter(
                      color: faceEnabled
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom-trailing triangle that marks a split button.
class _CornerTrianglePainter extends CustomPainter {
  const _CornerTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
