// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A tab's content is the first page of the tab's own navigator, and every
// route builds a barrier beneath its content. A page route's barrier is not
// dismissible, and tapping one plays the platform alert sound (NSBeep on
// macOS). Content that lets the pointer through, as a schematic or waveform
// canvas does, put every click on that barrier too: the click did its work
// and the window beeped. The page has nothing beneath it to dismiss, so it
// builds no barrier a pointer can reach. A dialog pushed above it keeps its
// own.

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MethodCall> sounds;

  setUp(() => sounds = <MethodCall>[]);

  void listenForSounds(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemSound.play') sounds.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  testWidgets('a click on content that lets the pointer through plays no '
      'sound, and still reaches the content', (tester) async {
    listenForSounds(tester);
    var downs = 0;
    final tab = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: CruxTabNavigatorHost(
          navigatorKey: tab,
          builder: (_) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => downs++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));

    expect(downs, 1);
    expect(sounds, isEmpty);
  });

  testWidgets('a dialog on the tab navigator that cannot be dismissed still '
      'holds the pointer with its own barrier', (tester) async {
    listenForSounds(tester);
    var downs = 0;
    final tab = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: CruxTabNavigatorHost(
          navigatorKey: tab,
          builder: (_) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => downs++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    unawaited(
      showDialog<void>(
        context: tab.currentContext!,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('Busy')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Busy'), findsOneWidget);
    expect(downs, 0);
    expect(sounds, hasLength(1));
  });
}
