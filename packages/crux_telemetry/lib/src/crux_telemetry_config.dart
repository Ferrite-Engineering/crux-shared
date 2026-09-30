// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/services/telemetry_event_queue.dart';
import 'package:crux_telemetry/src/telemetry_endpoint.dart';
import 'package:meta/meta.dart';

/// Everything the telemetry pipeline needs to know about the *product* it is
/// collecting for.
///
/// The one piece of per-product configuration in `crux_telemetry`. Each product
/// supplies exactly one instance through `cruxTelemetryConfigProvider`, which
/// has no default binding — a product that forgets to override it throws at the
/// first read (app wiring) rather than silently reporting somebody else's slug.
///
/// ```dart
/// final netCruxTelemetryConfig = CruxTelemetryConfig(
///   productSlug: 'netcrux',
///   userAgentName: 'NetCrux',
/// );
/// ```
///
/// The endpoints default to the suite ingest Worker and are overridable only
/// for tests and for a future self-hosted Enterprise ingest; a product that
/// simply reports usage never touches them.
@immutable
class CruxTelemetryConfig {
  /// Creates a telemetry configuration from URL literals.
  ///
  /// The endpoints are taken as `String`s and parsed here so a product can
  /// declare them as plain literals rather than sprinkling [Uri.parse] over its
  /// wiring, and so a malformed URL throws [FormatException] at construction —
  /// the same wiring moment the missing-override case throws — never mid-flush.
  CruxTelemetryConfig({
    required this.productSlug,
    required this.userAgentName,
    String productionEndpoint = kTelemetryProductionEndpoint,
    String stagingEndpoint = kTelemetryStagingEndpoint,
    String documentationUri = kTelemetryDocumentationUri,
    this.flushInterval = kTelemetryFlushInterval,
    this.volatileFlushInterval = kTelemetryVolatileFlushInterval,
    this.initialRetryDelay = kTelemetryInitialRetryDelay,
    this.maxRetryDelay = kTelemetryMaxRetryDelay,
    this.postTimeout = kTelemetryPostTimeout,
    this.maxQueuedEvents = kTelemetryMaxQueuedEvents,
    this.maxEventAge = kTelemetryEventMaxAge,
  }) : productionEndpoint = Uri.parse(productionEndpoint),
       stagingEndpoint = Uri.parse(stagingEndpoint),
       documentationUri = Uri.parse(documentationUri);

  /// The slug reported as the `product` envelope field — lowercase, no spaces,
  /// and one of the Worker's `PRODUCTS` set (`wavecrux`, `netcrux`,
  /// `lintcrux`, `simcrux`).
  ///
  /// A slug the Worker does not know rejects **every** batch the product ever
  /// sends, with a 400 the client cannot see, so this is checked against the
  /// Worker's list by the payload-contract test rather than left to review.
  final String productSlug;

  /// The product's display name for the ingest `User-Agent`
  /// (`WaveCrux/0.6.0`). Keep it a single token without spaces so the header
  /// stays well-formed.
  final String userAgentName;

  /// Ingest endpoint writing the production dataset.
  final Uri productionEndpoint;

  /// Ingest endpoint writing the staging dataset, used by `TELEMETRY_DEV`
  /// builds.
  final Uri stagingEndpoint;

  /// The disclosure page both consent surfaces link to.
  final Uri documentationUri;

  /// Interval between automatic flushes after the launch flush.
  final Duration flushInterval;

  /// Interval used **only where the queue has no persistent backing** — web,
  /// and anywhere else `path_provider` cannot give the queue a file.
  ///
  /// Tunable per product for the same reason [flushInterval] is: a product
  /// whose web build is a short-lived read-only viewer may want it shorter
  /// still. See `LiveTelemetryService` for why the two cadences differ.
  final Duration volatileFlushInterval;

  /// First backoff step after a failed flush; doubles up to [maxRetryDelay].
  final Duration initialRetryDelay;

  /// Ceiling on the backoff.
  final Duration maxRetryDelay;

  /// Per-POST timeout.
  final Duration postTimeout;

  /// Hard cap on queued events, in memory and on disk.
  final int maxQueuedEvents;

  /// Age beyond which a queued event is dropped unsent.
  final Duration maxEventAge;

  /// The ingest URL for a [dev] build. **The path selects the dataset** — see
  /// [telemetryEndpointFor].
  Uri endpointFor({required bool dev}) =>
      dev ? stagingEndpoint : productionEndpoint;

  @override
  String toString() =>
      'CruxTelemetryConfig(productSlug: $productSlug, '
      'userAgentName: $userAgentName, '
      'productionEndpoint: $productionEndpoint)';
}

/// Default interval between automatic flushes after the launch flush.
const Duration kTelemetryFlushInterval = Duration(hours: 6);

/// Default near-term flush cadence for a queue with **no persistent backing**.
///
/// Six hours is the right interval when the queue survives the process, because
/// the launch flush is what actually ships a session and the timer is only
/// there for the long-running case. Where the queue is memory-only there is no
/// next launch to hand anything to, so the same interval means "never": no
/// browser tab lives six hours. Sixty seconds is long enough that identical
/// events still coalesce and no user action ever waits on the network, and
/// short enough that a one-minute visit reports.
const Duration kTelemetryVolatileFlushInterval = Duration(seconds: 60);

/// Default first backoff step after a failed flush.
const Duration kTelemetryInitialRetryDelay = Duration(minutes: 1);

/// Default ceiling on the flush backoff.
///
/// Reached quickly and stayed at: an installation that cannot reach the
/// endpoint should knock roughly as often as the normal schedule would, not
/// less and certainly not more.
const Duration kTelemetryMaxRetryDelay = Duration(hours: 6);

/// Default per-POST timeout.
const Duration kTelemetryPostTimeout = Duration(seconds: 15);
