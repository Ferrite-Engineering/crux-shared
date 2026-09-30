// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show ProcessInfo;

import 'package:crux_stats_strip/src/models/crux_memory_stats.dart';
import 'package:crux_stats_strip/src/widgets/crux_stats_strip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many RSS samples the rolling window keeps.
const int kCruxMemoryStatsWindow = 60;

/// Interval between RSS samples.
///
/// Two seconds: memory moves on the scale of a file load or a subprocess
/// spawn, not a frame, and a tighter poll would burn a timer wakeup per
/// second for a number that had not changed.
const Duration kCruxMemorySampleInterval = Duration(seconds: 2);

/// Reads the current process's resident set size, in bytes.
///
/// Injectable so tests can drive the series without depending on the real
/// process. Returns 0 when the platform cannot report it — `ProcessInfo`
/// is unavailable on web, and returning 0 lets the strip render "—" rather
/// than forcing every consumer to handle an exception.
typedef CruxResidentBytesReader = int Function();

int _defaultResidentBytes() {
  if (kIsWeb) return 0;
  try {
    return ProcessInfo.currentRss;
  } on Object {
    return 0;
  }
}

/// Overridable RSS reader.
final Provider<CruxResidentBytesReader> cruxResidentBytesReaderProvider =
    Provider<CruxResidentBytesReader>((ref) => _defaultResidentBytes);

/// Surfaces other than the strip that want live RSS sampling, by tag.
///
/// The strip is not the only reader of process memory — an App Diagnostics
/// dialog shows the same number, and a user who opens one while the strip is
/// collapsed must not be shown a permanently empty Memory section. Each
/// surface [request]s on mount and [release]s on dispose; sampling runs while
/// anyone is asking.
///
/// Tags rather than a refcount so a surface that fails to release exactly
/// once cannot drive the count negative or wedge it above zero forever — a
/// second `request('app-diagnostics')` is idempotent.
class CruxMemoryPollRequestNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  /// Registers [tag] as wanting live samples. Idempotent.
  void request(String tag) {
    if (state.contains(tag)) return;
    state = <String>{...state, tag};
  }

  /// Withdraws [tag]'s request. Idempotent.
  void release(String tag) {
    if (!state.contains(tag)) return;
    state = <String>{...state}..remove(tag);
  }
}

/// Non-strip surfaces currently requesting live RSS samples.
final NotifierProvider<CruxMemoryPollRequestNotifier, Set<String>>
cruxMemoryPollRequestProvider =
    NotifierProvider<CruxMemoryPollRequestNotifier, Set<String>>(
      CruxMemoryPollRequestNotifier.new,
    );

/// Whether anything currently wants live RSS samples: an expanded strip, or
/// any [cruxMemoryPollRequestProvider] tag.
///
/// A read-only view for tests and diagnostics. The poller does not read it:
/// [CruxMemoryStatsNotifier] listens to the two sources directly, because a
/// derived provider is recomputed only on demand and would start and stop the
/// timer one change late.
final Provider<bool> cruxMemoryPollingActiveProvider = Provider<bool>(
  (ref) =>
      ref.watch(cruxStatsStripExpandedProvider) ||
      ref.watch(cruxMemoryPollRequestProvider).isNotEmpty,
);

/// Rolling process-memory statistics, root-scope.
///
/// **Polls only while some surface is watching** — an expanded strip, or a
/// holder of a [cruxMemoryPollRequestProvider] tag. Reading RSS every two
/// seconds forever, for a readout nobody has open, is a wakeup per sample
/// bought for nothing — and in a widget test it leaves a pending timer
/// after the tree is disposed, which the test binding rightly treats as a
/// leak.
///
/// Losing the last watcher *pauses* the timer; it does not reset the
/// history. The samples live on the notifier, which is not auto-disposed,
/// so a user who expands the strip after a long session still sees the
/// climb that prompted them to look.
class CruxMemoryStatsNotifier extends Notifier<CruxMemoryStats> {
  final List<double> _recent = <double>[];
  Timer? _timer;

  @override
  CruxMemoryStats build() {
    // `listen`, deliberately not `watch`. A Notifier's build only re-runs
    // when something reads the provider, so with `watch` the timer outlived
    // the last watcher: close the App Diagnostics dialog over a collapsed
    // strip and nothing reads this again, so the "cancel on rebuild" never
    // happens and the poll runs for the rest of the session.
    //
    // The listeners are on the two *sources* rather than on the derived
    // [cruxMemoryPollingActiveProvider], because a derived Provider is
    // itself only recomputed on demand — listening to it reintroduces the
    // same laziness one level up. Notifier state changes propagate to
    // listeners eagerly, and the callback reads the derived value, which
    // forces it current.
    ref
      ..listen<bool>(
        cruxStatsStripExpandedProvider,
        (_, _) => _syncPolling(),
        fireImmediately: true,
      )
      ..listen<Set<String>>(
        cruxMemoryPollRequestProvider,
        (_, _) => _syncPolling(),
      )
      ..onDispose(_stop);

    return _recent.isEmpty
        ? CruxMemoryStats.empty
        : CruxMemoryStats(
            residentBytes: _recent.last.round(),
            recentResidentBytes: List<double>.unmodifiable(_recent),
          );
  }

  /// Starts or stops sampling to match current demand. History is untouched
  /// — a pause must not discard the samples that prompted the user to look.
  ///
  /// Recomputes demand from the two sources rather than reading
  /// [cruxMemoryPollingActiveProvider]. A source notifies its listeners
  /// *before* its dependents recompute, so reading the derived provider from
  /// inside this callback returns the pre-change value — which meant the
  /// release that should have stopped the timer promptly started a new one.
  void _syncPolling() {
    _stop();
    final active =
        ref.read(cruxStatsStripExpandedProvider) ||
        ref.read(cruxMemoryPollRequestProvider).isNotEmpty;
    if (!active) return;
    // First sample immediately so the surface shows a number as soon as it
    // opens, rather than a dash for the first two seconds.
    scheduleMicrotask(_sample);
    _timer = Timer.periodic(kCruxMemorySampleInterval, (_) => _sample());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _sample() {
    if (!ref.mounted) return;
    final bytes = ref.read(cruxResidentBytesReaderProvider)();
    if (bytes <= 0) return;
    _recent.add(bytes.toDouble());
    if (_recent.length > kCruxMemoryStatsWindow) _recent.removeAt(0);
    state = CruxMemoryStats(
      residentBytes: bytes,
      recentResidentBytes: List<double>.unmodifiable(_recent),
    );
  }

  /// Takes a sample immediately, outside the timer cadence.
  @visibleForTesting
  void sampleNow() => _sample();
}

/// The app-wide process-memory statistics.
final NotifierProvider<CruxMemoryStatsNotifier, CruxMemoryStats>
cruxMemoryStatsProvider =
    NotifierProvider<CruxMemoryStatsNotifier, CruxMemoryStats>(
      CruxMemoryStatsNotifier.new,
    );
