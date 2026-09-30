// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _metrics = KeyBindingEditorMetrics(
  touchTarget: 44,
  iconSize: 24,
  bodyFontSize: 14,
  labelFontSize: 12,
  monoFontSize: 13,
);

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  KeyBindingRow row({
    ShortcutActivator? activator = const SingleActivator(
      LogicalKeyboardKey.keyZ,
      meta: true,
    ),
    String? conflictMessage,
    bool isCustomized = false,
    VoidCallback? onEdit,
    VoidCallback? onUnbind,
    VoidCallback? onReset,
  }) => KeyBindingRow(
    label: 'Zoom In',
    activator: activator,
    metrics: _metrics,
    notBoundLabel: '—',
    conflictMessage: conflictMessage,
    isCustomized: isCustomized,
    editTooltip: 'Change',
    unbindTooltip: 'Remove',
    resetTooltip: 'Reset',
    onEdit: onEdit ?? () {},
    onUnbind: onUnbind ?? () {},
    onReset: onReset ?? () {},
  );

  testWidgets('shows the action label and edit button', (tester) async {
    await tester.pumpWidget(wrap(row()));
    expect(find.text('Zoom In'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('shows the not-bound placeholder and no unbind when unbound', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(row(activator: null)));
    expect(find.text('—'), findsOneWidget);
    expect(find.byIcon(Icons.backspace_outlined), findsNothing);
  });

  testWidgets('shows the reset button only when customized', (tester) async {
    await tester.pumpWidget(wrap(row()));
    expect(find.byIcon(Icons.settings_backup_restore), findsNothing);
    await tester.pumpWidget(wrap(row(isCustomized: true)));
    expect(find.byIcon(Icons.settings_backup_restore), findsOneWidget);
  });

  testWidgets('renders a conflict warning when provided', (tester) async {
    await tester.pumpWidget(
      wrap(row(conflictMessage: 'Also used by Pan Left')),
    );
    expect(find.text('Also used by Pan Left'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('buttons invoke their callbacks', (tester) async {
    var edited = false;
    var unbound = false;
    var reset = false;
    await tester.pumpWidget(
      wrap(
        row(
          isCustomized: true,
          onEdit: () => edited = true,
          onUnbind: () => unbound = true,
          onReset: () => reset = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.tap(find.byIcon(Icons.settings_backup_restore));
    expect(edited, isTrue);
    expect(unbound, isTrue);
    expect(reset, isTrue);
  });

  testWidgets('renders the capture field in place of chip + buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        KeyBindingRow(
          label: 'Zoom In',
          activator: const SingleActivator(LogicalKeyboardKey.keyZ),
          metrics: _metrics,
          notBoundLabel: '—',
          conflictMessage: null,
          isCustomized: false,
          editTooltip: 'Change',
          unbindTooltip: 'Remove',
          resetTooltip: 'Reset',
          onEdit: () {},
          onUnbind: () {},
          onReset: () {},
          captureField: const Text('CAPTURING'),
        ),
      ),
    );
    expect(find.text('CAPTURING'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('icon buttons meet the touch-target floor', (tester) async {
    await tester.pumpWidget(wrap(row()));
    final size = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.edit_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
