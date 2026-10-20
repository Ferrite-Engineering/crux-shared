// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a tab's provider scope: only what is built under the
/// nested navigator can see it.
class _TabScope extends InheritedWidget {
  const _TabScope({required this.name, required super.child});

  final String name;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TabScope>()?.name;

  @override
  bool updateShouldNotify(_TabScope oldWidget) => oldWidget.name != name;
}

void main() {
  testWidgets('a dialog given a navigator mounts under it and closes with '
      'Escape', (tester) async {
    final nested = GlobalKey<NavigatorState>();
    late BuildContext outside;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            outside = context;
            return Scaffold(
              body: _TabScope(
                name: 'tab-1',
                child: Navigator(
                  key: nested,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => const Text('tab content'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    String? seen = 'unset';
    final result = showCruxDialog<String>(
      context: outside,
      navigator: nested.currentState,
      barrierDismissible: false,
      builder: (dialogContext) {
        seen = _TabScope.of(dialogContext);
        return CruxDialog(
          title: 'Rename',
          content: const Text('Body'),
          actions: [
            CruxDialogAction(
              label: 'OK',
              role: CruxDialogActionRole.primary,
              onPressed: () => Navigator.of(dialogContext).pop('ok'),
            ),
          ],
        );
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(seen, 'tab-1');
    // The root navigator has nothing pushed; the nested one does.
    expect(Navigator.of(outside).canPop(), isFalse);
    expect(nested.currentState!.canPop(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    expect(await result, isNull);
  });

  testWidgets('without a navigator the dialog goes on the root navigator, '
      'outside the nested scope', (tester) async {
    late BuildContext inside;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _TabScope(
            name: 'tab-1',
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (context, _, _) {
                  inside = context;
                  return const Text('tab content');
                },
              ),
            ),
          ),
        ),
      ),
    );
    String? seen = 'unset';
    final result = showCruxDialog<void>(
      context: inside,
      builder: (dialogContext) {
        seen = _TabScope.of(dialogContext);
        return const CruxDialog(title: 'Root', content: Text('Body'));
      },
    );
    await tester.pumpAndSettle();
    expect(seen, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await result;
  });
}
