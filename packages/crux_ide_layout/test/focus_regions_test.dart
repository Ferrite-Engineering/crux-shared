// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Layout implements IdePanelLayout {
  _Layout({this.bottomVisible = true});

  @override
  bool leftVisible = true;
  @override
  bool rightVisible = true;
  @override
  bool bottomVisible;
  @override
  PaneSize? leftSize = PaneSize.pixel(200);
  @override
  PaneSize? rightSize = PaneSize.pixel(200);
  @override
  PaneSize? bottomSize = PaneSize.pixel(150);
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

Widget _buttons(String region) => Column(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    TextButton(onPressed: () {}, child: Text('$region one')),
    TextButton(onPressed: () {}, child: Text('$region two')),
  ],
);

Widget _screen({
  bool bottomVisible = true,
  bool? restoreLostFocus,
  bool toolbarButton = true,
}) => MaterialApp(
  home: Scaffold(
    body: CruxFocusRegionScope(
      restoreLostFocus: restoreLostFocus,
      child: Column(
        children: <Widget>[
          CruxFocusRegion(
            semanticLabel: 'Toolbar',
            child: toolbarButton
                ? TextButton(onPressed: () {}, child: const Text('Open'))
                : TextButton(
                    key: const Key('replacement'),
                    onPressed: () {},
                    child: const Text('Open again'),
                  ),
          ),
          Expanded(
            child: CruxIdeLayout(
              layout: _Layout(bottomVisible: bottomVisible),
              sink: _Sink(),
              // Buttons sit at the top of every region, level with the full
              // height resizers, so a geometric order would interleave them.
              leftBuilder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: _buttons('Left'),
              ),
              centerBuilder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: _buttons('Center'),
              ),
              rightBuilder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: _buttons('Right'),
              ),
              bottomBuilder: (_, _) => Align(
                alignment: Alignment.topLeft,
                child: _buttons('Bottom'),
              ),
            ),
          ),
          CruxFocusRegion(
            semanticLabel: 'Status bar',
            child: TextButton(onPressed: () {}, child: const Text('Errors')),
          ),
        ],
      ),
    ),
  ),
);

String? _focusedText() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final element = context as Element;
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final widget = e.widget;
    if (widget is Text) {
      found = widget.data;
      return;
    }
    e.visitChildren(visit);
  }

  visit(element);
  return found;
}

