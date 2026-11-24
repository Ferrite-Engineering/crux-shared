// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart' show kBetaPeriod;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_telemetry_core/crux_telemetry_core.dart'
    show kHeadlessTelemetryBetaPeriod;
import 'package:flutter_test/flutter_test.dart';

/// What a headless binary reads without Flutter must agree with what this
/// package's gate reads with it.
void main() {
  test('the headless beta flag is crux_license kBetaPeriod', () {
    // `crux_telemetry_core` cannot import crux_license (a Flutter package),
    // so it reads the same define with the same default; a new beta that
    // changed the default in one place only would fail here.
    expect(kHeadlessTelemetryBetaPeriod, kBetaPeriod);
  });

  test('the headless reader looks for the keys the consent store writes', () {
    // The headless reader adds `SharedPreferences`' `flutter.` prefix itself;
    // the store writes the bare suite keys through the product's adapter.
    expect(TelemetryConsentStore.storageKey, 'telemetry.consent');
    expect(kTelemetryConsentKey, TelemetryConsentStore.storageKey);
    expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
  });
}
