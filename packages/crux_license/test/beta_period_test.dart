// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kBetaPeriod', () {
    // The release gate reads this default from source, and a production
    // release refuses a build where it is still true. This pins what a build
    // without a BETA_PERIOD define gets, which is what every release ships.
    test('is a const bool defaulting to false: the public beta has ended', () {
      expect(kBetaPeriod, isA<bool>());
      expect(kBetaPeriod, isFalse);
    });
  });
}
