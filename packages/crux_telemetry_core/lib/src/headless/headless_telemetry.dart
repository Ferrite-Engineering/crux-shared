// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show Platform;

import 'package:crux_telemetry_core/src/headless/desktop_telemetry_store.dart';
import 'package:crux_telemetry_core/src/models/telemetry_envelope.dart';
import 'package:crux_telemetry_core/src/models/telemetry_event.dart';
import 'package:crux_telemetry_core/src/models/telemetry_policy.dart';
import 'package:crux_telemetry_core/src/services/telemetry_batch.dart';
import 'package:crux_telemetry_core/src/telemetry_endpoint.dart';
import 'package:crux_telemetry_core/src/telemetry_vocabulary.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// The public-beta flag as a headless binary sees it: the `BETA_PERIOD`
/// define, with the same default as `crux_license`'s `kBetaPeriod`.
///
/// Read here rather than imported because `crux_license` is a Flutter
/// package. `crux_telemetry`'s tests assert the two agree, so a new beta
/// cannot switch one on without the other.
const bool kHeadlessTelemetryBetaPeriod = bool.fromEnvironment(
  'BETA_PERIOD',
  // Spelled out to match `kBetaPeriod`'s declaration, which the release gate
  // reads.
  // ignore: avoid_redundant_argument_values
  defaultValue: false,
);

/// How long the first event waits for others to join it before a batch is
/// sent: long enough that a burst of calls coalesces into one row per tool
/// and outcome, short enough that a short session reports.
const Duration kHeadlessTelemetryFlushDelay = Duration(seconds: 60);

/// Per-POST timeout. A headless process must not wait on our network.
const Duration kHeadlessTelemetryPostTimeout = Duration(seconds: 5);

/// Ceiling on the last send when the process is done.
const Duration kHeadlessTelemetryCloseBudget = Duration(seconds: 5);

/// Most events held between sends; past it the oldest go.
const int kHeadlessTelemetryMaxBuffered = 500;

/// Usage counting for a product's **headless** binary (an MCP server, a
/// command-line run), under the consent the product's **desktop app**
/// recorded on this machine.
///
/// Sends only when all of these hold, asked again on every [record] and on
/// every send:
///
///  * the `CI` environment variable is not set, whatever its value;
///  * the public beta is not running ([kHeadlessTelemetryBetaPeriod]), unless
///    this is a `TELEMETRY_DEV` build;
///  * no Enterprise policy forbids it ([TelemetryPolicy.deny]);
///  * the desktop app recorded `enabled`, with an installation id beside it
///    (see [DesktopTelemetryConsent] for which edition's answer counts).
///
/// Nothing else opens it. `unset` is not consent here, although the desktop
/// disclosure's toggle starts on outside the consent-first regions: that
/// default is a position the user confirms in the app, and a machine that
/// has only ever run the headless binary has confirmed nothing. A policy's
/// `allow` does not open it either: the rule for headless binaries is the
/// desktop app's recorded consent, and nothing weaker.
///
/// Events go to the same Worker as the app's, under the app's installation
/// id, in the same batch format. They are held in memory and sent
/// [flushDelay] after the first one, and by [close]; nothing is written to
/// disk, and nothing in the desktop app's own queue is touched. A send that
/// fails keeps the events for the next window; [close] drops what it cannot
/// send within [closeBudget].
///
/// Only names reach the wire: an event whose name, property key or string
/// value is not a token of `[a-z0-9_]` (names may also hold `.`) is dropped
/// whole, so a path, an argument or a design name cannot be sent even by a
/// caller that tried.
///
/// Never throws.
class HeadlessTelemetry {
  /// Counting for [product]'s headless binary of the [pro] edition, at
  /// [appVersion], reporting [licenseTier] (a `kTelemetryLicenseTiers` name)
  /// under [policy].
  ///
  /// [environment], [consent], [client], [dev], [betaPeriod], `now` and
  /// `operatingSystem` are seams for tests; each defaults to the real thing.
  ///
  /// Throws an [ArgumentError] when [appVersion] is empty or [licenseTier] is
  /// not a name the Worker accepts: a wiring mistake, which would otherwise
  /// lose every batch to a 400 nobody sees.
  HeadlessTelemetry({
    required this.product,
    required this.pro,
    required this.appVersion,
    this.licenseTier = 'openCore',
    this.policy = TelemetryPolicy.absent,
    Map<String, String>? environment,
    DesktopTelemetryConsent? consent,
    this.client,
    this.dev = kTelemetryDev,
    this.betaPeriod = kHeadlessTelemetryBetaPeriod,
    this.flushDelay = kHeadlessTelemetryFlushDelay,
    this.postTimeout = kHeadlessTelemetryPostTimeout,
    this.closeBudget = kHeadlessTelemetryCloseBudget,
    DateTime Function()? now,
    String? operatingSystem,
  }) : environment = environment ?? Platform.environment,
       consent =
           consent ??
           DesktopTelemetryConsent(desktopTelemetryStores(product, pro: pro)),
       _now = now ?? DateTime.now,
       _os = headlessTelemetryOsSlug(
         operatingSystem ?? Platform.operatingSystem,
       ) {
    if (appVersion.isEmpty) {
      throw ArgumentError.value(appVersion, 'appVersion', 'must not be empty');
    }
    if (!kTelemetryLicenseTiers.contains(licenseTier)) {
      throw ArgumentError.value(
        licenseTier,
        'licenseTier',
        'one of ${kTelemetryLicenseTiers.join(', ')}',
      );
    }
    _sessionStart = _now();
  }

