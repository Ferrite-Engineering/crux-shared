// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/src/crux_color_theme.dart';
import 'package:crux_theme/src/theme_pack_store.dart';
import 'package:crux_theme/src/theme_registry.dart';
import 'package:crux_theme/src/widgets/preset_picker.dart';
import 'package:crux_theme/src/widgets/theme_appearance_strings.dart';
import 'package:crux_theme/src/widgets/theme_pack_browser.dart';
import 'package:crux_theme/src/widgets/token_category_section.dart';
import 'package:flutter/material.dart';

/// Default top-level Settings → Appearance composer for the
/// `crux_theme` widget set.
///
/// Drops the three primary surfaces into a single vertical layout in
/// the order an adopter typically wants them:
///
/// 1. Section title + optional subtitle.
/// 2. [PresetPicker] — quick way to swap to a curated theme.
/// 3. One [TokenCategorySection] per registered token category — for
///    per-token edits (collapsed by default).
/// 4. [ThemePackBrowser] — install / export / uninstall flow for
///    user-supplied `.crux-theme.json` packs.
///
/// Adopters who want a different order — or who want to weave in
/// product-specific widgets (e.g. a WaveCrux "Quick canvas overrides"
/// shortcut for the four most-tweaked tokens) — should compose their
/// own layout from the individual exported widgets instead.
///
/// Constructor arguments:
///
/// * [presets]: ordered list of presets the user can choose. Pass
///   `builtinPresets().values.toList()` plus any product-specific
///   additions.
/// * [store]: storage for installed packs. Use
///   `DirectoryThemePackStore(directory: ...)` on desktop/mobile; the
///   widget itself stays `dart:io`-free so it renders on web.
/// * [pickPackDocument] / [savePackDocument]: caller-supplied document
///   picker / exporter for [ThemePackBrowser]. Plug your chosen
///   `file_picker` / share-sheet bridge in here; both exchange
///   document text rather than file handles.
/// * [showAdvancedOverrides]: when `false`, the per-token override
///   block is hidden — useful for compact mobile Settings panels.
/// * [trailingActions]: optional product-specific widgets appended
///   below [ThemePackBrowser]. Lets adopters add e.g. a "Reset to
///   defaults" button without subclassing the composer.
/// * [previewTokens]: forwarded to [PresetPicker.previewTokens] so
///   the preset cards highlight the host product's most-distinguishing
///   tokens.
class ThemeAppearanceSection extends StatelessWidget {
  /// Creates the default composer.
  const ThemeAppearanceSection({
    required this.presets,
    required this.store,
    required this.pickPackDocument,
    required this.savePackDocument,
    this.strings = const ThemeAppearanceStringsEn(),
    this.showAdvancedOverrides = true,
    this.trailingActions = const <Widget>[],
    this.previewTokens,
    super.key,
  });

  /// Presets rendered by the embedded [PresetPicker].
  final List<CruxColorTheme> presets;

  /// Storage used by the embedded [ThemePackBrowser] for installed
  /// theme packs.
  final ThemePackStore store;

  /// Document picker callback forwarded to [ThemePackBrowser].
  final PickPackDocument pickPackDocument;

  /// Document exporter callback forwarded to [ThemePackBrowser].
  final SavePackDocument savePackDocument;

  /// Localized strings shared across every child widget.
  final ThemeAppearanceStrings strings;

  /// When `false`, suppresses the per-category token override section.
  final bool showAdvancedOverrides;

  /// Product-specific widgets appended below the pack browser.
  final List<Widget> trailingActions;

  /// Optional preview token list forwarded to [PresetPicker].
  final List<(String, String)>? previewTokens;

  @override
  Widget build(BuildContext context) {
    final categories = ThemeRegistry.instance.registeredCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          title: strings.sectionTitle,
          subtitle: strings.sectionSubtitle,
        ),
        const SizedBox(height: 8),
        _SubsectionHeading(label: strings.presetSectionHeading),
        const SizedBox(height: 4),
        PresetPicker(
          presets: presets,
          strings: strings,
          previewTokens: previewTokens,
        ),
        if (showAdvancedOverrides) ...[
          const SizedBox(height: 16),
          _SubsectionHeading(label: strings.tokenOverridesSectionHeading),
          const SizedBox(height: 4),
          for (final category in categories)
            TokenCategorySection(category: category, strings: strings),
        ],
        const SizedBox(height: 16),
        _SubsectionHeading(label: strings.themePackBrowserSectionHeading),
        const SizedBox(height: 4),
        ThemePackBrowser(
          store: store,
          pickPackDocument: pickPackDocument,
          savePackDocument: savePackDocument,
          strings: strings,
        ),
        if (trailingActions.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...trailingActions,
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SubsectionHeading extends StatelessWidget {
  const _SubsectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}
