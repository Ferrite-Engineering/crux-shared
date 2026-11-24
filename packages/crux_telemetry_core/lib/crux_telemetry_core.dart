// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The Flutter-free half of the suite's telemetry.
///
/// `crux_telemetry` is a Flutter package: its pipeline is built on Riverpod,
/// its queue on `path_provider`, its consent surfaces are widgets. A headless
/// binary built with `dart build cli` (each product's command line and MCP
/// server) can link none of that. This package holds what both need and
/// nothing that needs Flutter:
///
///  * the payload: `TelemetryEvent`, `TelemetryEnvelope`, the coalescing
///    batcher, the endpoints and the closed vocabularies the Worker checks;
///  * the consent vocabulary: `TelemetryConsentState`, `TelemetryPolicy`, the
///    storage keys and the `TelemetryStorage` seam;
///  * `TelemetryService` and `NoopTelemetryService`, and
///    `telemetryEnumToken`;
///  * for headless binaries: `DesktopTelemetryConsent`, which reads the
///    consent a product's desktop app recorded on this machine (both
///    editions, on macOS, Linux and Windows), and `HeadlessTelemetry`, which
///    counts under it and sends to the same Worker under the app's
///    installation id, never when `CI` is set.
///
/// `crux_telemetry` re-exports the first three groups, so a desktop app
/// imports only `crux_telemetry`. `no_flutter_dependency_test.dart` proves
/// that no Flutter package is anywhere in this one's closure.
library;

export 'src/headless/desktop_telemetry_store.dart';
export 'src/headless/headless_telemetry.dart';
export 'src/models/telemetry_consent_state.dart';
export 'src/models/telemetry_envelope.dart';
export 'src/models/telemetry_event.dart';
export 'src/models/telemetry_policy.dart';
export 'src/services/noop_telemetry_service.dart';
export 'src/services/telemetry_batch.dart';
export 'src/storage/telemetry_storage.dart';
export 'src/telemetry_endpoint.dart';
export 'src/telemetry_enum_token.dart';
export 'src/telemetry_service.dart';
export 'src/telemetry_vocabulary.dart';
