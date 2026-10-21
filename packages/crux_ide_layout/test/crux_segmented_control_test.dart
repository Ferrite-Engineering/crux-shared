// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF5C6BC0),
    brightness: brightness,
  ),
  extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
);

class _Host extends StatefulWidget {
  const _Host({
    this.enabled = true,
    this.dense = false,
    this.brightness = Brightness.dark,
    this.disabledSegment,
  });

  final bool enabled;
  final bool dense;
  final Brightness brightness;
  final String? disabledSegment;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String value = 'wave';
  final List<String> changes = <String>[];

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _theme(widget.brightness),
    home: Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            CruxSegmentedControl<String>(
              semanticLabel: 'View',
              dense: widget.dense,
              segments: [
                for (final (v, label) in const [
                  ('wave', 'Wave'),
                  ('table', 'Table'),
                  ('both', 'Both'),
                ])
                  CruxSegment(
                    value: v,
                    label: label,
                    enabled: v != widget.disabledSegment,
                  ),
              ],
              selected: value,
              onChanged: widget.enabled
                  ? (v) => setState(() {
                      value = v;
                      changes.add(v);
                    })
                  : null,
            ),
            TextButton(onPressed: () {}, child: const Text('After')),
          ],
        ),
      ),
    ),
  );
}

_HostState _state(WidgetTester tester) => tester.state<_HostState>(
  find.byType(_Host),
);

Finder _segment(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CruxPressable),
);

String? _focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  final pressable = context?.findAncestorWidgetOfExactType<CruxPressable>();
  if (pressable != null) return pressable.semanticLabel;
  return context?.findAncestorWidgetOfExactType<TextButton>() == null
      ? null
      : 'button';
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  testWidgets('it is 28 px tall, 24 px dense', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(
      tester.getSize(find.byType(CruxSegmentedControl<String>)).height,
      28,
    );
    await tester.pumpWidget(const _Host(dense: true));
    expect(
      tester.getSize(find.byType(CruxSegmentedControl<String>)).height,
      24,
    );
  });

  testWidgets('a click selects; the selected segment again changes nothing', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(find.text('Table'));
    await tester.pump();
    expect(_state(tester).value, 'table');
    await tester.tap(find.text('Table'));
    await tester.pump();
    expect(_state(tester).changes, ['table']);
  });

  testWidgets('no check glyph, no Material SegmentedButton', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
  });

  testWidgets('one Tab stop on the selected segment; arrows move, Space and '
      'Enter select', (tester) async {
    await tester.pumpWidget(const _Host());
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focusedLabel(), 'button');
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focusedLabel(), 'Wave');

    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Table');
    // Moving focus does not select.
    expect(_state(tester).value, 'wave');
    await _key(tester, LogicalKeyboardKey.space);
    expect(_state(tester).value, 'table');

    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Both');
    // The arrow stops at the end rather than leaving the group.
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Both');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_state(tester).value, 'both');

    await _key(tester, LogicalKeyboardKey.home);
    expect(_focusedLabel(), 'Wave');
    await _key(tester, LogicalKeyboardKey.end);
    expect(_focusedLabel(), 'Both');

    // Tab leaves the group in one step.
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focusedLabel(), 'button');
  });

  testWidgets('a disabled segment is skipped and cannot be chosen', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(disabledSegment: 'table'));
    await tester.tap(find.text('Table'));
    await tester.pump();
    expect(_state(tester).value, 'wave');
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedLabel(), 'Both');
  });

  testWidgets('a disabled control is no Tab stop and ignores clicks', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(enabled: false));
    await tester.tap(find.text('Both'));
    await tester.pump();
    expect(_state(tester).value, 'wave');
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focusedLabel(), 'button');
  });

  testWidgets('the ring is drawn around the focused segment only, inside it', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.arrowRight);
    final rings = tester
        .widgetList<CruxFocusRing>(find.byType(CruxFocusRing))
        .toList();
    expect(rings.where((r) => r.focused), hasLength(1));
    final focused = find.ancestor(
      of: find.text('Table'),
      matching: find.byType(CruxFocusRing),
    );
    final ring = tester.widget<CruxFocusRing>(focused);
    expect(ring.focused, isTrue);
    expect(ring.inset, isTrue);
    // Inside its own bounds, so the neighbours are untouched.
    final size = tester.getSize(focused);
    final paint = CruxFocusRingPainter(
      color: Colors.blue,
      radius: ring.radius,
      width: 1.5,
      inset: true,
    );
    final outer = paint.ringFor(size).outerRect.inflate(0.75);
    expect((Offset.zero & size).intersect(outer), outer);
  });

  testWidgets('the selected segment stands clear of the face in light', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(brightness: Brightness.light));
    Color faceOf(String label) {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    final selected = faceOf('Wave');
    final other = faceOf('Table');
    expect(
      (other.computeLuminance() - selected.computeLuminance()).abs(),
      greaterThan(0.25),
    );
  });

  testWidgets('pressing darkens the selected segment in light', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(brightness: Brightness.light));
    Color face() {
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('Wave'), matching: find.byType(Container))
            .first,
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    final rest = face();
    final gesture = await tester.startGesture(
      tester.getCenter(_segment('Wave')),
    );
    await tester.pump();
    expect(face().computeLuminance(), lessThan(rest.computeLuminance()));
    await gesture.up();
  });

  testWidgets('one group named by its label; each segment a button with a '
      'selected state', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    expect(
      tester.getSemantics(_segment('Wave')),
      matchesSemantics(
        label: 'Wave',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(_segment('Table')),
      matchesSemantics(
        label: 'Table',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('focus walk: one stop, inside the named group', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(walk.stops, hasLength(3));
    expectFocusWalkGolden(walk, 'test/goldens/crux_segmented_control.txt');
    handle.dispose();
  });
}
