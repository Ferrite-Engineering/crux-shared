// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A settings row whose primary control is too wide to sit in a trailing
/// slot — a `SegmentedButton`, for instance.
///
/// The label and optional [description] stack above a full-width [control].
/// Use this instead of cramming a wide control into a `ListTile.subtitle`,
/// which produces inconsistent alignment across a settings panel.
class CruxSettingsControlTile extends StatelessWidget {
  /// Creates a stacked control row.
  const CruxSettingsControlTile({
    required this.title,
    required this.control,
    this.description,
    super.key,
  });

  /// Row label.
  final String title;

  /// Optional secondary description shown under the [title].
  final String? description;

  /// The full-width control rendered below the label.
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(
              description!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          control,
        ],
      ),
    );
  }
}
