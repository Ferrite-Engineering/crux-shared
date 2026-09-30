// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A rounded, bordered "grouped list" card for a Settings detail pane.
///
/// Children are stacked and separated by inset hairline dividers, matching
/// the native grouped-settings idiom on macOS / iOS / Android. This is the
/// *section grouping* surface, so it uses the quiet
/// [ColorScheme.surfaceContainerLow] tone with a large (12 dp) radius —
/// deliberately distinct from *data / value* surfaces (preset cards,
/// swatches, text inputs) which sit at [ColorScheme.surfaceContainerHighest].
///
/// The card restores comfortable settings-row padding via a
/// [ListTileTheme.merge], so it reads correctly even when the host's
/// ambient [ListTileThemeData] is tuned dense for other surfaces (e.g. a
/// tree). Every row — `ListTile`/`SwitchListTile`, sliders, segmented
/// buttons — then clears the card border on all four sides.
class CruxSettingsCard extends StatelessWidget {
  /// Creates a grouped settings card from [children].
  const CruxSettingsCard({required this.children, super.key});

  /// Rows to stack inside the card, separated by inset hairline dividers.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: ListTileTheme.merge(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          minVerticalPadding: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16),
                  // A Card is a semantics container, so a row that is not a
                  // container itself (a plain ListTile with a trailing
                  // dropdown) would pour its text into the card's name, and
                  // every other row's control would then be announced
                  // inside a group named after that one row.
                  Semantics(container: true, child: children[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
