// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ModalGuard.reset);

  test('re-entrant run with the same key is suppressed until close', () async {
    final first = Completer<void>();
    var opens = 0;

    unawaited(
      ModalGuard.run('dlg', () {
        opens++;
        return first.future;
      }),
    );
    expect(ModalGuard.isOpen('dlg'), isTrue);

    await ModalGuard.run('dlg', () async => opens++);
    expect(opens, 1, reason: 're-entrant open must be a no-op');

    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(ModalGuard.isOpen('dlg'), isFalse);

    await ModalGuard.run('dlg', () async => opens++);
    expect(opens, 2, reason: 'key must be reusable after close');
  });

  test('distinct keys do not block each other', () async {
    final a = Completer<void>();
    var bOpened = false;
    unawaited(ModalGuard.run('a', () => a.future));
    await ModalGuard.run('b', () async => bOpened = true);
    expect(bOpened, isTrue);
    a.complete();
  });

  test('a throwing open releases the key', () async {
    await expectLater(
      ModalGuard.run('boom', () async => throw StateError('x')),
      throwsStateError,
    );
    expect(ModalGuard.isOpen('boom'), isFalse);
  });
}