  /// The product counted.
  final CruxTelemetryProduct product;

  /// Whether this is the Pro edition's binary.
  final bool pro;

  /// The `app_version` envelope field.
  final String appVersion;

  /// The `license_tier` envelope field.
  final String licenseTier;

  /// An Enterprise policy's telemetry decision, when one governs this
  /// installation.
  final TelemetryPolicy policy;

  /// The process environment.
  final Map<String, String> environment;

  /// Where the desktop app's answer is read.
  final DesktopTelemetryConsent consent;

  /// Whether this is a `TELEMETRY_DEV` build: the staging endpoint, and the
  /// beta does not close it. The consent rule is the same.
  final bool dev;

  /// Whether the public beta is running.
  final bool betaPeriod;

  /// How long the first held event waits before a send.
  final Duration flushDelay;

  /// Per-POST timeout.
  final Duration postTimeout;

  /// Ceiling on the send [close] makes.
  final Duration closeBudget;

  /// The HTTP client to send with; `null` makes one, closed by [close].
  final http.Client? client;

  final DateTime Function() _now;
  final String _os;
  late final DateTime _sessionStart;

  final List<TelemetryEvent> _held = <TelemetryEvent>[];
  http.Client? _ownClient;
  Timer? _timer;
  Future<void>? _sending;
  bool _closed = false;

  /// Events held for the next send. For tests.
  @visibleForTesting
  List<TelemetryEvent> get held => List<TelemetryEvent>.unmodifiable(_held);

  /// Whether an event recorded now would be sent: the rule on the class, read
  /// now. Never throws.
  bool consented() {
    try {
      return !_closed && _gateOpen && consent.read().sendable;
    } on Object {
      return false;
    }
  }

  bool get _gateOpen =>
      !environment.containsKey('CI') &&
      (dev || !betaPeriod) &&
      policy != TelemetryPolicy.deny;

  /// Records one event named [name] with [properties], if [consented];
  /// otherwise does nothing. The shape of `crux_mcp`'s telemetry sink.
  void record(String name, Map<String, Object?> properties) {
    try {
      if (!_wellFormed(name, properties) || !consented()) return;
      _held.add(
        TelemetryEvent(name, properties: properties, timestamp: _now()),
      );
      if (_held.length > kHeadlessTelemetryMaxBuffered) _held.removeAt(0);
      _timer ??= Timer(flushDelay, () {
        _timer = null;
        unawaited(flush());
      });
    } on Object {
      // Telemetry never breaks a call.
    }
  }

