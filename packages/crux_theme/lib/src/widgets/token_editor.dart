// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/providers.dart';
import 'package:crux_theme/src/theme_registry.dart';
import 'package:crux_theme/src/theme_token_category.dart';
import 'package:crux_theme/src/widgets/color_swatch.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single-row editor for one themable color token.
///
/// The row renders the descriptor's display name, an interactive
/// [CruxColorSwatch] showing the current value, and a "reset to
/// default" button that activates only when the active theme has an
/// explicit value for the token (i.e. the user has overridden the
/// descriptor default).
///
/// All edits flow through [cruxColorThemeProvider]'s notifier:
///
/// * Tapping the swatch and confirming the picker calls
///   `applyOverrides({"<category>.<token>": picked})`.
/// * Tapping "reset" rebuilds the active theme's token table with the
///   entry removed.
///
/// The widget is generic over no payload type — it reads from a
/// `NotifierProvider<CruxColorThemeNotifier, CruxColorTheme>` directly
/// since [cruxColorThemeProvider] is process-wide.
class TokenEditor extends ConsumerWidget {
  /// Creates an editor row.
  const TokenEditor({
    required this.categoryId,
    required this.descriptor,
    this.strings = const ThemeAppearanceStringsEn(),
    super.key,
  });

  /// Category id under which [descriptor] is registered. Combined with
  /// `descriptor.id` to form the dotted override key.
  final String categoryId;

  /// Descriptor for the token edited by this row.
  final ThemeTokenDescriptor descriptor;

  /// Localized strings driving every label and tooltip.
  final ThemeAppearanceStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch only this row's own token, not the whole theme. Every token
    // in every expanded category renders one of these; watching the
    // whole CruxColorTheme meant changing a single color via
    // applyOverrides rebuilt every row in the editor, each re-running
    // ThemeRegistry.resolve and hasToken. `select` rebuilds a row only
    // when its own resolved value or override state actually moves.
    final (current, hasOverride) = ref.watch(
      cruxColorThemeProvider.select((theme) {
        final resolved =
            ThemeRegistry.instance.resolve(theme, categoryId, descriptor.id) ??
            descriptor.defaultFor(theme.brightness);
        return (resolved, theme.hasToken(categoryId, descriptor.id));
      }),
    );
    final notifier = ref.read(cruxColorThemeProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descriptor.displayName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (descriptor.description != null)
                  Text(
                    descriptor.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CruxColorSwatch(
            color: current,
            strings: strings,
            onColorPicked: (picked) {
              notifier.applyOverrides({
                CruxColorTheme.dottedId(categoryId, descriptor.id): picked,
              });
            },
          ),
          IconButton(
            tooltip: strings.resetTokenToDefaultTooltip,
            icon: const Icon(Icons.refresh),
            onPressed: hasOverride
                // Read the theme at press time rather than closing over
                // a build-time snapshot — the row no longer watches the
                // whole theme, so a snapshot could be stale.
                ? () => _resetTokenOverride(
                    notifier,
                    ref.read(cruxColorThemeProvider),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  void _resetTokenOverride(
    CruxColorThemeNotifier notifier,
    CruxColorTheme current,
  ) {
    final next = <String, Map<String, Color>>{};
    for (final entry in current.tokens.entries) {
      if (entry.key != categoryId) {
        next[entry.key] = Map<String, Color>.from(entry.value);
        continue;
      }
      final pruned = <String, Color>{};
      for (final tokenEntry in entry.value.entries) {
        if (tokenEntry.key == descriptor.id) continue;
        pruned[tokenEntry.key] = tokenEntry.value;
      }
      if (pruned.isNotEmpty) next[categoryId] = pruned;
    }
    notifier.activate(current.copyWith(tokens: next));
  }
}
