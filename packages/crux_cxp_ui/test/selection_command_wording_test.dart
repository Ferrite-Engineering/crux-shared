// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the selection command is hyphenated like every other cross-probe label',
    () {
      final s = CruxCxpStrings.forLocale(
        const Locale('en'),
        product: 'WaveCrux',
      );
      expect(s.selectionCommand, 'Cross-Probe Selection…');
    },
  );

  test('the selection command opens something, so it ends in an ellipsis', () {
    for (final code in ['en', 'zh', 'ja', 'ko']) {
      final s = CruxCxpStrings.forLocale(Locale(code), product: 'WaveCrux');
      expect(s.selectionCommand.endsWith('…'), isTrue, reason: code);
    }
  });
}
