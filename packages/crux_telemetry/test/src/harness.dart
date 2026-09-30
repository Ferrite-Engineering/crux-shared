// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';

/// The configuration every test in this package wires.
///
/// The slug is `wavecrux` and the `User-Agent` name is `WaveCrux` for one
/// reason: the ingestion Worker's canonical `valid-batch.json` — the document
/// the payload-contract test asserts this package emits — carries them. Using
/// anything else here would mean maintaining a second fixture whose only
/// difference from the contract is a slug, which is exactly how a contract test
/// stops testing the contract.
///
/// Nothing in `lib/` knows either string.
final CruxTelemetryConfig testTelemetryConfig = CruxTelemetryConfig(
  productSlug: 'wavecrux',
  userAgentName: 'WaveCrux',
);

/// The envelope the contract fixture describes, and the one every service test
/// posts with.
TelemetryEnvelope testEnvelope({
  String locale = 'en',
  String licenseTier = 'openCore',
}) => TelemetryEnvelope(
  installationId: '00000000-0000-4000-8000-000000000002',
  appVersion: '0.6.0',
  product: testTelemetryConfig.productSlug,
  os: 'macos',
  formFactor: 'desktop',
  locale: locale,
  licenseTier: licenseTier,
  sessionStart: DateTime.utc(2026, 8, 4, 9, 15),
  userAgentName: testTelemetryConfig.userAgentName,
);
