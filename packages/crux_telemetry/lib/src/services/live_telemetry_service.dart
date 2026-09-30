// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show Directory;

import 'package:crux_telemetry/src/crux_telemetry_config.dart';
import 'package:crux_telemetry/src/models/telemetry_envelope.dart';
import 'package:crux_telemetry/src/models/telemetry_event.dart';
import 'package:crux_telemetry/src/services/telemetry_batch.dart';
import 'package:crux_telemetry/src/services/telemetry_event_queue.dart';
import 'package:crux_telemetry/src/telemetry_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Resolves the envelope for the next flush, or `null` when it cannot be
/// resolved yet.
///
/// Async because `app_version` comes from `package_info_plus`, and `null`able
/// because a flush that raced startup must skip rather than invent a version:
/// a bad `app_version` rejects the whole batch at the Worker.
typedef TelemetryEnvelopeResolver = Future<TelemetryEnvelope?> Function();

/// Subscribes [onBackgrounded] to the host's "this app is going away" signals
/// and returns the callback that cancels the subscription.
///
/// A seam purely so the volatile-mode behaviour is testable without a widget
/// binding; [observeTelemetryLifecycle] is the real one and the default.
typedef TelemetryLifecycleObserver =
    void Function() Function(void Function() onBackgrounded);

/// The default [TelemetryLifecycleObserver]: Flutter's own lifecycle surface.
///
/// Deliberately the framework's [AppLifecycleListener] rather than anything
/// from `dart:html`. On web Flutter already maps the page's visibility and
/// unload events onto [AppLifecycleState.hidden] and
/// [AppLifecycleState.detached], so the browser case needs no web-only import
/// here — and taking one would make this file unbuildable everywhere else.
///
/// `hidden`, `paused` and `detached` are all treated as "going away". They are
/// not equally final, but the distinction does not matter to a flush: the cost
/// of flushing at a tab switch that turns out to be temporary is one extra
/// POST, and the cost of waiting for something more certain is the whole
/// session, because a browser gives nothing more certain.
void Function() observeTelemetryLifecycle(void Function() onBackgrounded) {
  final listener = AppLifecycleListener(
    onStateChange: (state) {
      switch (state) {
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          onBackgrounded();
        case AppLifecycleState.resumed:
        case AppLifecycleState.inactive:
          break;
      }
    },
  );
  return listener.dispose;
}

/// How a single POST ended, from the queue's point of view.
enum _PostOutcome {
  /// The Worker took it. Drop the rows.
  accepted,

  /// The Worker refused it on its merits (a 4xx that is not a 429). The rows
  /// are malformed for this endpoint and will be malformed forever, so they
  /// are dropped too — retrying a permanent rejection is precisely the traffic
  /// the caps exist to prevent.
  rejected,

  /// Transport failure, timeout, 429, or a 5xx. Keep the rows and back off.
  failed,
}

