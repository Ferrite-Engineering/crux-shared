// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Cross-suite anonymous usage-statistics pipeline for the EDACrux suite.
///
/// One implementation of "what did people actually use, and did they agree to
/// tell us?" for every product in the suite: the event model, the append-only
/// disk queue with its age and size caps, the coalescing batcher that matches
/// the ingestion Worker's payload contract, the never-throwing ingest client
/// with its backoff, the beta × dev-flag × Enterprise-policy × consent gate,
/// and both consent surfaces — the first-launch disclosure, shown until it is
/// answered, and the Settings → Privacy section.
///
/// Everything product-specific stays out. The event **catalog** and the call
/// sites that record against it belong to each product; so do the ARB strings
/// (supplied through `CruxTelemetryStrings`), the `form_factor` derivation
/// (supplied through `telemetryFormFactorProvider`), and the persistence
/// adapter (supplied through `telemetryStorageProvider`). The product slug,
/// the `User-Agent` name and the endpoints arrive as a `CruxTelemetryConfig`
/// through `cruxTelemetryConfigProvider`. See the package README for the wiring
/// snippet.
///
/// One event is the exception, because no product call site can record it:
/// `app.uncaught_error`, which `TelemetryUncaughtErrorCounter` records from the
/// global error handlers with a closed vocabulary this package owns. Each
/// product still lists it in its own catalog.
///
/// **The pipeline is inert during the public beta.** `telemetryGateProvider` —
/// the transmission gate, from which alone `telemetryServiceProvider` chooses
/// the live, no-op or pending service — is `closed` for every consent value
/// while `kBetaPeriod` is on and the `TELEMETRY_DEV` dart-define is off, so the
/// live service is never constructed and the consent surfaces never mount.
/// Activation is the `kBetaPeriod` flip, not a merge.
library;

export 'src/crux_telemetry_config.dart'
    hide
        kTelemetryFlushInterval,
        kTelemetryInitialRetryDelay,
        kTelemetryMaxRetryDelay,
        kTelemetryPostTimeout,
        kTelemetryVolatileFlushInterval;
export 'src/crux_telemetry_strings.dart';
export 'src/models/telemetry_consent_state.dart';
export 'src/models/telemetry_envelope.dart' hide telemetryIso8601;
export 'src/models/telemetry_event.dart';
export 'src/models/telemetry_policy.dart';
export 'src/providers/telemetry_consent_store.dart';
export 'src/providers/telemetry_consent_ui_providers.dart'
    hide openTelemetryDocumentation;
export 'src/providers/telemetry_installation_id.dart'
    hide mintTelemetryInstallationId, telemetryStoredInstallationIdProvider;
export 'src/providers/telemetry_seam_providers.dart'
    hide
        telemetryDefaultConsentProvider,
        telemetryPlatformLocalesProvider,
        telemetryPlatformRegionsProvider,
        telemetryPlatformTimeZoneProvider,
        telemetrySessionStartProvider;
export 'src/providers/telemetry_service_provider.dart'
    hide resolveTelemetryEnvelope, telemetryUncaughtErrorCounterProvider;
export 'src/services/live_telemetry_service.dart';
export 'src/services/noop_telemetry_service.dart';
export 'src/services/pending_telemetry_service.dart';
export 'src/services/telemetry_batch.dart'
    hide
        canonicalTelemetryProperties,
        encodeTelemetryBatch,
        kTelemetryMaxBatchBytes,
        kTelemetryMaxBatchEvents,
        telemetryGroupKey;
export 'src/services/telemetry_event_queue.dart'
    hide kTelemetryEventMaxAge, kTelemetryMaxQueuedEvents, pruneTelemetryEvents;
export 'src/services/telemetry_uncaught_error_counter.dart'
    hide kTelemetryUncaughtErrorSessionCap;
export 'src/services/telemetry_unclean_shutdown_detector.dart'
    hide kCruxUncleanShutdownEventEnabled;
export 'src/storage/telemetry_storage.dart';
export 'src/telemetry_endpoint.dart'
    hide
        kTelemetryDocumentationUri,
        kTelemetryProductionEndpoint,
        kTelemetryStagingEndpoint;
export 'src/telemetry_enum_token.dart';
export 'src/telemetry_error_vocabulary.dart'
    hide
        kTelemetryFlutterLibraryTokens,
        telemetryErrorKindOf,
        telemetryErrorLibraryOf;
export 'src/telemetry_platform.dart' hide telemetryOsSlug;
export 'src/telemetry_region.dart'
    hide
        kTelemetryOptInCountries,
        kTelemetryOptInTimeZonePrefix,
        kTelemetryOptInTimeZones,
        telemetryCountriesInLocaleId,
        telemetryDefaultConsentFor,
        telemetryRequiresOptIn,
        telemetryTimeZoneRequiresOptIn;
export 'src/telemetry_service.dart';
export 'src/widgets/telemetry_consent_disclosure.dart';
export 'src/widgets/telemetry_consent_gate.dart';
export 'src/widgets/telemetry_consent_metrics.dart';
export 'src/widgets/telemetry_settings_section.dart';
