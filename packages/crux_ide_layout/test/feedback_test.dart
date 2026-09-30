// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _snackHost(void Function(BuildContext) onPressed) {
  return MaterialApp(
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

void main() {
  group('showCruxInfoSnack', () {
    testWidgets('shows a floating snack with the 4 s standard duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _snackHost((context) => showCruxInfoSnack(context, 'saved')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('saved'), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(snack.duration, kCruxInfoSnackDuration);
      expect(kCruxInfoSnackDuration, const Duration(seconds: 4));
    });

    testWidgets('is a no-op without a ScaffoldMessenger', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              showCruxInfoSnack(context, 'nobody hears this');
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('showCruxErrorSnack', () {
    testWidgets('shows a floating error snack with the 6 s duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _snackHost((context) => showCruxErrorSnack(context, 'load failed')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.text('load failed'), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.behavior, SnackBarBehavior.floating);
      expect(snack.duration, kCruxErrorSnackDuration);
      expect(kCruxErrorSnackDuration, const Duration(seconds: 6));
    });

    testWidgets('uses the error-container palette', (tester) async {
      await tester.pumpWidget(
        _snackHost((context) => showCruxErrorSnack(context, 'load failed')),
      );
      final colorScheme = Theme.of(
        tester.element(find.text('go')),
      ).colorScheme;
      await tester.tap(find.text('go'));
      await tester.pump();

      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, colorScheme.errorContainer);
    });
  });

  group('confirmCruxDestructiveAction', () {
    Widget host(void Function({required bool confirmed}) onResult) {
      return _snackHost((context) async {
        final ok = await confirmCruxDestructiveAction(
          context,
          title: 'Delete workspace?',
          body: 'This cannot be undone.',
          confirmLabel: 'Delete',
          cancelLabel: 'Cancel',
        );
        onResult(confirmed: ok);
      });
    }

    testWidgets('renders title, body and both buttons', (tester) async {
      await tester.pumpWidget(host(({required confirmed}) {}));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Delete workspace?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('cancel sits left of the destructive confirm', (tester) async {
      await tester.pumpWidget(host(({required confirmed}) {}));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final cancelX = tester.getCenter(find.text('Cancel')).dx;
      final confirmX = tester.getCenter(find.text('Delete')).dx;
      expect(cancelX, lessThan(confirmX));
    });

    testWidgets('the confirm button is destructive-styled', (tester) async {
      await tester.pumpWidget(host(({required confirmed}) {}));
      final colorScheme = Theme.of(
        tester.element(find.text('go')),
      ).colorScheme;
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        button.style?.backgroundColor?.resolve(const <WidgetState>{}),
        colorScheme.error,
      );
    });

    testWidgets('confirm resolves true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(({required confirmed}) => result = confirmed),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancel resolves false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(({required confirmed}) => result = confirmed),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('barrier dismissal resolves false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(({required confirmed}) => result = confirmed),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Tap outside the dialog.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
