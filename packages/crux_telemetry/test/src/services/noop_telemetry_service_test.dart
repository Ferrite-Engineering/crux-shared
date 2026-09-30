// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopTelemetryService', () {
    test('record discards every event without throwing', () {
      const NoopTelemetryService()
        ..record(TelemetryEvent('a'))
        ..record(TelemetryEvent('b', properties: const {'k': 1}));
      // No assertion possible; the contract is silent discard.
    });

    test('is const-constructible (singleton-friendly)', () {
      const a = NoopTelemetryService();
      const b = NoopTelemetryService();
      expect(identical(a, b), isTrue);
    });
  });
}
