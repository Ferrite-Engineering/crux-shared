// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<(String, String)> _presets = [
  ('default', 'Default'),
  ('emacs', 'Emacs'),
  ('gtkwave', 'GTKWave'),
  ('vim', 'Vim'),
  ('vscode', 'VS Code'),
];

class _Host extends StatefulWidget {
  const _Host({
    this.enabled = true,
    this.dense = false,
    this.initial = 'default',
    this.disabledItem,
  });

  final bool enabled;
  final bool dense;
  final String? initial;
  final String? disabledItem;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String? value = widget.initial;
  final List<String> changes = <String>[];

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5C6BC0),
        brightness: Brightness.dark,
      ),
      extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
    ),
    home: Scaffold(
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () {}, child: const Text('Before')),
            CruxPopUpButton<String>(
              key: const ValueKey('popUp'),
              semanticLabel: 'Keymap preset',
              placeholder: 'Choose',
              dense: widget.dense,
              items: [
                for (final (v, label) in _presets)
                  CruxPopUpItem(
                    value: v,
                    label: label,
                    enabled: v != widget.disabledItem,
                  ),
              ],
              value: value,
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

_HostState _state(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host));

final Finder _button = find.byKey(const ValueKey('popUp'));

Finder _item(String label) => find.ancestor(
  of: find.text(label).last,
  matching: find.byType(CruxPressable),
);

bool get _menuOpen =>
    find.byKey(const ValueKey('cruxPopUpItem-0')).evaluate().isNotEmpty;

String? _focusedLabel() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<CruxPressable>()
    ?.semanticLabel;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

Future<void> _focusButton(WidgetTester tester) async {
  await _key(tester, LogicalKeyboardKey.tab);
  await _key(tester, LogicalKeyboardKey.tab);
  expect(_focusedLabel(), 'Keymap preset');
}

