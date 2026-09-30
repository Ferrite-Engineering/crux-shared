// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kAiExperimental', () {
    test('is a const bool', () {
      expect(kAiExperimental, isA<bool>());
    });

    test('defaults to true (AI graduated to default-available)', () {
      // The test runner injects no AI_EXPERIMENTAL define, so the build flag
      // reads its compile-time default — now `true`. A normal build carries
      // the AI surface (still gated behind the off-by-default user opt-in).
      // Omitting AI entirely is `--dart-define=AI_EXPERIMENTAL=false`.
      expect(kAiExperimental, isTrue);
    });
  });
}
