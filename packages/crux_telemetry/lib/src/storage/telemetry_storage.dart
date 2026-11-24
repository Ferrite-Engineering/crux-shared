// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Moved to the Flutter-free `crux_telemetry_core`, so a headless binary reads
// the same keys this package's consent store writes. This path stays because
// the products' headless entry points import it directly.
export 'package:crux_telemetry_core/crux_telemetry_core.dart'
    show
        InMemoryTelemetryStorage,
        TelemetryStorage,
        kTelemetryConsentKey,
        kTelemetryInstallationIdKey,
        resetTelemetryConsent;
