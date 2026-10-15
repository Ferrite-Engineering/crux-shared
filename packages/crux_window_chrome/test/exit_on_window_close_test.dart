// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:crux_window_chrome/src/exit_on_window_close.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('routeWindowCloseThroughExitRequest', () {
    test(
      'holds the window open and installs one exit-request listener',
      () async {
        final prevented = <bool>[];
        final listeners = <WindowListener>[];
        await routeWindowCloseThroughExitRequest(
          setPreventClose: (p) async => prevented.add(p),
          addListener: listeners.add,
          requestExit: () async => AppExitResponse.exit,
          forceClose: () async {},
        );
        expect(prevented, <bool>[true]);
        expect(listeners, hasLength(1));
        expect(listeners.single, isA<ExitRequestOnWindowClose>());
      },
    );
  });

  group('ExitRequestOnWindowClose', () {
    test('a window close asks the app to exit', () async {
      var asked = 0;
      var forced = 0;
      ExitRequestOnWindowClose(
        requestExit: () async {
          asked++;
          return AppExitResponse.exit;
        },
        forceClose: () async => forced++,
      ).onWindowClose();
      await pumpEventQueue();
      expect(asked, 1);
      expect(forced, 0);
    });

    test('a cancelled exit leaves the window alone', () async {
      var forced = 0;
      ExitRequestOnWindowClose(
        requestExit: () async => AppExitResponse.cancel,
        forceClose: () async => forced++,
      ).onWindowClose();
      await pumpEventQueue();
      expect(forced, 0);
    });

    test('a second close while the first is answered asks once', () async {
      var asked = 0;
      final answer = Completer<AppExitResponse>();
      final listener =
          ExitRequestOnWindowClose(
              requestExit: () {
                asked++;
                return answer.future;
              },
              forceClose: () async {},
            )
            ..onWindowClose()
            ..onWindowClose();
      expect(asked, 1);
      answer.complete(AppExitResponse.cancel);
      await pumpEventQueue();
      listener.onWindowClose();
      expect(asked, 2);
    });

    test('a failed request still closes the window', () async {
      var forced = 0;
      ExitRequestOnWindowClose(
        requestExit: () async => throw StateError('no engine'),
        forceClose: () async => forced++,
      ).onWindowClose();
      await pumpEventQueue();
      expect(forced, 1);
    });
  });
}
