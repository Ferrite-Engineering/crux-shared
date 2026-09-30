// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/src/crux_settings_card.dart';
import 'package:flutter/material.dart';

/// A settings-section body wrapped in the suite-shared grouped card
/// ([CruxSettingsCard]) with uniform 16 dp interior padding.
///
/// LintCrux and SimCrux each privately re-implemented this exact wrapper
/// (`SettingsSectionCard` / a file-local `_card()`); it is now the one
/// standard way a settings category's detail pane gets the card look used
/// across the suite.
class CruxSettingsSectionCard extends StatelessWidget {
  /// Creates a section card around [children].
  const CruxSettingsSectionCard({required this.children, super.key});

  /// The section's content, laid out in a stretched column inside the card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CruxSettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
