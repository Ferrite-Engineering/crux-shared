// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CruxSettingsCard', () {
    testWidgets('renders a Card with hairline dividers between children', (
      tester,
    ) async {
      await _pump(
        tester,
        const CruxSettingsCard(
          children: [Text('a'), Text('b'), Text('c')],
        ),
      );
      expect(find.byType(Card), findsOneWidget);
      // One divider between each adjacent pair (3 children → 2 dividers).
      expect(find.byType(Divider), findsNWidgets(2));
      expect(find.text('a'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('single child has no divider', (tester) async {
      await _pump(tester, const CruxSettingsCard(children: [Text('solo')]));
      expect(find.byType(Divider), findsNothing);
    });
  });

  group('CruxSettingsControlTile', () {
    testWidgets('stacks label, description, and control', (tester) async {
      await _pump(
        tester,
        const CruxSettingsControlTile(
          title: 'Theme',
          description: 'pick one',
          control: Text('CONTROL'),
        ),
      );
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('pick one'), findsOneWidget);
      expect(find.text('CONTROL'), findsOneWidget);
    });

    testWidgets('omits description when null', (tester) async {
      await _pump(
        tester,
        const CruxSettingsControlTile(title: 'Theme', control: Text('C')),
      );
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });
  });

  group('CruxSettingsSliderTile', () {
    testWidgets('renders a Slider with the value readout', (tester) async {
      var changed = 0.0;
      await _pump(
        tester,
        CruxSettingsSliderTile(
          title: 'Font size',
          description: 'in points',
          min: 8,
          max: 24,
          divisions: 16,
          value: 14,
          label: '14',
          valueText: '14',
          onChanged: (v) => changed = v,
        ),
      );
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('14'), findsWidgets);

      await tester.tap(find.byType(Slider));
      await tester.pump();
      expect(changed, isNot(0.0));
    });
  });
}
