// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Action implements CruxAction {
  zoomIn,
  zoomOut,
  openFile;

  @override
  String get id => 'test.$name';

  @override
  ActionCategory get category =>
      this == _Action.openFile ? ActionCategory.file : ActionCategory.view;
}

class _Strings implements KeyBindingsEditorStrings {
  @override
  String get description => 'Edit shortcuts.';
  @override
  String get phoneNote => 'Needs a keyboard.';
  @override
  String get importLabel => 'Import';
  @override
  String get exportLabel => 'Export';
  @override
  String get resetAllLabel => 'Reset all';
  @override
  String get notBound => '—';
  @override
  String get editTooltip => 'Change';
  @override
  String get unbindTooltip => 'Remove';
  @override
  String get resetTooltip => 'Reset';
  @override
  String get capturePrompt => 'Press keys';
  @override
  String conflict(String actions) => 'Also used by $actions';
  @override
  String get resetAllTitle => 'Reset all shortcuts?';
  @override
  String get resetAllBody => 'Everything returns to default.';
  @override
  String get resetAllCancel => 'Cancel';
}

class _A11yStrings implements KeyBindingsAccessibilityStrings {
  @override
  String get keyboardHint => 'Arrows move, Enter changes, Delete removes';
  @override
  String get notBoundSpoken => 'no shortcut';
}

const _defaults = <_Action, ShortcutActivator>{
  _Action.zoomIn: SingleActivator(LogicalKeyboardKey.equal, control: true),
  _Action.zoomOut: SingleActivator(LogicalKeyboardKey.minus, control: true),
  _Action.openFile: SingleActivator(LogicalKeyboardKey.keyO, control: true),
};

class _Recorder {
  final List<String> calls = <String>[];
}

Widget _editor(
  _Recorder recorder, {
  Map<_Action, ShortcutActivator> bindings = _defaults,
  KeyBindingsAccessibilityStrings? a11y,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: KeyBindingsEditor<_Action>(
        actions: _Action.values,
        categoryOf: (a) => a.category,
        categoryLabelOf: (c) => c.name,
        labelOf: (a) => a.name,
        categoryCardBuilder: (context, rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
        bindings: bindings,
        defaults: _defaults,
        conflicts: const {},
        metrics: const KeyBindingEditorMetrics(
          touchTarget: 44,
          iconSize: 24,
          bodyFontSize: 14,
          labelFontSize: 12,
          monoFontSize: 13,
        ),
        strings: _Strings(),
        accessibilityStrings: a11y,
        onCapture: (a, b) => recorder.calls.add('capture ${a.name}'),
        onUnbind: (a) => recorder.calls.add('unbind ${a.name}'),
        onReset: (a) => recorder.calls.add('reset ${a.name}'),
        onResetAll: () {},
        onImport: () {},
        onExport: () {},
      ),
    ),
  ),
);

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list is one Tab stop, and each row one named button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_editor(_Recorder()));

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.stops.map((s) => s.line), <String>[
      'Import button',
      'Export button',
      'Reset all button',
      'zoomIn, Control+Equals button',
    ]);
    handle.dispose();
  });

  testWidgets('arrow keys move between rows and carry the Tab stop', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_editor(_Recorder()));
    await walkFocus(tester, maxStops: 4);

    await _key(tester, LogicalKeyboardKey.arrowDown);
    expect(describeFocus(tester).name, 'zoomOut, Control+Minus');
    await _key(tester, LogicalKeyboardKey.end);
    expect(describeFocus(tester).name, 'openFile, Control+O');
    await _key(tester, LogicalKeyboardKey.home);
    await _key(tester, LogicalKeyboardKey.arrowDown);

    final walk = await walkFocus(tester);
    expect(walk.stops.map((s) => s.name), contains('zoomOut, Control+Minus'));
    expect(
      walk.stops.map((s) => s.name),
      isNot(contains('zoomIn, Control+Equals')),
    );
    handle.dispose();
  });

  testWidgets('Enter captures, and focus returns to the row afterwards', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final recorder = _Recorder();
    await tester.pumpWidget(_editor(recorder));
    await walkFocus(tester, maxStops: 4);

    await _key(tester, LogicalKeyboardKey.enter);
    expectFocusAnnounced(tester, named: 'Press keys');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(recorder.calls, <String>['capture zoomIn']);
    expectFocusAnnounced(tester, named: 'zoomIn');
    handle.dispose();
  });

  testWidgets('capture started with the pointer on a later row returns '
      'focus there and moves the Tab stop with it', (tester) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_editor(recorder));

    // The pointer path: no keyboard focus anywhere, edit a row that does not
    // hold the list's Tab stop.
    final edit = find.byIcon(Icons.edit_outlined).at(2);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(recorder.calls, <String>['capture openFile']);
    final handle = tester.ensureSemantics();
    await tester.pump();
    expectFocusAnnounced(tester, named: 'openFile');
    final walk = await walkFocus(tester);
    expect(
      walk.stops.where((s) => s.name.startsWith('zoomIn')),
      isEmpty,
      reason: 'the Tab stop moved to openFile',
    );
    handle.dispose();
  });

  testWidgets('Escape cancels capture and returns focus to the row', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final recorder = _Recorder();
    await tester.pumpWidget(_editor(recorder));
    await walkFocus(tester, maxStops: 4);

    await _key(tester, LogicalKeyboardKey.enter);
    await _key(tester, LogicalKeyboardKey.escape);

    expect(recorder.calls, isEmpty);
    expectFocusAnnounced(tester, named: 'zoomIn');
    handle.dispose();
  });

  testWidgets('Delete unbinds; Shift+Delete resets only a customised row', (
    tester,
  ) async {
    final recorder = _Recorder();
    await tester.pumpWidget(
      _editor(
        recorder,
        bindings: const <_Action, ShortcutActivator>{
          _Action.zoomIn: SingleActivator(LogicalKeyboardKey.keyK, alt: true),
          _Action.zoomOut: SingleActivator(
            LogicalKeyboardKey.minus,
            control: true,
          ),
        },
      ),
    );
    await walkFocus(tester, maxStops: 4);

    await _key(tester, LogicalKeyboardKey.delete, shift: true);
    await _key(tester, LogicalKeyboardKey.backspace);
    await _key(tester, LogicalKeyboardKey.arrowDown);
    await _key(tester, LogicalKeyboardKey.delete, shift: true);
    await _key(tester, LogicalKeyboardKey.end);
    await _key(tester, LogicalKeyboardKey.delete);

    // zoomIn is customised: reset and unbind both apply. zoomOut is at its
    // default, so Shift+Delete does nothing. openFile is unbound, so Delete
    // does nothing.
    expect(recorder.calls, <String>['reset zoomIn', 'unbind zoomIn']);
  });

  testWidgets('the hint is spoken on entry and an unbound row says so', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _editor(
        _Recorder(),
        bindings: const <_Action, ShortcutActivator>{},
        a11y: _A11yStrings(),
      ),
    );

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(
      walk.stops.last.line,
      '[Arrows move, Enter changes, Delete removes grouping] '
      'zoomIn, no shortcut button',
    );
    handle.dispose();
  });

  test('the spoken label uses words, never glyphs', () {
    expect(
      formatShortcutSpokenLabel(
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          control: true,
          shift: true,
        ),
      ),
      'Control+Shift+Left Arrow',
    );
    expect(
      formatShortcutSpokenLabel(null, emptyLabel: 'no shortcut'),
      'no shortcut',
    );
  });
}
