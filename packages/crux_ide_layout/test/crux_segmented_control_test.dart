// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
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
    this.initial = 'wave',
    this.iconOnly = false,
  });

  final bool enabled;
  final bool dense;
  final Brightness brightness;
  final String? disabledSegment;

  /// The value selected at first; null selects nothing.
  final String? initial;

  /// Whether every segment draws only its icon.
  final bool iconOnly;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String? value = widget.initial;
  final List<String> changes = <String>[];

  /// Selects [v] from outside the control, as a model change would.
  void select(String v) => setState(() => value = v);

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
                    icon: widget.iconOnly ? Icons.circle : null,
                    iconOnly: widget.iconOnly,
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

class _IconHost extends StatefulWidget {
  const _IconHost({this.mixed = false});

  final bool mixed;

  @override
  State<_IconHost> createState() => _IconHostState();
}

class _IconHostState extends State<_IconHost> {
  String value = 'wave';

  @override
  Widget build(BuildContext context) => CruxSegmentedControl<String>(
    semanticLabel: 'View',
    segments: [
      const CruxSegment(
        value: 'wave',
        label: 'Wave',
        icon: Icons.show_chart,
        iconOnly: true,
      ),
      CruxSegment(
        value: 'table',
        label: 'Table',
        icon: Icons.table_chart,
        iconOnly: !widget.mixed,
      ),
      const CruxSegment(
        value: 'both',
        label: 'Both',
        icon: Icons.vertical_split,
        iconOnly: true,
      ),
    ],
    selected: value,
    onChanged: (v) => setState(() => value = v),
  );
}

