// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/window_foreground.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    windowForegroundHandoff = const MethodChannelWindowForegroundHandoff();
    messenger.setMockMethodCallHandler(windowForegroundChannel, null);
  });

  group('the method-channel hand-off', () {
    test('without a platform handler it makes no hand-off and never '
        'raises', () async {
      expect(await windowForegroundHandoff.yieldForegroundTo(4242), isNull);
      expect(await windowForegroundHandoff.takeForeground(''), isFalse);
    });

    test('yields to the process it is given and passes the token on, as '
        'the channel contract names them', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(windowForegroundChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'yieldForeground' => 'wayland-token-1',
          'takeForeground' => true,
          _ => null,
        };
      });

      expect(
        await windowForegroundHandoff.yieldForegroundTo(4242),
        'wayland-token-1',
      );
      expect(
        await windowForegroundHandoff.takeForeground('wayland-token-1'),
        isTrue,
      );
      expect(calls.map((c) => c.method), ['yieldForeground', 'takeForeground']);
      expect(calls[0].arguments, {'pid': 4242});
      expect(calls[1].arguments, {'token': 'wayland-token-1'});
    });

    test('an empty token is a hand-off, a null answer is none', () async {
      Object? answer = '';
      messenger.setMockMethodCallHandler(
        windowForegroundChannel,
        (call) async => answer,
      );
      expect(await windowForegroundHandoff.yieldForegroundTo(7), '');
      answer = null;
      expect(await windowForegroundHandoff.yieldForegroundTo(7), isNull);
      expect(await windowForegroundHandoff.takeForeground(''), isFalse);
    });

    test('a pid that names no process is never sent to the platform', () async {
      var called = false;
      messenger.setMockMethodCallHandler(windowForegroundChannel, (call) async {
        called = true;
        return '';
      });
      expect(await windowForegroundHandoff.yieldForegroundTo(0), isNull);
      expect(await windowForegroundHandoff.yieldForegroundTo(-1), isNull);
      expect(called, isFalse);
    });

    test('a native failure is no hand-off, never an error', () async {
      messenger.setMockMethodCallHandler(windowForegroundChannel, (call) async {
        throw PlatformException(code: 'refused');
      });
      expect(await windowForegroundHandoff.yieldForegroundTo(4242), isNull);
      expect(await windowForegroundHandoff.takeForeground('t'), isFalse);
    });
  });

  test('the no-op hand-off never reaches the platform', () async {
    var called = false;
    messenger.setMockMethodCallHandler(windowForegroundChannel, (call) async {
      called = true;
      return '';
    });
    windowForegroundHandoff = const NoopWindowForegroundHandoff();
    expect(await windowForegroundHandoff.yieldForegroundTo(4242), isNull);
    expect(await windowForegroundHandoff.takeForeground(''), isFalse);
    expect(called, isFalse);
  });
}
