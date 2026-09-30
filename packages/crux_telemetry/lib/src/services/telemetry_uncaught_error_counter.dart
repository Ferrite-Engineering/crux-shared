// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart' show kBetaPeriod;
import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/telemetry_endpoint.dart' show kTelemetryDev;
import 'package:crux_telemetry/src/telemetry_error_vocabulary.dart';
import 'package:crux_telemetry/src/telemetry_service.dart';
import 'package:flutter/foundation.dart' show FlutterErrorDetails;
import 'package:meta/meta.dart';

/// The default for [TelemetryUncaughtErrorCounter.sessionCap].
///
/// Ten, because the number of *distinct* `(source, kind, library)` tuples an
/// honest session produces is small. A single fault usually shows up as one
/// tuple, sometimes as that tuple plus the handful of secondary failures it
/// knocks loose — a build that throws, then the layout and paint errors of the
/// half-built subtree. Ten leaves room for the root cause and its cascade.
/// Past that, every extra tuple describes the same broken session again: it
/// adds nothing about the first fault, and it lets one wedged installation
/// outweigh many healthy ones in the suite-wide error totals. The cap is also
/// what bounds the pre-attach buffer, so it keeps that to ten small objects.
const int kTelemetryUncaughtErrorSessionCap = 10;

/// Counts uncaught errors as `app.uncaught_error` telemetry events: at most
/// once per `(source, kind, library)` tuple per session, and at most
/// [sessionCap] tuples in all.
///
/// **What it sends is the error's shape, never its content.** Each event
/// carries four closed-vocabulary properties — `source`, `kind`, `library`,
/// `silent` — and nothing else: no message, no stack, no file name, no
/// `toString` of anything. `kind` is decided by `is` checks, never by
/// `runtimeType.toString()`, which an obfuscated release build would scramble
/// and which is open-ended in any build. See `telemetry_error_vocabulary.dart`.
///
/// **Why it exists.** Every product installs `FlutterError.onError` and
/// `PlatformDispatcher.onError` before `runApp`, and until this counter those
/// handlers only filled an in-memory ring and wrote to stderr — which a
/// Finder-launched macOS app sends to `/dev/null` and a Windows GUI app does
/// not have. A crash in a GUI-launched release build left no durable trace
/// anywhere. This is the smallest trace that answers "does it crash in the
/// field, and in which part of the framework" without carrying anything a user
/// wrote.
///
/// **Consent is decided exactly where it is for every other event**, by
/// handing the events to whichever `TelemetryService` the provider
/// `telemetryServiceProvider` resolved: the live one records them, the pending
/// one holds them until the consent store settles and then replays or drops
/// them, and the no-op discards them. This class has no gate of its own to get
/// wrong.
///
/// **Errors arrive before the service exists.** The handlers are installed
/// before any provider container is built, so an error during startup has
/// nowhere to go yet. Until [attach] is called the events wait in a buffer,
/// bounded by [sessionCap] because the tuple dedupe runs first; [attach] hands
/// them to the service, which applies the gate to them like any other event.
/// `telemetryServiceProvider` attaches [instance] itself, so a product wires
/// nothing beyond the handlers it already installs.
///
/// **Inert during the beta.** A build that can never transmit — `kBetaPeriod`
/// on, `TELEMETRY_DEV` off, the same condition that closes the gate
/// synchronously — does not dedupe, buffer or construct anything. A beta
/// build holds no telemetry in memory any more than it sends any.
class TelemetryUncaughtErrorCounter {
  /// Creates a counter.
  ///
  /// [inert] defaults to the dark-launch condition; tests pass `false` to
  /// exercise a post-beta build.
  TelemetryUncaughtErrorCounter({
    this.sessionCap = kTelemetryUncaughtErrorSessionCap,
    bool? inert,
  }) : inert = inert ?? (kBetaPeriod && !kTelemetryDev);

  /// The process-wide counter: the one the global error handlers report to,
  /// and the one `telemetryServiceProvider` attaches.
  ///
  /// Process-wide because a session is a process. The tuples already counted
  /// have to outlive every service the provider hands out — it replaces the
  /// pending service with the live one as the consent store settles — or a
  /// tuple would be counted once per service rather than once per session.
  static final TelemetryUncaughtErrorCounter instance =
      TelemetryUncaughtErrorCounter();

  /// Most distinct tuples recorded in one session. See
  /// [kTelemetryUncaughtErrorSessionCap].
  final int sessionCap;

  /// Whether this build can never transmit, so nothing is counted at all.
  final bool inert;

  final Set<String> _counted = <String>{};
  final List<TelemetryEvent> _unattached = <TelemetryEvent>[];
  TelemetryService? _service;
  bool _recording = false;

  /// Counts an error that reached `FlutterError.onError`.
  ///
  /// Reads the exception's type, `library` and `silent` from [details], and
  /// nothing else — not `exceptionAsString()`, not the stack, not the
  /// diagnostics the framework attached.
  void recordFlutterError(FlutterErrorDetails details) {
    _count(
      source: 'flutter',
      error: details.exception,
      library: telemetryErrorLibraryOf(details.library),
      silent: details.silent,
    );
  }

  /// Counts an error that reached `PlatformDispatcher.onError`.
  ///
  /// There is no `FlutterErrorDetails` behind such an error, so its `library`
  /// is `none` and it is never `silent`.
  void recordPlatformError(Object error) {
    _count(source: 'platform', error: error, library: 'none', silent: false);
  }

  /// Routes events to [service] from now on, handing it everything counted
  /// while nothing was attached.
  ///
  /// The service applies the consent gate to those events like any other: the
  /// live service queues them, the pending one holds them until consent is
  /// known, the no-op drops them.
  void attach(TelemetryService service) {
    try {
      _service = service;
      if (_unattached.isEmpty) return;
      final waiting = List<TelemetryEvent>.of(_unattached);
      _unattached.clear();
      waiting.forEach(service.record);
    } on Object catch (_) {
      // Swallowed by design — telemetry never throws into a feature flow.
    }
  }

  /// Stops routing to [service], if it is still the attached one.
  ///
  /// A no-op for any other service, so a container torn down after another
  /// has attached cannot detach the newer one.
  void detach(TelemetryService service) {
    if (identical(_service, service)) _service = null;
  }

  /// Events counted while no service was attached. Exposed for tests.
  @visibleForTesting
  List<TelemetryEvent> get unattached =>
      List<TelemetryEvent>.unmodifiable(_unattached);

  /// How many distinct tuples this session has counted. Exposed for tests.
  @visibleForTesting
  int get countedTuples => _counted.length;

  void _count({
    required String source,
    required Object? error,
    required String library,
    required bool silent,
  }) {
    if (inert || _recording) return;
    // Re-entrancy guard: an error raised while this one is being recorded is
    // not counted, rather than recursing through the handler that called us.
    _recording = true;
    try {
      if (_counted.length >= sessionCap) return;
      final kind = telemetryErrorKindOf(error);
      if (!_counted.add('$source/$kind/$library')) return;
      final event = TelemetryEvent(
        kTelemetryUncaughtErrorEvent,
        properties: <String, Object?>{
          'source': source,
          'kind': kind,
          'library': library,
          'silent': silent,
        },
      );
      final service = _service;
      if (service == null) {
        _unattached.add(event);
      } else {
        service.record(event);
      }
    } on Object catch (_) {
      // Swallowed by design — this runs inside the app's error handlers, where
      // a second throw would replace the error being reported.
    } finally {
      _recording = false;
    }
  }
}