/// The live [TelemetryService]: an in-memory buffer over an append-only disk
/// queue, flushed to the suite ingestion Worker on launch and every six hours.
///
/// **This class must never throw and never block the UI isolate** — the same
/// contract `crux_updates`' `UpdateCheckService` carries, for the same reason:
/// it sits behind call sites in feature code that record a counter and move
/// on, and a telemetry failure that breaks a feature flow is a strictly worse
/// outcome than losing the counter. Every public entry point is wrapped; every
/// I/O and network path swallows. There is no error channel out of this class
/// at all, deliberately.
///
/// The flush ordering is worth stating plainly: [start] posts the queue the
/// **previous** session left behind, and this session's events go out on the
/// next six-hourly tick or on the next launch. Nothing is sent inline with the
/// event that produced it, so no user action is ever waiting on the network,
/// and coalescing has something to coalesce.
///
/// ## Volatile mode — when the queue has no persistent backing
///
/// That ordering rests entirely on there **being** a next launch to hand the
/// queue to. Where [TelemetryEventQueue.hasPersistentBacking] is false — web,
/// and anywhere else `path_provider` cannot give the queue a file — there is
/// not one: nothing survives the process, so "the next launch ships it" means
/// "nothing is ever shipped". A six-hourly timer does not save it either,
/// because no browser session lives six hours. The launch flush in that mode
/// finds an empty queue, returns immediately, and arms nothing at all, which is
/// precisely how four products' web builds transmitted zero rows.
///
/// So when, and **only** when, the queue is volatile, this service also:
///
///  * arms a near-term flush [volatileFlushInterval] after the first
///    [record] since the last flush — one flush per window rather than one per
///    event, so a busy session still makes progress and coalescing still has
///    something to coalesce; and
///  * flushes on the host's hidden/paused/detached lifecycle signals, which for
///    a browser tab is the only warning it ever gives before it goes away.
///
/// **The persistent-queue contract is untouched.** Desktop and mobile keep
/// "the launch flush ships the previous session, then every six hours", because
/// there the file *is* the handover and a near-term cadence would buy nothing
/// but POSTs. The near-term cadence exists exactly and only where there is no
/// next launch to rely on.
///
/// The one thing [volatileFlushInterval] governs on **every** host is a flush
/// the envelope resolver **deferred** — an `app_version` or a `form_factor`
/// that is not knowable yet. That is not a cadence: it is the same flush,
/// finished late, carrying the same events it was already carrying. Leaving it
/// to the six-hourly timer would turn "retry on the next tick" into "hand the
/// queue to a next launch that races the same first frame again".
class LiveTelemetryService implements TelemetryService {
  /// Creates a service posting to [endpoint].
  ///
  /// [client] and [directoryFactory] are the two seams tests drive: a
  /// `MockClient` for the transport, a temp directory for the queue. Both
  /// default to the real thing. The timing parameters are injectable so the
  /// backoff can be exercised under `fake_async` rather than in wall time.
  /// [isWeb] defaults to the real `kIsWeb` and exists so the browser request
  /// shape can be asserted from a VM test.
  LiveTelemetryService({
    required this.endpoint,
    required this.envelopeResolver,
    http.Client? client,
    Future<Directory> Function()? directoryFactory,
    TelemetryEventQueue? queue,
    TelemetryLifecycleObserver? lifecycleObserver,
    this.isWeb = kIsWeb,
    this.flushInterval = kTelemetryFlushInterval,
    this.volatileFlushInterval = kTelemetryVolatileFlushInterval,
    this.initialRetryDelay = kTelemetryInitialRetryDelay,
    this.maxRetryDelay = kTelemetryMaxRetryDelay,
    this.postTimeout = kTelemetryPostTimeout,
    this.maxQueuedEvents = kTelemetryMaxQueuedEvents,
    this.maxEventAge = kTelemetryEventMaxAge,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _lifecycleObserver = lifecycleObserver ?? observeTelemetryLifecycle,
       _queue =
           queue ??
           TelemetryEventQueue(
             directoryFactory: directoryFactory,
             maxEvents: maxQueuedEvents,
             maxAge: maxEventAge,
           ),
       _retryDelay = initialRetryDelay;

  /// The ingest URL — production or staging, chosen by the dev-mode flag.
  /// `telemetryEndpointProvider` resolves it from `CruxTelemetryConfig`.
  final Uri endpoint;

  /// Interval between automatic flushes after the launch flush.
  final Duration flushInterval;

  /// Near-term flush cadence used **only** while the queue is volatile — see
  /// the "Volatile mode" section on the class.
  ///
  /// Ignored entirely when the queue has a file behind it, where the persistent
  /// contract ([flushInterval] plus the launch flush) is the whole story.
  final Duration volatileFlushInterval;

  /// First backoff step after a failed flush; doubles up to [maxRetryDelay].
  final Duration initialRetryDelay;

  /// Ceiling on the backoff. Reached quickly and stayed at: an installation
  /// that cannot reach the endpoint should knock roughly as often as the
  /// normal schedule would, not less and certainly not more.
  final Duration maxRetryDelay;

  /// Per-POST timeout.
  final Duration postTimeout;

  /// Hard cap on the queue.
  final int maxQueuedEvents;

  /// Age beyond which a queued event is dropped unsent.
  final Duration maxEventAge;

  /// Resolves the envelope for each flush. Called per flush rather than once,
  /// so a long-running session reports the tier and form factor it currently
  /// has rather than the ones it booted with.
  final TelemetryEnvelopeResolver envelopeResolver;

  /// Whether this service runs in a browser, where the POST must stay inside
  /// the ingestion Worker's CORS allow-list.
  ///
  /// A browser build sets no `User-Agent`. Safari and Firefox honour a
  /// page-set `User-Agent` and therefore name it in the CORS preflight, and a
  /// preflight the Worker refuses means the batch never leaves the tab — the
  /// client only ever sees `failed` and retries forever. Chrome silently drops
  /// the header, which is why only Chrome sessions ever reached the dataset.
  /// The envelope already carries the product and version the header would
  /// have said, so the browser loses nothing by omitting it.
  final bool isWeb;

  final http.Client _client;
  final TelemetryEventQueue _queue;
  final DateTime Function() _now;
  final TelemetryLifecycleObserver _lifecycleObserver;

  final List<TelemetryEvent> _pending = <TelemetryEvent>[];

  /// Serialises every disk touch. `record()` appends while a flush rewrites;
  /// without a single chain the rewrite could land between an append's read
  /// and its write and lose it.
  Future<void> _disk = Future<void>.value();

  Timer? _flushTimer;
  Timer? _retryTimer;
  Timer? _volatileTimer;
  void Function()? _cancelLifecycle;
  Duration _retryDelay;
  bool _started = false;
  bool _flushing = false;
  bool _disposed = false;
  bool _volatile = false;

  /// Events currently held in memory. Exposed for tests.
  @visibleForTesting
  List<TelemetryEvent> get pending =>
      List<TelemetryEvent>.unmodifiable(_pending);

  /// The delay the next failed flush will wait. Exposed for tests.
  @visibleForTesting
  Duration get retryDelay => _retryDelay;

  /// Whether [start] found the queue to have no file behind it — see the
  /// "Volatile mode" section on the class. Exposed for tests.
  @visibleForTesting
  bool get isVolatile => _volatile;

  @override
  void record(TelemetryEvent event) {
    // Synchronous, `void`, and total. A call site records a counter the way it
    // would increment an integer; anything that could propagate from here would
    // turn an analytics concern into a feature bug.
    try {
      if (_disposed) return;
      _pending.add(event);
      _trim();
      unawaited(_onDisk(() => _queue.append(event)));
      // Volatile only. On a persistent queue the append above IS the handover
      // and nothing here needs a near-term timer.
      if (_volatile) _armVolatileFlush();
    } on Object catch (_) {
      // Swallowed by design — see the class doc.
    }
  }

  /// Loads the previous session's queue, flushes it, and starts the periodic
  /// flush. Idempotent.
  void start() {
    try {
      if (_started || _disposed) return;
      _started = true;
      unawaited(_resumeAndFlush());
      _flushTimer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
    } on Object catch (_) {
      // Swallowed by design — see the class doc.
    }
  }

  /// Flushes the queue now. Never throws; resolves when the attempt is over.
  ///
  /// Re-entrant calls (a periodic tick landing on a slow retry) return
  /// immediately rather than queueing a second in-flight flush.
  Future<void> flush() async {
    if (_flushing || _disposed) return;
    _flushing = true;
    var deferred = false;
    try {
      // Whatever the window was for, this attempt supersedes it.
      _volatileTimer?.cancel();
      _volatileTimer = null;
      _trim();
      if (_pending.isEmpty) return;

      final envelope = await envelopeResolver();
      deferred = envelope == null;
      if (envelope == null || _disposed) return;

      // Snapshot by identity so events recorded while the POSTs are in flight
      // are neither sent twice nor dropped unsent.
      final snapshot = Set<TelemetryEvent>.identity()..addAll(_pending);
      final batches = buildTelemetryBatches(
        envelope,
        coalesceTelemetryEvents(_pending),
      );

      final settled = <String>{};
      var backOff = false;
      for (final batch in batches) {
        final outcome = await _post(envelope, batch.body);
        if (outcome == _PostOutcome.failed) {
          backOff = true;
          break;
        }
        settled.addAll(batch.entries.map((entry) => entry.groupKey));
      }

      if (settled.isNotEmpty) {
        _pending.removeWhere(
          (event) =>
              snapshot.contains(event) &&
              settled.contains(
                telemetryGroupKey(event.name, event.properties),
              ),
        );
        await _onDisk(() => _queue.replaceAll(List.of(_pending)));
      }

      if (backOff) {
        _scheduleRetry();
      } else {
        _retryDelay = initialRetryDelay;
        _retryTimer?.cancel();
        _retryTimer = null;
      }
    } on Object catch (_) {
      _scheduleRetry();
    } finally {
      _flushing = false;
      // Two reasons to arm the near-term window, and they are different claims.
      //
      // `_volatile` is the cadence itself: with no file behind the queue there
      // is no next launch, so this is how a session ever reports. It is
      // re-armed here as well as from `record` because a flush that skipped
      // recorded nothing new, and nothing else would ever arm it again.
      //
      // `deferred` is narrower and holds on **every** host: the envelope could
      // not be resolved, so a flush that was already due did not happen. Coming
      // back in a minute finishes that flush; it does not add a cadence, and in
      // particular it never sends anything inline with the event that produced
      // it — the events involved are the ones the launch flush was carrying.
      // Without it "defer and retry on the next tick" would mean the next tick
      // six hours away, and a launch flush that loses a first-frame race would
      // hand the whole queue to a next launch that races it again.
      if ((_volatile || deferred) && _pending.isNotEmpty) {
        _armVolatileFlush();
      }
    }
  }

  /// Stops the timers and persists whatever is still buffered.
  ///
  /// Not a flush: quitting the app is not the moment to wait on a network
  /// round trip. The queue file is the handover to the next launch.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushTimer?.cancel();
    _retryTimer?.cancel();
    _volatileTimer?.cancel();
    _flushTimer = null;
    _retryTimer = null;
    _volatileTimer = null;
    _cancelLifecycle?.call();
    _cancelLifecycle = null;
    unawaited(_onDisk(() => _queue.replaceAll(List.of(_pending))));
  }

  Future<void> _resumeAndFlush() async {
    try {
      // Asked before the load, because the answer decides what the rest of this
      // session's cadence is — not merely what came back this time. An empty
      // load is equally what a healthy first launch on disk returns.
      _volatile = !await _queue.hasPersistentBacking();
      if (_disposed) return;
      if (_volatile) _observeLifecycle();

      final persisted = await _queue.load(now: _now());
      if (_disposed) return;
      // The persisted events are older than anything recorded this session, so
      // they go in front — the queue stays chronological, which is what makes
      // "drop the oldest" at the cap mean what it says.
      _pending.insertAll(0, persisted);
      _trim();
      await flush();
    } on Object catch (_) {
      // Swallowed by design — see the class doc.
    }
  }

  /// Arms one near-term flush per [volatileFlushInterval] window.
  ///
  /// One flush per window rather than one per event, and deliberately not a
  /// timer that every [record] pushes further out: a session recording steadily
  /// would then never reach the end of the debounce and would report nothing at
  /// all, which is the defect this exists to fix rather than a fix for it. The
  /// window starts at the first record after a flush, so a burst still
  /// coalesces and no call site ever waits on the network.
  ///
  /// Called for volatile mode's cadence, and — on every host — to re-attempt a
  /// flush the envelope resolver deferred. See the two paragraphs in [flush].
  void _armVolatileFlush() {
    // A backoff is already scheduled and starts at a minute; a second timer for
    // the same queue would only add a POST to an endpoint that just failed.
    if (_disposed || _volatileTimer != null || _retryTimer != null) return;
    _volatileTimer = Timer(volatileFlushInterval, () {
      _volatileTimer = null;
      unawaited(flush());
    });
  }

  void _observeLifecycle() {
    try {
      _cancelLifecycle = _lifecycleObserver(() {
        if (!_disposed) unawaited(flush());
      });
    } on Object catch (_) {
      // No lifecycle surface (a bare `ProviderContainer` in a unit test, or a
      // host with no widget binding). The interval cadence still covers it.
    }
  }

  Future<_PostOutcome> _post(TelemetryEnvelope envelope, String body) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              if (!isWeb) 'User-Agent': envelope.userAgent,
            },
            body: body,
          )
          .timeout(postTimeout);
      final status = response.statusCode;
      if (status >= 200 && status < 300) return _PostOutcome.accepted;
      // 429 is the one 4xx that means "later", not "never".
      if (status == 429) return _PostOutcome.failed;
      if (status < 500) return _PostOutcome.rejected;
      return _PostOutcome.failed;
    } on Object catch (_) {
      return _PostOutcome.failed;
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retryTimer?.cancel();
    final delay = _retryDelay;
    final doubled = _retryDelay * 2;
    _retryDelay = doubled > maxRetryDelay ? maxRetryDelay : doubled;
    _retryTimer = Timer(delay, () => unawaited(flush()));
  }

  void _trim() {
    final kept = pruneTelemetryEvents(
      _pending,
      now: _now(),
      maxAge: maxEventAge,
      maxEvents: maxQueuedEvents,
    );
    if (kept.length == _pending.length) return;
    _pending
      ..clear()
      ..addAll(kept);
  }

  Future<void> _onDisk(Future<void> Function() operation) {
    final next = _disk.then((_) async {
      try {
        await operation();
      } on Object catch (_) {
        // Swallowed by design — see the class doc.
      }
    });
    _disk = next;
    return next;
  }
}
