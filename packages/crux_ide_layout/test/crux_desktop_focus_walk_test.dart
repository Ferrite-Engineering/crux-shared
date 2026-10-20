// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a desktop screen reader hears walking the Crux Desktop dialog and
/// the toast stack, pinned as transcripts. Text, not pixels: they do not
/// depend on the renderer.
Widget _desktop(Widget home) => MaterialApp(
  theme: ThemeData(
    extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
  ),
  home: home,
);

void main() {
  testWidgets('CruxDialog: focus opens on the first control, Tab stays '
      'inside', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _desktop(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCruxDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => CruxDialog(
                    title: 'Add Marker',
                    content: const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Places a named marker at the cursor.'),
                        SizedBox(height: 8),
                        TextField(
                          decoration: InputDecoration(hintText: 'Name'),
                        ),
                      ],
                    ),
                    actions: [
                      CruxDialogAction(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                      CruxDialogAction(
                        label: 'Add',
                        role: CruxDialogActionRole.primary,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expectFocusAnnounced(tester, context: 'dialog opened');

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expect(walk.transcript, isNot(contains('Open button')));
    expectFocusWalkGolden(walk, 'test/goldens/crux_dialog.txt');
    handle.dispose();
  });

  testWidgets('a toast never takes focus; an error toast close is a Tab '
      'stop named by its message', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _desktop(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () => showCruxInfoSnack(context, 'Exported'),
                    child: const Text('Export'),
                  ),
                  ElevatedButton(
                    onPressed: () => showCruxErrorSnack(context, 'No file'),
                    child: const Text('Open file'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.tap(find.text('Open file'));
    await tester.pump();
    expect(find.text('No file'), findsOneWidget);
    // Showing the toast moved no focus into it.
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      focused?.findAncestorWidgetOfExactType<CruxToastCard>(),
      isNull,
    );

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    expectFocusWalkGolden(walk, 'test/goldens/crux_toast_stack.txt');
    handle.dispose();
  });
}
