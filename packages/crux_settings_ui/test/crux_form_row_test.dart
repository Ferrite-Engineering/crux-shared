// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show CruxDesktopTokens;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A form with every kind of row: a field, a dropdown, a switch and a
/// checkbox.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  bool reload = true;
  bool snap = false;
  String colour = 'Amber';

  @override
  Widget build(BuildContext context) => CruxFormSection(
    title: 'Marker',
    children: [
      const CruxFormRow(
        label: 'Name',
        help: 'Shown on the time ruler.',
        child: SizedBox(width: 200, child: TextField()),
      ),
      CruxFormRow(
        label: 'Colour',
        child: DropdownButton<String>(
          value: colour,
          isDense: true,
          onChanged: (v) => setState(() => colour = v ?? colour),
          items: const [
            DropdownMenuItem(value: 'Amber', child: Text('Amber')),
            DropdownMenuItem(value: 'Teal', child: Text('Teal')),
          ],
        ),
      ),
      CruxFormRow.toggle(
        key: const Key('reload'),
        label: 'Reload on change',
        value: reload,
        onChanged: (v) => setState(() => reload = v),
      ),
      CruxFormRow.checkbox(
        key: const Key('snap'),
        label: 'Snap to nearest edge',
        value: snap,
        onChanged: (v) => setState(() => snap = v),
      ),
    ],
  );
}

Widget _app(Widget child, {bool desktop = true}) => MaterialApp(
  theme: ThemeData(
    extensions: desktop
        ? const <ThemeExtension<dynamic>>[CruxDesktopTokens()]
        : const <ThemeExtension<dynamic>>[],
  ),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(width: 520, child: child),
    ),
  ),
);

void main() {
  testWidgets('labels sit in one column to the left of their controls', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Form()));
    final name = tester.getTopLeft(find.text('Name'));
    final colour = tester.getTopLeft(find.text('Colour'));
    expect(name.dx, colour.dx);
    final field = tester.getTopLeft(find.byType(TextField));
    expect(field.dx, name.dx + kCruxFormLabelWidth);
    expect(field.dy, lessThan(tester.getBottomLeft(find.text('Name')).dy));
  });

  testWidgets('a desktop toggle row uses CruxSwitch', (tester) async {
    await tester.pumpWidget(_app(const _Form()));
    expect(find.byType(CruxSwitch), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a phone toggle row keeps the Material switch, stacked', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Form(), desktop: false));
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(CruxSwitch), findsNothing);
    final label = tester.getBottomLeft(find.text('Name'));
    final field = tester.getTopLeft(find.byType(TextField));
    expect(field.dy, greaterThanOrEqualTo(label.dy));
  });

  testWidgets('the label toggles a switch and a checkbox', (tester) async {
    await tester.pumpWidget(_app(const _Form()));
    await tester.tap(find.text('Reload on change'));
    await tester.pump();
    expect(
      tester.widget<CruxFormRow>(find.byKey(const Key('reload'))).value,
      isFalse,
    );
    await tester.tap(find.text('Snap to nearest edge'));
    await tester.pump();
    expect(
      tester.widget<CruxFormRow>(find.byKey(const Key('snap'))).value,
      isTrue,
    );
  });

  testWidgets('the label is the control accessible name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Form()));
    expect(
      tester.getSemantics(find.byKey(const Key('reload'))),
      matchesSemantics(
        label: 'Reload on change',
        hasToggledState: true,
        isToggled: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('snap'))),
      matchesSemantics(
        label: 'Snap to nearest edge',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a disabled toggle greys its label and ignores clicks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const CruxFormRow.toggle(
          label: 'Broadcast',
          value: false,
          onChanged: null,
          help: 'Needs the server on.',
        ),
      ),
    );
    await tester.tap(find.text('Broadcast'), warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<CruxSwitch>(find.byType(CruxSwitch)).value, isFalse);
    final label = tester.widget<Text>(find.text('Broadcast'));
    expect(label.style?.color?.a, lessThan(0.5));
    expect(find.text('Needs the server on.'), findsOneWidget);
  });

  testWidgets('a Settings row spreads label and control apart', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const CruxSettingsControlTile(
          title: 'Language',
          description: 'Applies immediately',
          control: SizedBox(width: 120, height: 28),
        ),
      ),
    );
    final label = tester.getTopLeft(find.text('Language'));
    final control = tester.getTopRight(
      find.byWidgetPredicate((w) => w is SizedBox && w.width == 120),
    );
    expect(label.dx, lessThan(100));
    expect(control.dx, greaterThan(400));
  });

  testWidgets('focus walk: field, dropdown, switch, checkbox', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const _Form()));
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_form_section.txt');
    handle.dispose();
  });
}
