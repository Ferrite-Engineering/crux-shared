// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A labelled group of annotation rows in a panel: an adopted layer, "Not
/// displayed", "Not in this file", "Outside the current scope".
///
/// The header is a single line in the theme's small label style; the rows are
/// the product's own.
class CruxAnnotationGroup extends StatelessWidget {
  /// Creates the group.
  const CruxAnnotationGroup({
    required this.label,
    required this.children,
    this.trailing,
    super.key,
  });

  /// The header text, already localized (and usually carrying the count).
  final String label;

  /// The rows.
  final List<Widget> children;

  /// Controls that act on the group as a unit: present for a group a user can
  /// hide or delete wholesale, absent for a classification such as "Not
  /// displayed".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
      ...children,
    ],
  );
}
