// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:collection';
import 'dart:ui' show PlatformDispatcher;

import 'package:crux_telemetry/crux_telemetry.dart'
    show TelemetryUncaughtErrorCounter;
import 'package:flutter/foundation.dart' show ChangeNotifier, FlutterError;
import 'package:logging/logging.dart';

/// One captured log line: the tuple stored by [CruxIssueReporterLogBuffer].
class CruxIssueLogEntry {
  /// Creates a log entry.
  const CruxIssueLogEntry({
    required this.timestamp,
    required this.level,
    required this.loggerName,
    required this.message,
  });

  /// When the record was emitted.
  final DateTime timestamp;

  /// Severity of the record.
  final Level level;

  /// Name of the [Logger] that emitted the record (empty for the root).
  final String loggerName;

  /// The log message text.
  final String message;

  @override
  String toString() =>
      'CruxIssueLogEntry(${timestamp.toIso8601String()} '
      '${level.name} $loggerName: $message)';
}

/// A fixed-capacity circular buffer of recent log records, used by the beta
/// issue reporter to attach the last lines of diagnostic output to a bug
/// report.
///
/// Registered as a `package:logging` listener in each product's `bootstrap()`
/// **before any provider is constructed**, so early-startup warnings (plugin
/// scans, workspace hydration, theme registration) are captured. When the
/// buffer overflows its [capacity], the oldest entry is dropped.
///
/// The shared [instance] is what `bootstrap()` attaches and what
/// `cruxIssueReporterLogBufferProvider` returns; tests construct their own
/// instances with a small capacity to exercise overflow behaviour.
class CruxIssueReporterLogBuffer extends ChangeNotifier {
  /// Creates a buffer holding at most [capacity] entries.
  CruxIssueReporterLogBuffer({this.capacity = defaultCapacity})
    : assert(capacity > 0, 'capacity must be positive');

  /// The default ring size: 500 entries.
  static const int defaultCapacity = 500;

  /// The process-wide buffer attached to the logging system in `bootstrap()`.
  static final CruxIssueReporterLogBuffer instance =
      CruxIssueReporterLogBuffer();

  /// Maximum number of entries retained. Older entries are evicted FIFO.
  final int capacity;

  final ListQueue<CruxIssueLogEntry> _entries = ListQueue<CruxIssueLogEntry>();
  StreamSubscription<LogRecord>? _subscription;
  bool _flutterErrorsCaptured = false;

  /// Number of entries currently held (at most [capacity]).
  int get length => _entries.length;

  /// An immutable snapshot of all retained entries, oldest first. Used by a
  /// live Logs panel, which rebuilds on [notifyListeners].
  List<CruxIssueLogEntry> get entries => List.unmodifiable(_entries);

  /// Records [entry], evicting the oldest entries past [capacity], then
  /// notifies listeners. Cheap when no UI observes.
  void add(CruxIssueLogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    notifyListeners();
  }

  /// Subscribes this buffer to [Logger.root] so every emitted record is
  /// captured. Idempotent — a second call is a no-op. Raises the root level
  /// to [Level.ALL] so debug-level context lines are retained too.
  void attachToLogging() {
    if (_subscription != null) return;
    Logger.root.level = Level.ALL;
    _subscription = Logger.root.onRecord.listen((record) {
      add(
        CruxIssueLogEntry(
          timestamp: record.time,
          level: record.level,
          loggerName: record.loggerName,
          message: record.message,
        ),
      );
    });
  }

  /// Routes uncaught Flutter framework errors ([FlutterError.onError]) and
  /// uncaught async/platform errors ([PlatformDispatcher.onError]) into
  /// [Logger.root] — and therefore into this buffer — so a crash or thrown
  /// exception during the session lands in the bug report's diagnostics
  /// section. Any previously installed handlers are chained, so existing
  /// console reporting (the red error box, console dumps) is preserved.
  ///
  /// Call once in `bootstrap()` after [attachToLogging]. Idempotent — a second
  /// call is a no-op. Each SEVERE record carries the error and its stack
  /// trace, so another [Logger.root] listener, such as a product's stderr
  /// sink, can print where the error came from; this buffer stores only the
  /// summary line. The chained handlers still dump to the console as before.
  ///
  /// Both handlers also report to [errorCounter] — by default
  /// [TelemetryUncaughtErrorCounter.instance] — which counts the error as an
  /// `app.uncaught_error` telemetry event: its class bucket, the framework
  /// library that reported it, and whether it was silent, and never its
  /// message or stack. That is the only durable trace a crash leaves in a
  /// GUI-launched release build, where stderr goes nowhere. Whether the count
  /// is ever sent is the telemetry consent gate's decision, exactly as for
  /// every other event; the counter itself is inert in a build that cannot
  /// transmit.
  void captureFlutterErrors({TelemetryUncaughtErrorCounter? errorCounter}) {
    if (_flutterErrorsCaptured) return;
    _flutterErrorsCaptured = true;
    final log = Logger('flutter');
    final counter = errorCounter ?? TelemetryUncaughtErrorCounter.instance;

    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      log.severe(details.exceptionAsString(), details.exception, details.stack);
      counter.recordFlutterError(details);
      previousFlutterOnError?.call(details);
    };

    final previousDispatcherOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      log.severe('Uncaught: $error', error, stack);
      counter.recordPlatformError(error);
      return previousDispatcherOnError?.call(error, stack) ?? false;
    };
  }

  /// Cancels the logging subscription. Mainly for tests and hot restart.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Returns up to the [count] most-recent entries, in chronological order
  /// (oldest first). When [minLevel] is given, only entries at or above that
  /// level are considered before taking the most-recent [count].
  List<CruxIssueLogEntry> recentEntries(int count, {Level? minLevel}) {
    if (count <= 0) return const [];
    final source = minLevel == null
        ? _entries
        : _entries.where((e) => e.level >= minLevel);
    final list = source.toList(growable: false);
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }

  /// Removes all retained entries and notifies listeners. Does not affect the
  /// logging subscription.
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