  /// Sends what is held, if the rule on the class still holds; drops it if
  /// it no longer does. Resolves when the attempt is over. Never throws.
  Future<void> flush() {
    final running = _sending;
    if (running != null) return running;
    final attempt = _send().whenComplete(() => _sending = null);
    _sending = attempt;
    return attempt;
  }

  /// Sends what is held, within [closeBudget], and stops: nothing is
  /// recorded or sent afterwards. Call once, when the binary is done. Never
  /// throws.
  Future<void> close() async {
    if (_closed) return;
    _timer?.cancel();
    _timer = null;
    try {
      await flush().timeout(closeBudget);
    } on Object {
      // Out of budget: what was not sent is dropped.
    }
    _closed = true;
    // A failed send re-arms the window; there is no next window now.
    _timer?.cancel();
    _timer = null;
    _held.clear();
    _ownClient?.close();
    _ownClient = null;
  }

  Future<void> _send() async {
    _timer?.cancel();
    _timer = null;
    if (_held.isEmpty) return;
    try {
      final answer = _gateOpen ? consent.read() : DesktopTelemetryAnswer.none;
      if (!answer.sendable) {
        // Withdrawn since the events were recorded: they go no further.
        _held.clear();
        return;
      }
      final envelope = TelemetryEnvelope(
        installationId: answer.installationId!,
        appVersion: appVersion,
        product: product.slug,
        os: _os,
        // A headless binary runs on a desktop host; it draws no layout.
        formFactor: 'desktop',
        // It shows no language either; the package's seam default.
        locale: 'en',
        licenseTier: licenseTier,
        sessionStart: _sessionStart,
        userAgentName: product.displayName,
      );
      final snapshot = List<TelemetryEvent>.of(_held);
      final batches = buildTelemetryBatches(
        envelope,
        coalesceTelemetryEvents(snapshot),
      );
      final sender = client ?? (_ownClient ??= http.Client());
      final endpoint = telemetryEndpointFor(dev: dev);
      for (final batch in batches) {
        final response = await sender
            .post(
              endpoint,
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'User-Agent': envelope.userAgent,
              },
              body: batch.body,
            )
            .timeout(postTimeout);
        final status = response.statusCode;
        // 429 and 5xx mean "later": keep everything for the next window.
        if (status == 429 || status >= 500) {
          _rearm();
          return;
        }
        // Accepted, or refused on its merits (which a retry cannot fix):
        // either way these rows are done.
        final settled = batch.entries.map((e) => e.groupKey).toSet();
        final sent = Set<TelemetryEvent>.identity()..addAll(snapshot);
        _held.removeWhere(
          (event) =>
              sent.contains(event) &&
              settled.contains(
                telemetryGroupKey(event.name, event.properties),
              ),
        );
      }
    } on Object {
      // Transport failure or timeout: keep the events for the next window.
      _rearm();
    }
  }

  void _rearm() {
    if (_closed || _held.isEmpty) return;
    _timer ??= Timer(flushDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  static final RegExp _token = RegExp(r'^[a-z0-9_]{1,64}$');
  static final RegExp _eventName = RegExp(r'^[a-z0-9_.]{1,64}$');

  static bool _wellFormed(String name, Map<String, Object?> properties) {
    if (!_eventName.hasMatch(name)) return false;
    for (final MapEntry(:key, :value) in properties.entries) {
      if (!_token.hasMatch(key)) return false;
      final allowed = switch (value) {
        null || num() || bool() => true,
        final String token => _token.hasMatch(token),
        _ => false,
      };
      if (!allowed) return false;
    }
    return true;
  }
}
