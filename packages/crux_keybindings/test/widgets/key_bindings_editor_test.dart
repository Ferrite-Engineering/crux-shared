// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

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
  String get importLabel => 'Import…';
  @override
  String get exportLabel => 'Export…';
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

class _ConflictMessages implements KeyBindingsConflictMessages {
  @override
  String wins(String others) => 'Wins over $others';
  @override
  String shadowedBy(String winner) => 'Shadowed by $winner';
  @override
  String summary(int count) => '$count conflicts';
}

const _metrics = KeyBindingEditorMetrics(
  touchTarget: 44,
  iconSize: 24,
  bodyFontSize: 14,
  labelFontSize: 12,
  monoFontSize: 13,
);

const _defaults = <_Action, ShortcutActivator>{
  _Action.zoomIn: SingleActivator(LogicalKeyboardKey.equal, meta: true),
  _Action.zoomOut: SingleActivator(LogicalKeyboardKey.minus, meta: true),
  _Action.openFile: SingleActivator(LogicalKeyboardKey.keyO, meta: true),
};

void main() {
  Widget wrap(
    Widget child, {
    Map<_Action, ShortcutActivator> bindings = _defaults,
    Map<_Action, List<_Action>> conflicts = const {},
    Map<_Action, ShortcutConflictEntry<_Action>>? conflictDetails,
    void Function(_Action, KeyBinding)? onCapture,
    void Function(_Action)? onUnbind,
    void Function(_Action)? onReset,
    VoidCallback? onResetAll,
    VoidCallback? onImport,
    VoidCallback? onExport,
    ActionCategory Function(_Action)? categoryOf,
    String Function(_Action)? labelOf,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KeyBindingsEditor<_Action>(
            actions: _Action.values,
            categoryOf: categoryOf ?? (a) => a.category,
            categoryLabelOf: (c) => c.name,
            labelOf: labelOf ?? (a) => a.name,
            // The package takes the grouped-card surface as a builder rather
            // than depending on a settings-UI shell; a plain Column is
            // sufficient for these tests.
            categoryCardBuilder: (context, rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
            bindings: bindings,
            defaults: _defaults,
            conflicts: conflicts,
            conflictDetails: conflictDetails,
            conflictMessages: conflictDetails == null
                ? null
                : _ConflictMessages(),
            metrics: _metrics,
            strings: _Strings(),
            onCapture: onCapture ?? (_, _) {},
            onUnbind: onUnbind ?? (_) {},
            onReset: onReset ?? (_) {},
            onResetAll: onResetAll ?? () {},
            onImport: onImport ?? () {},
            onExport: onExport ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('renders rows grouped by category + the controls', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SizedBox()));
    expect(find.byType(KeyBindingRow), findsNWidgets(3));
    expect(find.text('Import…'), findsOneWidget);
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Reset all'), findsOneWidget);
    // Category headers (view + file).
    expect(find.text('view'), findsOneWidget);
    expect(find.text('file'), findsOneWidget);
  });

  testWidgets('Import / Export buttons fire their callbacks', (tester) async {
    var imported = false;
    var exported = false;
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        onImport: () => imported = true,
        onExport: () => exported = true,
      ),
    );
    await tester.tap(find.text('Import…'));
    await tester.tap(find.text('Export…'));
    expect(imported, isTrue);
    expect(exported, isTrue);
  });

  testWidgets('capturing a chord fires onCapture', (tester) async {
    _Action? capturedAction;
    KeyBinding? capturedBinding;
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        onCapture: (a, b) {
          capturedAction = a;
          capturedBinding = b;
        },
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(KeyBindingRow, 'zoomIn'),
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(capturedAction, _Action.zoomIn);
    expect(capturedBinding!.key, LogicalKeyboardKey.keyJ);
    expect(capturedBinding!.modifiers, {KeyModifier.mod});
  });

  testWidgets('renders a conflict warning from the conflicts map', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        conflicts: const {
          _Action.zoomIn: [_Action.zoomOut],
        },
      ),
    );
    expect(find.text('Also used by zoomOut'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets(
    'rich mode: shadowed row and winning row show asymmetric messages',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(),
          conflictDetails: const {
            // zoomOut wins the chord; zoomIn is shadowed by it.
            _Action.zoomIn: ShortcutConflictEntry(
              others: [_Action.zoomOut],
              winner: _Action.zoomOut,
            ),
            _Action.zoomOut: ShortcutConflictEntry(
              others: [_Action.zoomIn],
              winner: _Action.zoomOut,
            ),
          },
        ),
      );
      // Asymmetric: only the shadowed row says "Shadowed by"; the winner says
      // "Wins over". The old symmetric "Also used by" is not used.
      expect(find.text('Shadowed by zoomOut'), findsOneWidget);
      expect(find.text('Wins over zoomIn'), findsOneWidget);
      expect(find.textContaining('Also used by'), findsNothing);
      // The shadowed row uses the blocking error icon.
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    },
  );

  testWidgets('rich mode: summary banner shows the conflict count', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        conflictDetails: const {
          _Action.zoomIn: ShortcutConflictEntry(
            others: [_Action.zoomOut],
            winner: _Action.zoomOut,
          ),
          _Action.zoomOut: ShortcutConflictEntry(
            others: [_Action.zoomIn],
            winner: _Action.zoomOut,
          ),
        },
      ),
    );
    // One distinct chord in conflict.
    expect(find.text('1 conflicts'), findsOneWidget);
  });

  testWidgets('no summary banner when there are no conflicts', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        conflictDetails: const {},
      ),
    );
    expect(find.textContaining('conflicts'), findsNothing);
  });

  testWidgets('reset-all confirms then fires onResetAll', (tester) async {
    var reset = false;
    await tester.pumpWidget(
      wrap(const SizedBox(), onResetAll: () => reset = true),
    );

    await tester.tap(find.widgetWithText(TextButton, 'Reset all'));
    await tester.pumpAndSettle();
    expect(find.text('Reset all shortcuts?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reset all'));
    await tester.pumpAndSettle();
    expect(reset, isTrue);
  });

  testWidgets('reset-all cancel does not fire onResetAll', (tester) async {
    var reset = false;
    await tester.pumpWidget(
      wrap(const SizedBox(), onResetAll: () => reset = true),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Reset all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(reset, isFalse);
  });

  testWidgets('reset button shows only for customized rows', (tester) async {
    // All-default bindings: no reset buttons.
    await tester.pumpWidget(wrap(const SizedBox()));
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
    // (one for the Reset-all button only; per-row reset icons absent)

    // Customize zoomIn -> a per-row reset icon appears (2 total now).
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        bindings: {
          ..._defaults,
          _Action.zoomIn: const SingleActivator(
            LogicalKeyboardKey.keyJ,
            meta: true,
          ),
        },
      ),
    );
    expect(find.byIcon(Icons.settings_backup_restore), findsNWidgets(2));
  });

  testWidgets('entering capture mode does not re-derive the whole editor', (
    tester,
  ) async {
    // Entering capture mode changes the appearance of exactly one row. A
    // `setState` on the editor instead re-groups every action by category and
    // re-resolves every action label — work proportional to the full action
    // list (100+ rows in a real product) for a single-slot change.
    var categoryOfCalls = 0;
    var labelOfCalls = 0;
    await tester.pumpWidget(
      wrap(
        const SizedBox(),
        categoryOf: (a) {
          categoryOfCalls++;
          return a.category;
        },
        labelOf: (a) {
          labelOfCalls++;
          return a.name;
        },
      ),
    );
    await tester.pumpAndSettle();

    categoryOfCalls = 0;
    labelOfCalls = 0;

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(
      categoryOfCalls,
      0,
      reason: 'Capture mode must not re-group actions by category.',
    );
    expect(
      labelOfCalls,
      0,
      reason: 'Capture mode must not re-resolve every action label.',
    );

    // …and it still actually entered capture mode.
    expect(find.text('Press keys'), findsOneWidget);
  });

  test('the package does not depend on a settings-UI shell', () {
    // The keybindings *core* (binding model, codec, resolver) has no UI at
    // all, but a single card wrapper in the editor used to drag the whole
    // settings-UI package into every consumer of that core. The card surface
    // is now a builder parameter, so the edge must stay gone.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('crux_settings_ui'),
      isFalse,
      reason: 'crux_keybindings must not depend on crux_settings_ui.',
    );

    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f.readAsStringSync().contains(
            "import 'package:crux_settings_ui/",
          ),
        )
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
