// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/theme_token_category.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:crux_theme/src/widgets/token_editor.dart';
import 'package:flutter/material.dart';

/// Expandable card that groups every [TokenEditor] inside one
/// [ThemeTokenCategory].
///
/// Renders the category's [ThemeTokenCategory.displayName] as a tappable
/// header with a leading expand / collapse chevron. The body is a
/// vertical list of [TokenEditor] rows, one per descriptor, in
/// registration order. The card starts collapsed by default to keep the
/// Settings → Appearance surface scannable; the user opens any category
/// they want to edit.
///
/// Expansion state is in-memory only. Persisted-expansion-state across
/// launches is a host-product concern (typically wired through the
/// product's settings store keyed by `crux_theme.expanded.<categoryId>`)
/// and is exposed as the [initiallyExpanded] argument so adopters can
/// supply their own restoration.
class TokenCategorySection extends StatefulWidget {
  /// Creates a category section.
  const TokenCategorySection({
    required this.category,
    this.strings = const ThemeAppearanceStringsEn(),
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    super.key,
  });

  /// Token category whose descriptors this section edits.
  final ThemeTokenCategory category;

  /// Localized strings forwarded to each [TokenEditor].
  final ThemeAppearanceStrings strings;

  /// Whether the section starts expanded. Use to restore persisted
  /// per-category expansion state on launch.
  final bool initiallyExpanded;

  /// Optional callback fired with the new expansion state when the
  /// header is tapped. Use to persist per-category expansion state.
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<TokenCategorySection> createState() => _TokenCategorySectionState();
}

class _TokenCategorySectionState extends State<TokenCategorySection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            category: widget.category,
            strings: widget.strings,
            expanded: _expanded,
            onToggle: _toggle,
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: widget.category.tokens.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        widget.strings.emptyTokenCategoryMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : Column(
                      children: [
                        for (final descriptor in widget.category.tokens)
                          TokenEditor(
                            categoryId: widget.category.id,
                            descriptor: descriptor,
                            strings: widget.strings,
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.category,
    required this.strings,
    required this.expanded,
    required this.onToggle,
  });

  final ThemeTokenCategory category;
  final ThemeAppearanceStrings strings;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = expanded
        ? strings.collapseCategoryLabel(category.displayName)
        : strings.expandCategoryLabel(category.displayName);
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}
