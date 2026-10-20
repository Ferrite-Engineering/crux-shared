// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A desktop host: the theme carries the Crux Desktop tokens.
Widget _desktopHost(void Function(BuildContext) onPressed) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

Finder get _toast => find.byType(CruxToastCard);

void main() {
  group('desktop toasts', () {
    testWidgets('an info toast sits bottom-right above the status bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _desktopHost((context) => showCruxInfoSnack(context, 'Saved')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(_toast, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final window = tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = tester.getRect(_toast);
      expect(rect.right, window.width - 16);
      expect(
        rect.bottom,
        window.height - const CruxDesktopTokens().toastBottomInset,
      );
      expect(
        rect.width,
        lessThanOrEqualTo(const CruxDesktopTokens().toastMaxWidth),
      );
      await tester.pump(kCruxInfoSnackDuration);
    });

    testWidgets('an info toast leaves after the standard duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _desktopHost((context) => showCruxInfoSnack(context, 'Saved')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(_toast, findsOneWidget);

      await tester.pump(kCruxInfoSnackDuration - const Duration(seconds: 1));
      expect(_toast, findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(_toast, findsNothing);
    });

    testWidgets('one is visible at a time: the newest replaces it', (
      tester,
    ) async {
      var n = 0;
      await tester.pumpWidget(
        _desktopHost((context) => showCruxInfoSnack(context, 'Message ${++n}')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(_toast, findsOneWidget);
      expect(find.text('Message 1'), findsNothing);
      expect(find.text('Message 2'), findsOneWidget);
      await tester.pump(kCruxInfoSnackDuration);
    });

    testWidgets('an error toast stays until it is closed', (tester) async {
      await tester.pumpWidget(
        _desktopHost((context) => showCruxErrorSnack(context, 'Load failed')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();

      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Load failed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cruxToastClose')));
      await tester.pump();
      expect(_toast, findsNothing);
    });

    testWidgets('a toast is announced, politely for info and assertively '
        'for an error', (tester) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        _desktopHost((context) {
          showCruxInfoSnack(context, 'Saved');
          showCruxErrorSnack(context, 'Load failed');
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(recorder.messages, containsAllInOrder(['Saved', 'Load failed']));
    });

    testWidgets('hideCruxSnack removes the toast showing', (tester) async {
      late BuildContext host;
      await tester.pumpWidget(
        _desktopHost((context) {
          host = context;
          showCruxErrorSnack(context, 'Checking');
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(_toast, findsOneWidget);
      hideCruxSnack(host);
      await tester.pump();
      expect(_toast, findsNothing);
    });

    testWidgets('a key reaches the toast', (tester) async {
      await tester.pumpWidget(
        _desktopHost(
          (context) => showCruxErrorSnack(
            context,
            'Send failed',
            key: const Key('send_failure'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byKey(const Key('send_failure')), findsOneWidget);
    });

    testWidgets('a toast outlives the dialog that raised it', (tester) async {
      await tester.pumpWidget(
        _desktopHost(
          (context) => showCruxDialog<void>(
            context: context,
            builder: (dialogContext) => CruxDialog(
              title: 'Export',
              content: const Text('Export the table?'),
              actions: [
                CruxDialogAction(
                  label: 'Export',
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    showCruxInfoSnack(dialogContext, 'Exported');
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export').last);
      await tester.pumpAndSettle();
      expect(find.byType(CruxDialog), findsNothing);
      expect(find.text('Exported'), findsOneWidget);
      await tester.pump(kCruxInfoSnackDuration);
    });
  });

  group('phone and tablet', () {
    testWidgets('without the desktop tokens it is a Material snack bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCruxInfoSnack(context, 'Saved'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_toast, findsNothing);
    });
  });
}