void main() {
  testWidgets('it is 28 px tall, 24 px dense', (tester) async {
    await tester.pumpWidget(const _Host());
    expect(tester.getSize(_button).height, 28);
    await tester.pumpWidget(const _Host(dense: true));
    expect(tester.getSize(_button).height, 24);
  });

  testWidgets('it is as wide as its widest item, whatever is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    final width = tester.getSize(_button).width;
    await tester.pumpWidget(const _Host(initial: 'vscode'));
    expect(tester.getSize(_button).width, width);
  });

  testWidgets('the value is regular weight with one plain chevron', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    final text = tester.widget<Text>(
      find.descendant(of: _button, matching: find.text('Default')),
    );
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(
      find.descendant(of: _button, matching: find.byIcon(Icons.expand_more)),
      findsOneWidget,
    );
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  testWidgets('a click opens the menu; the chosen item has the check; a click '
      'on an item chooses it and closes', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(_button);
    await tester.pump();
    expect(_menuOpen, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('cruxPopUpItem-0')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tap(_item('Vim'));
    await tester.pump();
    expect(_menuOpen, isFalse);
    expect(_state(tester).value, 'vim');
  });

  testWidgets('choosing the item already chosen changes nothing', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await tester.tap(_button);
    await tester.pump();
    await tester.tap(_item('Default'));
    await tester.pump();
    expect(_state(tester).changes, isEmpty);
  });

  for (final (name, open) in [
    ('Space', [LogicalKeyboardKey.space]),
    ('Enter', [LogicalKeyboardKey.enter]),
    ('Alt+Down', [LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowDown]),
  ]) {
    testWidgets('$name opens it with focus on the chosen item', (
      tester,
    ) async {
      await tester.pumpWidget(const _Host(initial: 'gtkwave'));
      await _focusButton(tester);
      for (final key in open.take(open.length - 1)) {
        await tester.sendKeyDownEvent(key);
      }
      await _key(tester, open.last);
      for (final key in open.take(open.length - 1)) {
        await tester.sendKeyUpEvent(key);
      }
      expect(_menuOpen, isTrue);
      expect(_focusedLabel(), 'GTKWave');
    });
  }

  testWidgets('arrows move, Enter chooses, focus returns to the button', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await _focusButton(tester);
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedLabel(), 'Emacs');
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedLabel(), 'GTKWave');
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedLabel(), 'Emacs');
    await _key(tester, LogicalKeyboardKey.end);
    expect(_focusedLabel(), 'VS Code');
    await _key(tester, LogicalKeyboardKey.home);
    expect(_focusedLabel(), 'Default');
    await _key(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedLabel(), 'VS Code', reason: 'the arrows wrap in a menu');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_menuOpen, isFalse);
    expect(_state(tester).value, 'vscode');
    expect(_focusedLabel(), 'Keymap preset');
  });

  testWidgets('Escape closes it with nothing changed', (tester) async {
    await tester.pumpWidget(const _Host());
    await _focusButton(tester);
    await _key(tester, LogicalKeyboardKey.space);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.escape);
    expect(_menuOpen, isFalse);
    expect(_state(tester).changes, isEmpty);
    expect(_focusedLabel(), 'Keymap preset');
  });

  testWidgets('type-ahead jumps to the item a typed prefix starts', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host());
    await _focusButton(tester);
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.keyV);
    expect(_focusedLabel(), 'Vim');
    // The same letter again walks to the next item that starts with it.
    await _key(tester, LogicalKeyboardKey.keyV);
    expect(_focusedLabel(), 'VS Code');
    // After a pause a new prefix starts.
    await tester.pump(const Duration(seconds: 2));
    await _key(tester, LogicalKeyboardKey.keyG);
    expect(_focusedLabel(), 'GTKWave');
    await _key(tester, LogicalKeyboardKey.enter);
    expect(_state(tester).value, 'gtkwave');
  });

  testWidgets('a disabled item is skipped and cannot be chosen', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(disabledItem: 'emacs'));
    await _focusButton(tester);
    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedLabel(), 'GTKWave');
    await tester.tap(_item('Emacs'));
    await tester.pump();
    expect(_menuOpen, isTrue);
    expect(_state(tester).changes, isEmpty);
  });

  testWidgets('a disabled button does not open and is no Tab stop', (
    tester,
  ) async {
    await tester.pumpWidget(const _Host(enabled: false));
    await tester.tap(_button);
    await tester.pump();
    expect(_menuOpen, isFalse);
    await _key(tester, LogicalKeyboardKey.tab);
    await _key(tester, LogicalKeyboardKey.tab);
    expect(_focusedLabel(), isNull);
  });

  testWidgets('a value no item carries shows the placeholder', (tester) async {
    await tester.pumpWidget(const _Host(initial: null));
    expect(
      find.descendant(of: _button, matching: find.text('Choose')),
      findsOneWidget,
    );
  });

  testWidgets('keyboard focus draws the ring 2 px outside', (tester) async {
    await tester.pumpWidget(const _Host());
    CruxFocusRing ring() => tester.widget<CruxFocusRing>(
      find.descendant(of: _button, matching: find.byType(CruxFocusRing)),
    );
    expect(ring().focused, isFalse);
    await tester.tap(_button);
    await tester.pump();
    await _key(tester, LogicalKeyboardKey.escape);
    // A click never draws the ring.
    expect(ring().focused, isFalse);
    await _focusButton(tester);
    expect(ring().focused, isTrue);
    expect(ring().inset, isFalse);
    expect(ring().gap, 2);
  });

  testWidgets('a button with the value and the expanded state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    final button = find
        .descendant(of: _button, matching: find.byType(CruxPressable))
        .first;
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        label: 'Keymap preset',
        value: 'Default',
        isButton: true,
        hasExpandedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(_button);
    await tester.pump();
    // The chosen item takes focus on the frame after the menu opens.
    await tester.pump();
    expect(
      tester.getSemantics(button),
      matchesSemantics(
        label: 'Keymap preset',
        value: 'Default',
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(_item('Default')),
      matchesSemantics(
        label: 'Default',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('focus walk: the pop-up is one named button with its value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host());
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_pop_up_button.txt');
    handle.dispose();
  });

  testWidgets('focus lands on the chosen item, announced, when the menu '
      'opens', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const _Host(initial: 'vim'));
    await _focusButton(tester);
    await _key(tester, LogicalKeyboardKey.enter);
    expectFocusAnnounced(tester, named: 'Vim', context: 'menu opened');
    expect(describeFocus(tester).line, contains('selected'));
    handle.dispose();
  });

  group('CruxPopUpFormField', () {
    Widget form(GlobalKey<FormState> key, {ValueChanged<String>? onChanged}) =>
        MaterialApp(
          theme: ThemeData(
            extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
          ),
          home: Scaffold(
            body: Form(
              key: key,
              child: CruxPopUpFormField<String>(
                key: const ValueKey('field'),
                semanticLabel: 'Side',
                placeholder: 'Choose a side',
                items: const [
                  CruxPopUpItem(value: 'top', label: 'Top'),
                  CruxPopUpItem(value: 'left', label: 'Left'),
                ],
                onChanged: onChanged,
                validator: (v) => v == null ? 'Pick a side' : null,
              ),
            ),
          ),
        );

    testWidgets('validates, shows the error, and clears on a choice', (
      tester,
    ) async {
      final key = GlobalKey<FormState>();
      final changes = <String>[];
      await tester.pumpWidget(form(key, onChanged: changes.add));
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Pick a side'), findsOneWidget);
      expect(
        tester
            .widget<CruxPopUpButton<String>>(
              find.byType(CruxPopUpButton<String>),
            )
            .hasError,
        isTrue,
      );
      await tester.tap(find.byType(CruxPopUpButton<String>));
      await tester.pump();
      await tester.tap(find.text('Left').last);
      await tester.pump();
      expect(changes, ['left']);
      expect(key.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Pick a side'), findsNothing);
    });

    testWidgets('reset returns to the initial value', (tester) async {
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(form(key));
      await tester.tap(find.byType(CruxPopUpButton<String>));
      await tester.pump();
      await tester.tap(find.text('Top').last);
      await tester.pump();
      expect(
        tester
            .widget<CruxPopUpButton<String>>(
              find.byType(CruxPopUpButton<String>),
            )
            .value,
        'top',
      );
      key.currentState!.reset();
      await tester.pump();
      expect(
        tester
            .widget<CruxPopUpButton<String>>(
              find.byType(CruxPopUpButton<String>),
            )
            .value,
        isNull,
      );
    });
  });
}
