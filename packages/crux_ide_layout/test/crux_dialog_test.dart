// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _desktop = CruxDesktopTokens();

/// A desktop host whose button opens [open].
Widget _host(void Function(BuildContext context) open) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[_desktop],
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Widget _confirm(BuildContext context, {VoidCallback? onSubmit}) => CruxDialog(
  title: 'Rename marker',
  onSubmit: onSubmit,
  content: const Text('Give the marker a name.'),
  actions: [
    CruxDialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(false),
    ),
    CruxDialogAction(
      label: 'Rename',
      role: CruxDialogActionRole.primary,
      onPressed: () => Navigator.of(context).pop(true),
    ),
  ],
);

void main() {
  setUp(ModalGuard.reset);

  group('showCruxDialog', () {
    testWidgets('Escape closes a non-dismissible dialog', (tester) async {
      bool? result = true;
      await tester.pumpWidget(
        _host((context) async {
          result = await showCruxDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: _confirm,
          );
        }),
      );
      await _open(tester);
      expect(find.byType(CruxDialog), findsOneWidget);

      // A scrim click does nothing.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(CruxDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CruxDialog), findsNothing);
      expect(result, isNull);
    });

    testWidgets('a dismissible dialog closes on a scrim click', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<bool>(
            context: context,
            builder: _confirm,
          ),
        ),
      );
      await _open(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(CruxDialog), findsNothing);
    });

    testWidgets('modalGuardKey suppresses a second copy while one is open', (
      tester,
    ) async {
      var opened = 0;
      late BuildContext host;
      await tester.pumpWidget(
        _host((context) {
          host = context;
          opened++;
          unawaited(
            showCruxDialog<void>(
              context: context,
              modalGuardKey: 'rename',
              builder: _confirm,
            ),
          );
        }),
      );
      await _open(tester);
      expect(ModalGuard.isOpen('rename'), isTrue);

      Object? second = 'pending';
      second = await showCruxDialog<bool>(
        context: host,
        modalGuardKey: 'rename',
        builder: _confirm,
      );
      await tester.pumpAndSettle();
      expect(second, isNull, reason: 'a suppressed call resolves null');
      expect(find.byType(CruxDialog), findsOneWidget);
      expect(opened, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(ModalGuard.isOpen('rename'), isFalse);
    });

    testWidgets('the scrim is the theme dialog barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            dialogTheme: DialogThemeData(
              barrierColor: Colors.black.withValues(alpha: 0.18),
            ),
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    showCruxDialog<void>(context: context, builder: _confirm),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await _open(tester);
      final barrier = tester.widget<ModalBarrier>(
        find.byType(ModalBarrier).last,
      );
      expect(barrier.color, Colors.black.withValues(alpha: 0.18));
    });
  });

  group('CruxDialog', () {
    testWidgets('focus moves to the first control when it opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<bool>(
            context: context,
            builder: _confirm,
          ),
        ),
      );
      await _open(tester);
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.widget),
          matching: find.widgetWithText(OutlinedButton, 'Cancel'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Enter runs the default action, but not on a button', (
      tester,
    ) async {
      var submitted = 0;
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<bool>(
            context: context,
            builder: (c) => CruxDialog(
              title: 'Rename marker',
              onSubmit: () => submitted++,
              content: const TextField(key: Key('name')),
              actions: [
                CruxDialogAction(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(c).pop(),
                ),
              ],
            ),
          ),
        ),
      );
      await _open(tester);

      // Focus opened on the field; Enter there submits.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submitted, 1);

      // On Cancel, Enter activates Cancel instead.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(submitted, 1);
      expect(find.byType(CruxDialog), findsNothing);
    });

    testWidgets('Enter in a multi-line field is a newline', (tester) async {
      var submitted = 0;
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<void>(
            context: context,
            builder: (c) => CruxDialog(
              title: 'Note',
              onSubmit: () => submitted++,
              content: const TextField(maxLines: 4),
            ),
          ),
        ),
      );
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(submitted, 0);
    });

    testWidgets('the destructive variant keeps focus on the safe action', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        _host((context) async {
          result = await confirmCruxDestructiveAction(
            context,
            title: 'Delete workspace?',
            body: 'This cannot be undone.',
            confirmLabel: 'Delete',
            cancelLabel: 'Cancel',
          );
        }),
      );
      await _open(tester);
      final colorScheme = Theme.of(
        tester.element(find.text('Delete')),
      ).colorScheme;
      final delete = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        delete.style?.backgroundColor?.resolve(const <WidgetState>{}),
        colorScheme.error,
      );
      // Enter on arrival cancels.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('the size is clamped to the window less its gutter', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(600, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<void>(
            context: context,
            builder: (c) => const CruxDialog(
              title: 'Wide',
              width: 900,
              content: SizedBox(height: 2000, child: Placeholder()),
            ),
          ),
        ),
      );
      await _open(tester);
      expect(tester.takeException(), isNull);
      final frame = tester.getSize(
        find
            .descendant(
              of: find.byType(CruxDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(frame.width, lessThanOrEqualTo(600 - 2 * kCruxDialogGutter));
      expect(frame.height, lessThanOrEqualTo(400 - 2 * kCruxDialogGutter));
    });

    testWidgets('the dialog is one container named by its title', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          (context) => showCruxDialog<bool>(
            context: context,
            builder: _confirm,
          ),
        ),
      );
      await _open(tester);
      expect(
        find.bySemanticsLabel('Rename marker'),
        findsOneWidget,
      );
      expectFocusAnnounced(tester, named: 'Cancel', context: 'dialog opened');
      handle.dispose();
    });
  });
}
