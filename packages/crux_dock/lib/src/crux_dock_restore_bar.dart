// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/src/crux_dock.dart';
import 'package:flutter/material.dart';

/// Thickness of a [CruxDockRestoreBar] (its cross-axis extent).
const double kCruxDockRestoreBarThickness = 28;

/// One tappable entry on a [CruxDockRestoreBar]: a collapsed dock tab.
@immutable
class CruxDockRestoreEntry {
  /// Creates a restore entry.
  const CruxDockRestoreEntry({
    required this.id,
    required this.icon,
    required this.label,
    required this.onRestore,
  });

  /// The dock entry's id (used for widget keys).
  final String id;

  /// The tab's icon.
  final IconData icon;

  /// Localized label, shown as the button's tooltip.
  final String label;

  /// Reopens the region with this tab active.
  final VoidCallback onRestore;
}

/// The slim edge strip a COLLAPSED dock region leaves behind — the
/// JetBrains "tool window bar" model, solving "the only way to reopen a
/// panel is dragging the resize bar".
///
/// Hosts render one along the matching window edge whenever a region is
/// hidden: the strip shows the dock's tab icons and a click reopens the
/// region with that tab active. The panel therefore never fully vanishes;
/// its tabs remain one click away exactly where the panel was.
///
/// [edge] picks the orientation: [CruxDockCollapseDirection.down] renders a
/// horizontal bar (mounted under the center content, above the status bar);
/// left/right render vertical bars at the window flanks.
class CruxDockRestoreBar extends StatelessWidget {
  /// Creates a restore bar.
  const CruxDockRestoreBar({
    required this.edge,
    required this.entries,
    this.semanticsLabel,
    super.key,
  });

  /// Which edge the bar sits along.
  final CruxDockCollapseDirection edge;

  /// The collapsed dock's tabs, in strip order.
  final List<CruxDockRestoreEntry> entries;

  /// Optional semantics label for the bar region.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = edge == CruxDockCollapseDirection.down;

    // Each restore button is its own named button. With only a tooltip, an
    // icon InkWell merged into the bar's region node and a screen reader
    // announced the region's name as a bare "text" ("Panel dock, text").
    final buttons = <Widget>[
      for (final entry in entries)
        MergeSemantics(
          child: Semantics(
            button: true,
            label: entry.label,
            child: Tooltip(
              message: entry.label,
              excludeFromSemantics: true,
              child: InkWell(
                key: ValueKey('cruxDockRestore-${entry.id}'),
                onTap: entry.onRestore,
                child: SizedBox(
                  width: kCruxDockRestoreBarThickness,
                  height: kCruxDockRestoreBarThickness,
                  child: Icon(
                    entry.icon,
                    size: kCruxDockIconSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];

    final border = switch (edge) {
      CruxDockCollapseDirection.down => Border(
        top: BorderSide(color: theme.dividerColor, width: 0.5),
      ),
      CruxDockCollapseDirection.left => Border(
        right: BorderSide(color: theme.dividerColor, width: 0.5),
      ),
      CruxDockCollapseDirection.right => Border(
        left: BorderSide(color: theme.dividerColor, width: 0.5),
      ),
    };

    return Semantics(
      label: semanticsLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: border,
        ),
        child: horizontal
            ? SizedBox(
                height: kCruxDockRestoreBarThickness,
                child: Row(children: buttons),
              )
            : SizedBox(
                width: kCruxDockRestoreBarThickness,
                child: Column(children: buttons),
              ),
      ),
    );
  }
}