_HostState _state(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

Finder _segment(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(CruxPressable));

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

  testWidgets('pressing darkens the selected segment in light', (tester) async {
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

  group('icon-only segments', () {
    Widget host({double? width, bool mixed = false}) => MaterialApp(
      theme: _theme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Row(
              children: [
                TextButton(onPressed: () {}, child: const Text('Before')),
                _IconHost(mixed: mixed),
                TextButton(onPressed: () {}, child: const Text('After')),
              ],
            ),
          ),
        ),
      ),
    );

    _IconHostState icons(WidgetTester tester) =>
        tester.state<_IconHostState>(find.byType(_IconHost));

    Finder seg(String label) => find.byWidgetPredicate(
      (w) => w is CruxPressable && w.semanticLabel == label,
    );

    testWidgets('three fit in 96 px, 28 px tall, no label drawn', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.dark),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 96, child: _IconHost()),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(CruxSegmentedControl<String>));
      expect(size.width, lessThanOrEqualTo(96));
      expect(size.height, 28);
      expect(find.text('Wave'), findsNothing);
      // Icon (16) plus 7 px each side.
      expect(tester.getSize(seg('Wave')).width, 30);
    });

    testWidgets('the semantic name is the label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      expect(
        tester.getSemantics(seg('Wave')),
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
      handle.dispose();
    });

    testWidgets('the label is the tooltip on hover', (tester) async {
      await tester.pumpWidget(host());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(seg('Table')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Table'), findsOneWidget);
      expect(find.byTooltip('Table'), findsOneWidget);
      await mouse.removePointer();
    });

    testWidgets('the label is the tooltip on keyboard focus', (tester) async {
      await tester.pumpWidget(host());
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_focusedLabel(), 'Wave');
      expect(find.text('Wave'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(_focusedLabel(), 'Table');
      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Wave'), findsNothing);
      await _key(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Table'), findsNothing);
    });

    testWidgets('arrows, Space and Enter work as for labelled segments', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_focusedLabel(), 'Table');
      await _key(tester, LogicalKeyboardKey.space);
      expect(icons(tester).value, 'table');
      await _key(tester, LogicalKeyboardKey.arrowRight);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(icons(tester).value, 'both');
      await tester.tap(seg('Wave'));
      await tester.pump();
      expect(icons(tester).value, 'wave');
    });

    testWidgets('a mixed control keeps labelled segments beside icon-only', (
      tester,
    ) async {
      await tester.pumpWidget(host(mixed: true));
      expect(find.text('Wave'), findsNothing);
      expect(find.text('Table'), findsOneWidget);
      expect(find.byIcon(Icons.table_chart), findsOneWidget);
      expect(find.byIcon(Icons.vertical_split), findsOneWidget);
    });

    testWidgets('focus walk: one stop, named segments', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops, hasLength(3));
      expectFocusWalkGolden(
        walk,
        'test/goldens/crux_segmented_control_icon_only.txt',
      );
      handle.dispose();
    });
  });

  group('Tab lands on the selected segment', () {
    for (final iconOnly in [false, true]) {
      final kind = iconOnly ? 'icon-only' : 'labelled';
      for (final (initial, label) in const [
        ('wave', 'Wave'),
        ('table', 'Table'),
        ('both', 'Both'),
      ]) {
        testWidgets('$kind, $label selected', (tester) async {
          await tester.pumpWidget(_Host(initial: initial, iconOnly: iconOnly));
          await _key(tester, LogicalKeyboardKey.tab);
          expect(_focusedLabel(), 'button');
          await _key(tester, LogicalKeyboardKey.tab);
          expect(_focusedLabel(), label);
          // One Tab stop: the next Tab leaves the group.
          await _key(tester, LogicalKeyboardKey.tab);
          expect(_focusedLabel(), 'button');
        });
      }

      testWidgets('$kind, nothing selected: the first segment', (tester) async {
        await tester.pumpWidget(_Host(initial: null, iconOnly: iconOnly));
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focusedLabel(), 'Wave');
      });

      testWidgets('$kind, nothing selected and the first disabled: the first '
          'enabled segment', (tester) async {
        await tester.pumpWidget(
          _Host(initial: null, iconOnly: iconOnly, disabledSegment: 'wave'),
        );
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focusedLabel(), 'Table');
      });

      testWidgets('$kind, the selected segment disabled: the first enabled '
          'one', (tester) async {
        await tester.pumpWidget(
          _Host(initial: 'table', iconOnly: iconOnly, disabledSegment: 'table'),
        );
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focusedLabel(), 'Wave');
      });

      testWidgets('$kind, Shift+Tab into the group also lands on the '
          'selected segment, and out returns to the previous control', (
        tester,
      ) async {
        await tester.pumpWidget(_Host(initial: 'table', iconOnly: iconOnly));
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focusedLabel(), 'button');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(_focusedLabel(), 'Table');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(_focusedLabel(), 'button');
      });

      testWidgets('$kind, after arrowing away and leaving, Tab returns to '
          'the selected segment', (tester) async {
        await tester.pumpWidget(_Host(initial: 'table', iconOnly: iconOnly));
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.tab);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(_focusedLabel(), 'Both');
        // Focus moved without selecting.
        expect(_state(tester).value, 'table');
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focusedLabel(), 'button');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(_focusedLabel(), 'Table');
      });
    }

    testWidgets('a selection made elsewhere moves the Tab stop', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host());
      _state(tester).select('both');
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.tab);
      expect(_focusedLabel(), 'Both');
    });

    testWidgets('focus walk: the second segment selected, one stop on it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const _Host(initial: 'table'));
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops, hasLength(3));
      expectFocusWalkGolden(
        walk,
        'test/goldens/crux_segmented_control_second_selected.txt',
      );
      handle.dispose();
    });

    testWidgets('focus walk: the last segment selected, icon-only', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const _Host(initial: 'both', iconOnly: true));
      final walk = await walkFocus(tester);
      expectCleanFocusWalk(walk);
      expect(walk.stops, hasLength(3));
      expectFocusWalkGolden(
        walk,
        'test/goldens/crux_segmented_control_last_selected_icon_only.txt',
      );
      handle.dispose();
    });
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
