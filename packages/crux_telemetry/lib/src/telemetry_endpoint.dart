// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Whether this build targets the **staging** telemetry dataset.
///
/// Set with `--dart-define=TELEMETRY_DEV=true`. This is the suite's dark-launch
/// switch: it activates the live pipeline in an ordinary `main` build so the
/// exact code real users will run can be exercised end to end on every
/// platform, while the production `crux_telemetry` dataset receives nothing
/// until the beta flag flips.
///
/// Read through `telemetryDevModeProvider` everywhere except the provider's own
/// default binding, so the gating matrix can be exercised without one build per
/// cell.
const bool kTelemetryDev = bool.fromEnvironment('TELEMETRY_DEV');

/// Production ingest — writes the `crux_telemetry` dataset.
///
/// Public on purpose. The whole client pipeline ships in the Apache-2.0
/// open-core source, so the URL could never have been a secret; abuse is
/// handled by the Worker's strict payload validation, not by hiding it.
///
/// One endpoint for the whole suite: the `product` envelope field is what
/// separates the four products' rows, not four hostnames.
const String kTelemetryProductionEndpoint =
    'https://telemetry.edacrux.app/v1/events';

/// Staging ingest — writes the `crux_telemetry_dev` dataset.
const String kTelemetryStagingEndpoint =
    'https://telemetry.edacrux.app/dev/v1/events';

/// The suite-wide telemetry disclosure page.
///
/// One page backs all four clients — the exact field list, the never-collect
/// list, and the opt-out instructions. Both consent surfaces (the first-launch
/// disclosure and Settings → Privacy) link here, so they cannot come to point
/// at different pages.
const String kTelemetryDocumentationUri = 'https://edacrux.app/telemetry';

/// The ingest URL for a [dev] build.
///
/// **The path selects the dataset** — not a header, not a body field. That is
/// the Worker's invariant, and it is what makes it impossible for a
/// misconfigured client to write staging events into production: nothing it
/// *sends* can move it between datasets, only which endpoint it *calls*.
Uri telemetryEndpointFor({required bool dev}) =>
    Uri.parse(dev ? kTelemetryStagingEndpoint : kTelemetryProductionEndpoint);
