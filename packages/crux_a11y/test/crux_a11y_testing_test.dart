// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the testing barrel exports the guard', () {
    expect(SemanticsOrphanGuard.instance, isNotNull);
  });
}
