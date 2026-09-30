// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset clears the decision and mounts the disclosure again', () async {
    final storage = InMemoryTelemetryStorage(<String, String>{
      kTelemetryConsentKey: 'enabled',
      kTelemetryInstallationIdKey: '00000000-0000-4000-8000-000000000001',
    });

    await resetTelemetryConsent(storage);

    // Absent, not empty. The consent store reads a missing key as "never
    // answered" and any present value as an answer, so writing '' here would
    // leave the installation just as un-promptable as before.
    expect(storage.values.containsKey(kTelemetryConsentKey), isFalse);
    expect(TelemetryConsentState.tryParse(null), isNull);
  });

  test('reset leaves the installation id alone', () async {
    // Deliberate: re-minting on every reset would make each test launch look
    // like a new installation to whichever dataset the build points at.
    const id = '00000000-0000-4000-8000-000000000001';
    final storage = InMemoryTelemetryStorage(<String, String>{
      kTelemetryConsentKey: 'disabled',
      kTelemetryInstallationIdKey: id,
    });

    await resetTelemetryConsent(storage);

    expect(storage.values[kTelemetryInstallationIdKey], id);
  });

  test('reset on an installation that never answered is a no-op', () async {
    final storage = InMemoryTelemetryStorage();

    await resetTelemetryConsent(storage);

    expect(storage.values, isEmpty);
  });

  test('a refusal is cleared as readily as an acceptance', () async {
    // The reset is symmetric on purpose — it restores "never answered", it
    // does not restore "yes".
    final storage = InMemoryTelemetryStorage(<String, String>{
      kTelemetryConsentKey: 'disabled',
    });

    await resetTelemetryConsent(storage);

    expect(storage.values.containsKey(kTelemetryConsentKey), isFalse);
  });
}
