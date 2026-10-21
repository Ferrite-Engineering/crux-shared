// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shared Settings tiles draw the owned Crux Desktop controls under a
/// desktop theme and keep Material's under a phone or tablet theme.
Widget _host({required bool desktop, required ValueChanged<String> onLocale}) {
  return MaterialApp(
    theme: ThemeData(
      extensions: desktop
          ? const <ThemeExtension<dynamic>>[CruxDesktopTokens()]
          : const <ThemeExtension<dynamic>>[],
    ),
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => CruxSettingsCard(
          children: [
            CruxAutoReloadSettingTile(
              label: 'When a loaded file changes',
              description: 'Applies at once',
              value: AutoReloadMode.prompt,
              onChanged: (_) {},
              promptLabel: 'Ask',
              autoLabel: 'Reload',
              offLabel: 'Ignore',
            ),
            CruxLocaleSettingTile(
              label: 'Language',
              description: 'Applies at once',
              locale: 'en',
              onChanged: onLocale,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desktop: the owned segmented control and pop-up, keys kept', (
    tester,
  ) async {
    await tester.pumpWidget(_host(desktop: true, onLocale: (_) {}));
    expect(
      find.byKey(const ValueKey('cruxAutoReloadSegments')),
      findsOneWidget,
    );
    expect(
      find.byType(CruxSegmentedControl<AutoReloadMode>),
      findsOneWidget,
    );
    expect(find.byType(SegmentedButton<AutoReloadMode>), findsNothing);
    expect(find.byKey(const ValueKey('cruxLocaleDropdown')), findsOneWidget);
    expect(find.byType(CruxPopUpButton<String>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('phone and tablet: Material, keys kept', (tester) async {
    await tester.pumpWidget(_host(desktop: false, onLocale: (_) {}));
    expect(find.byType(SegmentedButton<AutoReloadMode>), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cruxAutoReloadSegments')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cruxLocaleDropdown')), findsOneWidget);
  });

  testWidgets('desktop: choosing a language reports its code', (tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(_host(desktop: true, onLocale: chosen.add));
    await tester.tap(find.byKey(const ValueKey('cruxLocaleDropdown')));
    await tester.pump();
    await tester.tap(find.textContaining('日本語').last);
    await tester.pump();
    expect(chosen, ['ja']);
  });

  testWidgets('desktop focus walk: the segments are a named group, the '
      'pop-up is named by its row', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(desktop: true, onLocale: (_) {}));
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_shared_tiles_desktop.txt');
    handle.dispose();
  });
}
