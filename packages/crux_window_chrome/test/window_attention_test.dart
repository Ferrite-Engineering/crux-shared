// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    // Restore the default backend and clear any mock handler between tests.
    windowAttentionRequester = const MethodChannelWindowAttentionRequester();
    messenger.setMockMethodCallHandler(windowAttentionChannel, null);
  });

  group('requestUserAttention', () {
    test('is callable and safely no-ops without a platform handler', () async {
      // No mock handler registered → MissingPluginException, which the default
      // requester swallows. This is the "app tests don't explode" guarantee.
      await expectLater(requestUserAttention(), completes);
      await expectLater(
        requestUserAttention(kind: WindowAttentionKind.critical),
        completes,
      );
    });

    test('forwards to the native channel with the kind argument', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(windowAttentionChannel, (call) async {
        calls.add(call);
        return null;
      });

      await requestUserAttention();
      await requestUserAttention(kind: WindowAttentionKind.critical);

      expect(calls, hasLength(2));
      expect(calls[0].method, 'requestUserAttention');
      expect(calls[0].arguments, {'kind': 'informational'});
      expect(calls[1].arguments, {'kind': 'critical'});
    });

    test('swallows a PlatformException from the native side', () async {
      messenger.setMockMethodCallHandler(windowAttentionChannel, (call) async {
        throw PlatformException(code: 'boom');
      });

      await expectLater(requestUserAttention(), completes);
    });

    test('NoopWindowAttentionRequester suppresses the channel call', () async {
      var called = false;
      messenger.setMockMethodCallHandler(windowAttentionChannel, (call) async {
        called = true;
        return null;
      });
      windowAttentionRequester = const NoopWindowAttentionRequester();

      await requestUserAttention();

      expect(called, isFalse);
    });

    test('a custom requester intercepts the request', () async {
      final fake = _RecordingRequester();
      windowAttentionRequester = fake;

      await requestUserAttention(kind: WindowAttentionKind.critical);

      expect(fake.kinds, [WindowAttentionKind.critical]);
    });
  });
}

class _RecordingRequester implements WindowAttentionRequester {
  final List<WindowAttentionKind> kinds = <WindowAttentionKind>[];

  @override
  Future<void> requestUserAttention(WindowAttentionKind kind) async {
    kinds.add(kind);
  }
}