Future<void> _press(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.f6);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  testWidgets('Tab finishes a region before the next, and skips resizers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.stops.map((s) => s.name), <String>[
      'Open',
      'Left one',
      'Left two',
      'Center one',
      'Center two',
      'Bottom one',
      'Bottom two',
      'Right one',
      'Right two',
      'Errors',
    ]);
    expect(walk.stops.first.entered, <String>['Toolbar grouping']);
    handle.dispose();
  });

  testWidgets('a hidden region contributes no Tab stops', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_screen(bottomVisible: false));
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);

    expectCleanFocusWalk(walk);
    expect(walk.stops.map((s) => s.name), isNot(contains('Bottom one')));
    handle.dispose();
  });

  testWidgets('F6 and Shift+F6 move between regions in order', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final forward = <String?>[];
    for (var i = 0; i < 7; i++) {
      await _press(tester);
      forward.add(_focusedText());
    }
    expect(forward, <String?>[
      'Open',
      'Left one',
      'Center one',
      'Bottom one',
      'Right one',
      'Errors',
      'Open',
    ]);

    await _press(tester, shift: true);
    expect(_focusedText(), 'Errors');
    await _press(tester, shift: true);
    expect(_focusedText(), 'Right one');
  });

  testWidgets('returning to a region restores the control F6 left', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    await _press(tester); // Open
    await _press(tester); // Left one
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusedText(), 'Left two');

    await _press(tester); // Center one
    await _press(tester, shift: true);
    expect(_focusedText(), 'Left two');
  });

  testWidgets('F6 does not reach behind a dialog', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Open'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Busy')),
      ),
    );
    await tester.pumpAndSettle();

    await _press(tester);
    final primary = FocusManager.instance.primaryFocus;
    expect(
      primary?.context?.findAncestorWidgetOfExactType<CruxFocusRegion>(),
      isNull,
    );
  });

  group('lost focus', () {
    void focusText(WidgetTester tester, String text) =>
        Focus.of(tester.element(find.text(text))).requestFocus();

    testWidgets('activating a start-screen button that replaces the screen '
        'puts focus in the new primary region', (tester) async {
      // A detached focus node keeps its context and its cached ancestors,
      // so a restore that trusted those asked a dead node for focus and
      // left the window with none (SimCrux: Open Config → workspace).
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CruxFocusRegionScope(
                restoreLostFocus: true,
                child: Column(
                  children: <Widget>[
                    CruxFocusRegion(
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('Settings'),
                      ),
                    ),
                    Expanded(
                      child: CruxFocusRegion(
                        primary: true,
                        child: opened
                            ? OutlinedButton(
                                onPressed: () {},
                                child: const Text('Run'),
                              )
                            : FilledButton(
                                onPressed: () => setState(() => opened = true),
                                child: const Text('Open Config'),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_focusedText(), 'Open Config');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_focusedText(), 'Run');
    });

    testWidgets('a screen that opens with nothing focused claims the '
        'primary region', (tester) async {
      await tester.pumpWidget(_screen(restoreLostFocus: true));
      await tester.pumpAndSettle();

      expect(_focusedText(), 'Center one');
    });

    testWidgets('a rebuilt-away control hands focus to the primary region', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(restoreLostFocus: true));
      await tester.pumpAndSettle();
      focusText(tester, 'Open');
      await tester.pump();
      expect(_focusedText(), 'Open');

      // The focused toolbar button is replaced by a different widget, the
      // way a layout swap rebuilds a toolbar, so its focus node goes away.
      await tester.pumpWidget(
        _screen(restoreLostFocus: true, toolbarButton: false),
      );
      await tester.pumpAndSettle();

      expect(_focusedText(), 'Center one');
    });

    testWidgets('focus dropped onto the scope returns to where it was', (
      tester,
    ) async {
      await tester.pumpWidget(_screen(restoreLostFocus: true));
      await tester.pumpAndSettle();
      focusText(tester, 'Left two');
      await tester.pump();

      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(_focusedText(), 'Left two');
    });

    testWidgets('restoring can be switched off', (tester) async {
      await tester.pumpWidget(_screen(restoreLostFocus: false));
      await tester.pumpAndSettle();
      focusText(tester, 'Open');
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    });

    testWidgets('it is off by default on mobile platforms', (tester) async {
      await tester.pumpWidget(_screen());
      await tester.pumpAndSettle();
      focusText(tester, 'Open');
      await tester.pump();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, isA<FocusScopeNode>());
    });

    testWidgets(
      'it is on by default on desktop platforms',
      (tester) async {
        await tester.pumpWidget(_screen());
        await tester.pumpAndSettle();
        focusText(tester, 'Open');
        await tester.pump();
        FocusManager.instance.primaryFocus!.unfocus();
        await tester.pumpAndSettle();

        expect(_focusedText(), 'Open');
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );

    testWidgets('it does not pull focus out of a dialog', (tester) async {
      await tester.pumpWidget(_screen(restoreLostFocus: true));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Open'));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Busy')),
        ),
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CruxFocusRegion>(),
        isNull,
      );
    });
  });

  testWidgets('the scope exposes the movement for a host keymap', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Open'));
    final scope = CruxFocusRegionScope.maybeOf(context)!;

    expect(scope.focusNext(), isTrue);
    await tester.pump();
    expect(_focusedText(), 'Open');
    expect(scope.focusPrevious(), isTrue);
    await tester.pump();
    expect(_focusedText(), 'Errors');
  });

  group('announcements', () {
    Widget host(void Function(BuildContext) onPressed) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('go'),
          ),
        ),
      ),
    );

    testWidgets('announceCrux speaks the message', (tester) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        host((context) => announceCrux(context, 'Signals added')),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(recorder.messages, <String>['Signals added']);
    });

    testWidgets('the feedback snack bars are also spoken', (tester) async {
      final recorder = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        host((context) {
          showCruxInfoSnack(context, 'Saved');
          showCruxErrorSnack(context, 'Could not open top.vcd');
        }),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(recorder.messages, <String>['Saved', 'Could not open top.vcd']);
    });
  });
}
