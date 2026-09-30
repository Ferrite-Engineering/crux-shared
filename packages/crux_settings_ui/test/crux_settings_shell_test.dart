// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  group('openCruxSettings', () {
    testWidgets('asDialog: true shows the clamped dialog shell with a title '
        'row, close ×, and a non-dismissible barrier', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => openCruxSettings(
                  context,
                  title: 'Settings',
                  closeTooltip: 'Close',
                  asDialog: true,
                  bodyBuilder: (_) => const Text('BODY'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(CruxSettingsDialogShell), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);

      // Barrier tap must NOT dismiss.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(CruxSettingsDialogShell), findsOneWidget);

      // The close × does.
      await tester.tap(find.byKey(const ValueKey('cruxSettingsClose')));
      await tester.pumpAndSettle();
      expect(find.byType(CruxSettingsDialogShell), findsNothing);
    });

    testWidgets('asDialog: false pushes the route shell with an arrow_back '
        'leading', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => openCruxSettings(
                  context,
                  title: 'Settings',
                  closeTooltip: 'Back',
                  asDialog: false,
                  bodyBuilder: (_) => const Text('BODY'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(CruxSettingsRouteShell), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(CruxSettingsRouteShell), findsNothing);
    });

    testWidgets('wrap re-parents the shell (LintCrux tab-scope seam)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => openCruxSettings(
                  context,
                  title: 'Settings',
                  closeTooltip: 'Close',
                  asDialog: true,
                  bodyBuilder: (_) => const Text('BODY'),
                  wrap: (context, shell) => KeyedSubtree(
                    key: const ValueKey('wrapped'),
                    child: shell,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('wrapped')),
          matching: find.byType(CruxSettingsDialogShell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the dialog clamps to the viewport with a 48 dp gutter', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => openCruxSettings(
                  context,
                  title: 'Settings',
                  closeTooltip: 'Close',
                  asDialog: true,
                  bodyBuilder: (_) => const SizedBox.expand(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final size = tester.getSize(
        find.descendant(
          of: find.byType(CruxSettingsDialogShell),
          matching: find.byType(SizedBox).first,
        ),
      );
      expect(size.width, lessThanOrEqualTo(600 - 48));
      expect(size.height, lessThanOrEqualTo(500 - 48));
    });
  });

  group('CruxSettingsExtraCategory', () {
    testWidgets('toCategory carries id-stable icon/label/body', (tester) async {
      final extra = CruxSettingsExtraCategory(
        id: 'pro.example',
        icon: Icons.extension,
        labelBuilder: (_) => 'Example',
        bodyBuilder: (_) => const Text('EXTRA BODY'),
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              final category = extra.toCategory(context);
              expect(category.icon, Icons.extension);
              expect(category.title, 'Example');
              return Scaffold(body: category.content);
            },
          ),
        ),
      );
      expect(find.text('EXTRA BODY'), findsOneWidget);
    });
  });

  group('shared setting tiles', () {
    testWidgets('CruxLocaleSettingTile lists the four shipped locales and '
        'reports selection', (tester) async {
      String? selected;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CruxLocaleSettingTile(
              label: 'Language',
              description: 'UI language',
              locale: 'en',
              onChanged: (v) => selected = v,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cruxLocaleDropdown')));
      await tester.pumpAndSettle();
      expect(find.text('🇯🇵  日本語'), findsOneWidget);
      await tester.tap(find.text('🇯🇵  日本語').last);
      await tester.pumpAndSettle();
      expect(selected, 'ja');
    });

    testWidgets('CruxLocaleSettingTile degrades unknown codes to English', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CruxLocaleSettingTile(
              label: 'Language',
              description: 'UI language',
              locale: 'tlh',
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('🇺🇸  English'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CruxAutoReloadSettingTile renders prompt/auto/off in '
        'canonical order and reports selection', (tester) async {
      AutoReloadMode? selected;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CruxAutoReloadSettingTile(
              label: 'Auto-reload',
              description: 'When a loaded file changes on disk',
              value: AutoReloadMode.prompt,
              onChanged: (v) => selected = v,
              promptLabel: 'Prompt',
              autoLabel: 'Auto',
              offLabel: 'Off',
            ),
          ),
        ),
      );
      final promptX = tester.getCenter(find.text('Prompt')).dx;
      final autoX = tester.getCenter(find.text('Auto')).dx;
      final offX = tester.getCenter(find.text('Off')).dx;
      expect(promptX, lessThan(autoX));
      expect(autoX, lessThan(offX));

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(selected, AutoReloadMode.off);
    });

    testWidgets('CruxSettingsSectionCard wraps children in the grouped card '
        'with 16 dp padding', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: CruxSettingsSectionCard(children: [Text('IN CARD')]),
          ),
        ),
      );
      expect(find.byType(CruxSettingsCard), findsOneWidget);
      expect(find.text('IN CARD'), findsOneWidget);
    });
  });
}
