// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility guidelines for the shared settings shell.
///
/// A suite-wide audit found ZERO accessibility tests
/// across nine repos while `flutter_test` ships four guideline matchers free.
///
/// Settings is where a user goes to make the app usable for them — the theme,
/// the font size, the language, the reduce-motion-adjacent knobs. A settings
/// surface that is itself inaccessible is a closed door in front of the room
/// where the accessibility controls live, so it is worth guarding on its own
/// account rather than as one screen among many.
///
/// The master-detail shell is also the one surface with two materially
/// different layouts — a rail-plus-detail on wide viewports and a
/// list-then-detail on narrow ones. They are different widget trees, so both
/// are asserted; assuming the narrow layout inherits the wide one's compliance
/// is the kind of assumption accessibility testing keeps disproving.
List<CruxSettingsCategory> _categories() => const [
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.general,
    icon: Icons.tune,
    title: 'General',
    content: CruxSettingsCard(children: [Text('general-body')]),
  ),
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.appearance,
    icon: Icons.palette_outlined,
    title: 'Appearance',
    content: CruxSettingsCard(children: [Text('appearance-body')]),
  ),
  CruxSettingsCategory(
    id: CruxSettingsCategoryId.shortcuts,
    icon: Icons.keyboard_outlined,
    title: 'Keyboard Shortcuts',
    content: CruxSettingsCard(children: [Text('shortcuts-body')]),
  ),
];

Widget _host({required Brightness brightness}) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4650C8),
      brightness: brightness,
    ),
  ),
  home: Scaffold(body: CruxSettingsMasterDetail(categories: _categories())),
);

void main() {
  for (final brightness in Brightness.values) {
    for (final size in const [
      (label: 'wide', value: Size(1000, 700)),
      (label: 'narrow', value: Size(480, 700)),
    ]) {
      testWidgets(
        'settings shell meets the guidelines '
        '(${brightness.name}, ${size.label})',
        (tester) async {
          await tester.binding.setSurfaceSize(size.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final handle = tester.ensureSemantics();
          await tester.pumpWidget(_host(brightness: brightness));
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

          handle.dispose();
        },
      );
    }
  }
}
