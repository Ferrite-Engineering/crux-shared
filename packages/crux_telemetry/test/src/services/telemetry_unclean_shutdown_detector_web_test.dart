// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../harness.dart';

/// Runs only under `flutter test --platform chrome`, which CI invokes as its
/// own step. The VM suite never constructs the detector where `dart:io`
/// throws, so this is the one place the web path is executed: every web
/// edition builds the default instance on its first recorded event.
void main() {
  test('the default instance builds and stays inert in a browser', () async {
    final detector = TelemetryUncleanShutdownDetector.instance;
    expect(detector.supported, isFalse);
    expect(await detector.start(), isFalse);
    expect(detector.marker, isNull);
    detector.markCleanExit();
  });

  test('even a detector told it is supported does nothing', () async {
    final detector = TelemetryUncleanShutdownDetector(
      supported: true,
      directoryFactory: () => throw StateError('no file access on the web'),
    );
    expect(await detector.start(), isFalse);
    expect(detector.marker, isNull);
  });

  test('telemetryServiceProvider resolves and records', () async {
    // Only the product bindings are overridden: the detector is the default
    // process-wide instance, exactly as in a shipped web edition.
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(testTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(
          InMemoryTelemetryStorage(<String, String>{}),
        ),
        telemetryAppVersionProvider.overrideWith((_) async => '1.1.0'),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 202)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(telemetryServiceProvider);
    final detector = container.read(telemetryUncleanShutdownDetectorProvider);
    service.record(TelemetryEvent('test.web_first_event'));
    expect(await detector.start(), isFalse);
  });
}
