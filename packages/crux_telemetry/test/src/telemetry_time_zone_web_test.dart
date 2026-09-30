// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_telemetry/src/telemetry_time_zone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs only under `flutter test --platform chrome`, which CI invokes as its
/// own step. The VM suite sees the stub, so this is the one place the JS
/// interop path is actually executed.
void main() {
  test('the browser names an IANA zone', () {
    final zone = platformIanaTimeZone();
    expect(zone, isNotNull);
    // `Europe/Berlin`, `America/Denver`, or a bare `UTC` on a headless runner.
    expect(zone, matches(RegExp(r'^[A-Za-z0-9_+\-/]+$')));
  });

  test('the seam provider carries the same value', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(telemetryPlatformTimeZoneProvider),
      platformIanaTimeZone(),
    );
  });
}
