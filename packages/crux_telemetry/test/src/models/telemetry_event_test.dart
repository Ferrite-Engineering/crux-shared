// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelemetryEvent', () {
    test(
      'defaults timestamp to now and properties to empty unmodifiable map',
      () {
        final before = DateTime.now();
        final event = TelemetryEvent('test.event');
        final after = DateTime.now();

        expect(event.name, 'test.event');
        expect(event.properties, isEmpty);
        expect(event.timestamp.isBefore(before), isFalse);
        expect(event.timestamp.isAfter(after), isFalse);
        expect(() => event.properties['x'] = 1, throwsUnsupportedError);
      },
    );

    test('preserves explicit timestamp and properties', () {
      final ts = DateTime.utc(2026, 5, 5, 12, 30);
      final event = TelemetryEvent(
        'feature.enabled',
        properties: const {'count': 3, 'mode': 'auto'},
        timestamp: ts,
      );

      expect(event.name, 'feature.enabled');
      expect(event.timestamp, ts);
      expect(event.properties, {'count': 3, 'mode': 'auto'});
    });

    test('equality matches name + timestamp + properties', () {
      final ts = DateTime.utc(2026, 5, 5);
      final a = TelemetryEvent('a', properties: const {'k': 1}, timestamp: ts);
      final b = TelemetryEvent('a', properties: const {'k': 1}, timestamp: ts);
      final differentName = TelemetryEvent(
        'b',
        properties: const {'k': 1},
        timestamp: ts,
      );
      final differentProps = TelemetryEvent(
        'a',
        properties: const {'k': 2},
        timestamp: ts,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(differentName));
      expect(a, isNot(differentProps));
    });

    test('toString includes name and properties', () {
      final event = TelemetryEvent('debug_advisor.suggestion.accepted');
      expect(event.toString(), contains('debug_advisor.suggestion.accepted'));
    });
  });
}
