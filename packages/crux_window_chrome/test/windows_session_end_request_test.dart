// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Windows runners turn WM_ENDSESSION (a logoff, shutdown or restart) into
// one platform message to the framework and pump messages until it is
// answered, or three seconds pass. They need no Dart code of their own: the
// framework already answers that message by running every exit listener.
// These tests pin the contract the runners rely on, using the exact bytes
// their `flutter_window.cpp` sends:
//
// - the channel and the method call are the ones the Flutter engine sends
//   when the last window closes (`System.requestAppExit` with type
//   `cancelable`, the engine's `platform_handler.cc`);
// - every `AppLifecycleListener.onExitRequested` runs, even after one
//   cancels, so the session marker and the cross-probe peer file are
//   removed whatever another listener answers;
// - the reply comes only after the listeners' work finishes, which is what
//   the runner waits for before it lets Windows end the process.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The channel the runners send on (`kPlatformChannel` in the runners).
const String _runnerChannel = 'flutter/platform';

/// The message the runners send, byte for byte (`kSessionEndExitRequest`).
const String _runnerRequest =
    '{"method":"System.requestAppExit","args":{"type":"cancelable"}}';

/// Sends the runners' message as the engine delivers it and completes with
/// the decoded reply, or null when the framework sent none.
Future<Object?> _sendRunnerRequest() {
  final reply = Completer<Object?>();
  unawaited(
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _runnerChannel,
          ByteData.sublistView(utf8.encode(_runnerRequest)),
          (data) {
            try {
              reply.complete(
                data == null
                    ? null
                    : const JSONMethodCodec().decodeEnvelope(data),
              );
            } on Object catch (error, stack) {
              // An error envelope: the framework did not take the message.
              reply.completeError(error, stack);
            }
          },
        ),
  );
  return reply.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final listeners = <AppLifecycleListener>[];
  AppLifecycleListener listen(Future<AppExitResponse> Function() onExit) {
    final listener = AppLifecycleListener(onExitRequested: onExit);
    listeners.add(listener);
    return listener;
  }

  tearDown(() {
    for (final listener in listeners) {
      listener.dispose();
    }
    listeners.clear();
  });

  test('runs every exit listener and answers exit', () async {
    final ran = <String>[];
    listen(() async {
      ran.add('session marker');
      return AppExitResponse.exit;
    });
    listen(() async {
      ran.add('peer file');
      return AppExitResponse.exit;
    });

    final reply = await _sendRunnerRequest();

    expect(ran, <String>['session marker', 'peer file']);
    expect(reply, <String, Object?>{'response': 'exit'});
  });

  test('answers only once the listeners have finished their work', () async {
    final cleanup = Completer<void>();
    var cleanedUp = false;
    listen(() async {
      await cleanup.future;
      cleanedUp = true;
      return AppExitResponse.exit;
    });

    var answered = false;
    final reply = _sendRunnerRequest().whenComplete(() => answered = true);
    await pumpEventQueue();
    expect(answered, isFalse, reason: 'the runner must keep pumping');

    cleanup.complete();
    expect(await reply, <String, Object?>{'response': 'exit'});
    expect(cleanedUp, isTrue);
  });

  test('a listener that cancels does not stop the others', () async {
    final ran = <String>[];
    listen(() async {
      ran.add('unsaved work');
      return AppExitResponse.cancel;
    });
    listen(() async {
      ran.add('peer file');
      return AppExitResponse.exit;
    });

    final reply = await _sendRunnerRequest();

    expect(ran, <String>['unsaved work', 'peer file']);
    expect(reply, <String, Object?>{'response': 'cancel'});
  });
}
