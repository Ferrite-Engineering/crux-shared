// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/src/crux_settings_category.dart';
import 'package:flutter/material.dart';

/// A settings category contributed from outside an app's open-core list —
/// the suite's ONE extension seam for Pro-overlay settings.
///
/// Replaces three incompatible per-app seam types (WaveCrux's bare
/// `CruxSettingsCategory Function(BuildContext)`, LintCrux's
/// `SettingsExtraSection`, SimCrux's `SettingsSectionExtension`) with the
/// richest of the three shapes: a stable [id] (deep links, tests), a
/// required [icon], and context-taking builders so the contributor
/// localizes with its own `L10N` and may return a `Consumer` for
/// provider-aware bodies.
@immutable
class CruxSettingsExtraCategory {
  /// Creates an extra settings category.
  const CruxSettingsExtraCategory({
    required this.id,
    required this.icon,
    required this.labelBuilder,
    required this.bodyBuilder,
  });

  /// Stable identifier, e.g. `pro.custom_rules`. Never shown to the user.
  final String id;

  /// Rail icon for the category.
  final IconData icon;

  /// Resolves the localized rail label.
  final String Function(BuildContext context) labelBuilder;

  /// Builds the category's detail-pane content.
  final WidgetBuilder bodyBuilder;

  /// The equivalent [CruxSettingsCategory] for the master-detail shell.
  ///
  /// Carries this entry's own `pro.*` [id] through, so a Pro-contributed
  /// category is as identifiable in the assembled rail as a built-in one —
  /// which is what lets a conformance test assert that Pro extras follow all
  /// of the canonical categories rather than interleaving with them.
  CruxSettingsCategory toCategory(BuildContext context) => CruxSettingsCategory(
    id: id,
    icon: icon,
    title: labelBuilder(context),
    content: Builder(builder: bodyBuilder),
  );
}
