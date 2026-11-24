// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry_core/crux_telemetry_core.dart';

/// A desktop store held in memory: what a desktop app recorded, changeable
/// mid-test the way the user changes it in the app.
class FakeStore implements DesktopTelemetryStore {
  /// A store holding nothing.
  FakeStore();

  /// A store holding the answer [consent] and, when given, [id].
  FakeStore.answered(String consent, {String? id}) {
    values[kTelemetryConsentKey] = consent;
    if (id != null) values[kTelemetryInstallationIdKey] = id;
  }

  /// What is stored, by suite key.
  final Map<String, String> values = <String, String>{};

  /// How many reads were made.
  int reads = 0;

  @override
  String? read(String key) {
    reads++;
    return values[key];
  }
}
