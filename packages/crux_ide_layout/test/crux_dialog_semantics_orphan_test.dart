// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop accessibility bridge rejects an update that serializes a node
/// nobody claims, and stops following the app after the first one. Opening a
/// CruxDialog, typing in it, raising a toast from it and closing it must
/// never produce one.
void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  testWidgets('a CruxDialog and its toast serialize no orphan node', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showCruxDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => CruxDialog(
                    title: 'Rename',
                    onSubmit: () {
                      Navigator.of(dialogContext).pop();
                      showCruxErrorSnack(dialogContext, 'Name taken');
                    },
                    content: const TextField(key: Key('name')),
                    actions: [
                      CruxDialogAction(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name')), 'clk');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Name taken'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cruxToastClose')));
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'CruxDialog and toast');
    expect(SemanticsOrphanGuard.instance.updates, greaterThan(1));
  });

  testWidgets('a non-blocking CruxDialog serializes no orphan node', (
    tester,
  ) async {
    SemanticsOrphanGuard.instance.reset();
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => showCruxDialog<void>(
                  context: context,
                  blocking: false,
                  builder: (dialogContext) => const CruxDialog(
                    title: 'Stats',
                    content: Text('42 nodes'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.text('42 nodes'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    handle.dispose();
    SemanticsOrphanGuard.instance.check(context: 'non-blocking CruxDialog');
    expect(SemanticsOrphanGuard.instance.updates, greaterThan(1));
  });
}
