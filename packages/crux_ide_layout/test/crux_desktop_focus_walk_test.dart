// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget modalHost() => _desktop(
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => showCruxErrorSnack(context, 'Port in use'),
                child: const Text('Fail'),
              ),
              ElevatedButton(
                onPressed: () => showCruxDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialogContext) => CruxDialog(
                    title: 'Export',
                    content: const Text('Writes the selection to a file.'),
                    actions: [
                      CruxDialogAction(
                        label: 'Retry',
                        onPressed: () => showCruxErrorSnack(
                          dialogContext,
                          'Disk full',
                        ),
                      ),
                      CruxDialogAction(
                        label: 'Done',
                        role: CruxDialogActionRole.primary,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('an error toast raised inside a dialog is a Tab stop inside '
      'the dialog, and is announced', (tester) async {
    final handle = tester.ensureSemantics();
    final announcements = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(modalHost());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Disk full'), findsOneWidget);
    expect(announcements.messages, contains('Disk full'));

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk);
    // Still modal: the page behind the dialog is never reached.
    expect(walk.transcript, isNot(contains('Fail button')));
    expect(walk.transcript, contains('Disk full'));
    expectFocusWalkGolden(walk, 'test/goldens/crux_toast_under_modal.txt');

    // Tab reaches the close button, and Enter on it closes the toast with
    // the dialog still open.
    final close = find.byKey(const ValueKey('cruxToastClose'));
    for (var i = 0; i < 6; i++) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused != null &&
          focused.findAncestorWidgetOfExactType<CruxToastCard>() != null) {
        break;
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(close, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Disk full'), findsNothing);
    expect(find.byType(CruxDialog), findsOneWidget);
    handle.dispose();
  });

  testWidgets('an error toast shown before a dialog opens joins the '
      "dialog's Tab order, and returns to the page's after it closes", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(modalHost());
    await tester.tap(find.text('Fail'));
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Port in use'), findsOneWidget);

    final underModal = await walkFocus(tester);
    expectCleanFocusWalk(underModal);
    expect(underModal.transcript, contains('Port in use'));
    expect(underModal.transcript, isNot(contains('Fail button')));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(CruxDialog), findsNothing);
    final onPage = await walkFocus(tester);
    expectCleanFocusWalk(onPage);
    expect(onPage.transcript, contains('Fail button'));
    expect(onPage.transcript, contains('Port in use'));
    handle.dispose();
  });
}
