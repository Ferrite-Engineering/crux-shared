// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Calls {
  int reload = 0;
  int ignore = 0;
}

Widget _host(void Function(BuildContext) onPressed, {bool messenger = true}) {
  final body = Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        onPressed: () => onPressed(context),
        child: const Text('go'),
      ),
    ),
  );
  if (!messenger) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Material(child: body),
      ),
    );
  }
  return MaterialApp(home: Scaffold(body: body));
}

void Function(BuildContext) _show(_Calls calls, {String message = 'changed'}) =>
    (context) => showCruxReloadPrompt(
      context,
      message: message,
      reloadLabel: 'Reload',
      ignoreLabel: 'Ignore',
      onReload: () => calls.reload++,
      onIgnore: () => calls.ignore++,
    );

void main() {
  group('showCruxReloadPrompt', () {
    testWidgets('shows a banner with Ignore before the reload action', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_show(_Calls())));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);
      expect(find.text('changed'), findsOneWidget);
      final ignore = tester.getTopLeft(find.byKey(kCruxReloadPromptIgnoreKey));
      final reload = tester.getTopLeft(find.byKey(kCruxReloadPromptReloadKey));
      expect(ignore.dx, lessThan(reload.dx));
    });

    testWidgets('stays up: it has no timeout', (tester) async {
      await tester.pumpWidget(_host(_show(_Calls())));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);
    });

    testWidgets('Ignore hides it and runs onIgnore only', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(_host(_show(calls)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kCruxReloadPromptIgnoreKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
      expect(calls.ignore, 1);
      expect(calls.reload, 0);
    });

    testWidgets('the reload action hides it and runs onReload only', (
      tester,
    ) async {
      final calls = _Calls();
      await tester.pumpWidget(_host(_show(calls)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kCruxReloadPromptReloadKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
      expect(calls.reload, 1);
      expect(calls.ignore, 0);
    });

    testWidgets('a second change while it is up does not stack a banner', (
      tester,
    ) async {
      final calls = _Calls();
      await tester.pumpWidget(_host(_show(calls)));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);

      // One choice clears it; nothing was queued behind it.
      await tester.tap(find.byKey(kCruxReloadPromptIgnoreKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
      expect(calls.ignore, 1);
    });

    testWidgets('after a choice, the next change asks again', (tester) async {
      await tester.pumpWidget(_host(_show(_Calls())));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kCruxReloadPromptIgnoreKey));
      await tester.pumpAndSettle();

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsOneWidget);
    });

    testWidgets('speaks the message through the screen reader', (
      tester,
    ) async {
      final spoken = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
            message,
          ) async {
            final data = (message as Map<Object?, Object?>)['data'];
            if (data is Map<Object?, Object?>) {
              spoken.add('${data['message']}');
            }
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      await tester.pumpWidget(_host(_show(_Calls(), message: 'alu.v changed')));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(spoken, contains('alu.v changed'));
    });

    testWidgets('is a no-op without a ScaffoldMessenger', (tester) async {
      await tester.pumpWidget(_host(_show(_Calls()), messenger: false));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
    });
  });

  group('hideCruxReloadPrompt', () {
    testWidgets('hides the prompt without running either callback', (
      tester,
    ) async {
      final calls = _Calls();
      late BuildContext captured;
      await tester.pumpWidget(
        _host((context) {
          captured = context;
          _show(calls)(context);
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      hideCruxReloadPrompt(captured);
      await tester.pumpAndSettle();
      expect(find.byKey(kCruxReloadPromptKey), findsNothing);
      expect(calls.reload + calls.ignore, 0);
    });

    testWidgets('leaves a banner it did not show alone', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _host((context) {
          captured = context;
          ScaffoldMessenger.of(context).showMaterialBanner(
            const MaterialBanner(
              content: Text('someone else'),
              actions: <Widget>[SizedBox.shrink()],
            ),
          );
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      hideCruxReloadPrompt(captured);
      await tester.pumpAndSettle();
      expect(find.text('someone else'), findsOneWidget);
    });
  });
}
