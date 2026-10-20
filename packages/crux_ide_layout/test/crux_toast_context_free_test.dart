// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_ide_layout/src/crux_toast.dart' show registerCruxToastHost;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Layout implements IdePanelLayout {
  @override
  bool leftVisible = false;
  @override
  bool rightVisible = false;
  @override
  bool bottomVisible = false;
  @override
  PaneSize? leftSize;
  @override
  PaneSize? rightSize;
  @override
  PaneSize? bottomSize;
}

class _Sink implements IdePanelLayoutSink {
  @override
  void setLeftVisible({required bool visible}) {}
  @override
  void setRightVisible({required bool visible}) {}
  @override
  void setBottomVisible({required bool visible}) {}
  @override
  void setLeftSize(double pixels) {}
  @override
  void setRightSize(double pixels) {}
  @override
  void setBottomSize(double pixels) {}
}

/// Registers its overlay as a toast host, as the window chrome does.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    _release = registerCruxToastHost(context);
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Widget _app(Widget home, {bool desktop = true}) => MaterialApp(
  theme: ThemeData(
    extensions: <ThemeExtension<dynamic>>[
      if (desktop) const CruxDesktopTokens(),
    ],
  ),
  home: Scaffold(body: home),
);

void main() {
  testWidgets('shown with no BuildContext, with the same announcement', (
    tester,
  ) async {
    final announced = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(_app(const _Host()));
    expect(CruxToasts.showInfo('Saved.'), isTrue);
    await tester.pump();
    expect(find.text('Saved.'), findsOneWidget);
    expect(announced.messages, contains('Saved.'));
    await tester.pump(kCruxInfoSnackDuration + const Duration(seconds: 1));
    expect(find.text('Saved.'), findsNothing);
  });

  testWidgets('the newest toast replaces the one showing; an error stays '
      'and is announced', (tester) async {
    final announced = AnnouncementRecorder.attach(tester);
    await tester.pumpWidget(_app(const _Host()));
    CruxToasts.showInfo('First.');
    await tester.pump();
    expect(CruxToasts.showError('Re-run failed.'), isTrue);
    await tester.pump();
    expect(find.text('First.'), findsNothing);
    expect(find.text('Re-run failed.'), findsOneWidget);
    expect(announced.messages, contains('Re-run failed.'));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Re-run failed.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cruxToastClose')));
    await tester.pump();
    expect(find.text('Re-run failed.'), findsNothing);
  });

  testWidgets('the action works and is announced with the message', (
    tester,
  ) async {
    final announced = AnnouncementRecorder.attach(tester);
    var undone = 0;
    await tester.pumpWidget(_app(const _Host()));
    expect(
      CruxToasts.showInfo(
        'Removed.',
        action: CruxToastAction(label: 'Undo', onPressed: () => undone++),
      ),
      isTrue,
    );
    await tester.pump();
    expect(announced.messages, contains('Removed. Undo'));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, 1);
    expect(find.text('Removed.'), findsNothing);
  });

  testWidgets('without a host it is a safe no-op that returns false', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SizedBox.expand()));
    expect(CruxToasts.showInfo('Nowhere.'), isFalse);
    expect(CruxToasts.showError('Nowhere.'), isFalse);
    await tester.pump();
    expect(find.text('Nowhere.'), findsNothing);
  });

  testWidgets('a host whose theme is not a Crux Desktop theme is a no-op', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host(), desktop: false));
    expect(CruxToasts.showInfo('Phone.'), isFalse);
    await tester.pump();
    expect(find.text('Phone.'), findsNothing);
  });

  testWidgets('after the host unmounts the call is a no-op again', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const _Host()));
    await tester.pumpWidget(_app(const SizedBox.expand()));
    expect(CruxToasts.showInfo('Gone.'), isFalse);
  });

  testWidgets('a window that has shown a context toast is a host', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCruxInfoSnack(context, 'From context.'),
            child: const Text('Go'),
          ),
        ),
      ),
    );
    expect(CruxToasts.showInfo('Early.'), isFalse);
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(CruxToasts.showInfo('Later.'), isTrue);
    await tester.pump();
    expect(find.text('Later.'), findsOneWidget);
    expect(find.text('From context.'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('CruxIdeLayout registers its window as a host', (tester) async {
    await tester.pumpWidget(
      _app(
        CruxIdeLayout(
          layout: _Layout(),
          sink: _Sink(),
          leftBuilder: (_, _) => const SizedBox.shrink(),
          centerBuilder: (_, _) => const SizedBox.shrink(),
          rightBuilder: (_, _) => const SizedBox.shrink(),
          bottomBuilder: (_, _) => const SizedBox.shrink(),
        ),
      ),
    );
    expect(CruxToasts.showInfo('From the shell.'), isTrue);
    await tester.pump();
    expect(find.text('From the shell.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('two hosts: the one focused most recently wins', (tester) async {
    final first = GlobalKey<NavigatorState>();
    final second = GlobalKey<NavigatorState>();
    final focusA = FocusNode();
    final focusB = FocusNode();
    addTearDown(focusA.dispose);
    addTearDown(focusB.dispose);

    Widget window(GlobalKey<NavigatorState> key, FocusNode node, String id) =>
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: ThemeData(
                extensions: const <ThemeExtension<dynamic>>[
                  CruxDesktopTokens(),
                ],
              ),
              child: Navigator(
                key: key,
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => Stack(
                    children: <Widget>[
                      const _Host(),
                      Focus(focusNode: node, child: Text('window $id')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            window(first, focusA, 'a'),
            window(second, focusB, 'b'),
          ],
        ),
      ),
    );
    focusA.requestFocus();
    await tester.pump();
    CruxToasts.showInfo('For a.');
    await tester.pump();
    final overlayA = find.descendant(
      of: find.byKey(first),
      matching: find.text('For a.'),
    );
    expect(overlayA, findsOneWidget);

    focusB.requestFocus();
    await tester.pump();
    CruxToasts.showInfo('For b.');
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(second), matching: find.text('For b.')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
  });
}
