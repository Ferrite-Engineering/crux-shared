// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A file-change event emitted by [FileWatcherService].
enum FileWatchEvent {
  /// The file was modified (written, truncated, etc.).
  modified,

  /// The file was deleted or moved away from its original path.
  deleted,
}

/// Why a [FileWatcherService] stopped watching without being asked to.
enum FileWatchStopReason {
  /// The underlying platform watch reported an error, or the watch could
  /// not be established at all (for example the parent directory does not
  /// exist).
  error,

  /// The underlying platform watch ended on its own. This is what a
  /// deleted or renamed parent directory looks like on most platforms —
  /// the directory watch simply completes and no further events arrive.
  watchClosed,
}

/// Emitted on [FileWatcherService.stopped] when a watch dies on its own.
///
/// This is the signal a host uses to take the "auto-reload is on" badge
/// down and offer a re-arm, rather than leaving the user believing a file
/// is being watched when it is not. Re-arming is just another
/// [FileWatcherService.startWatching] call with the same [path].
@immutable
class FileWatchStopped {
  /// Creates a stop record.
  const FileWatchStopped({
    required this.path,
    required this.reason,
    this.error,
    this.stackTrace,
  });

  /// The path that was being watched when the watch died.
  final String path;

  /// Why the watch ended.
  final FileWatchStopReason reason;

  /// The platform error, when [reason] is [FileWatchStopReason.error].
  final Object? error;

  /// Stack trace accompanying [error], when one was available.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      'FileWatchStopped($path, $reason${error == null ? '' : ', $error'})';
}

/// Signature for a function that returns a [Stream<FileSystemEvent>] for
/// the given [path]. Injected in tests to avoid real file-system I/O.
typedef WatchFactory = Stream<FileSystemEvent> Function(String path);

/// Signature for a function that returns the [FileStat] of [path]. Injected
/// in tests; defaults to [FileStat.statSync].
typedef FileStatReader = FileStat Function(String path);

/// Watches the containing directory and filters events down to [path].
///
/// `File(path).watch()` delivers **no events on Windows**: `dart:io`
/// file-system watching there is directory-based (`ReadDirectoryChangesW`), so
/// a single-file watch silently yields nothing (verified empirically — a
/// single-file watch produced 0 events while a parent-directory watch produced
/// the modify and delete events with the correct path). Watching the parent
/// directory and filtering to the target path is the portable approach; it
/// behaves identically on macOS/Linux, where the directory also reports child
/// modify/delete events.
Stream<FileSystemEvent> _defaultFactory(String path) {
  final target = _normalizePath(path);
  return Directory(
    File(path).parent.path,
  ).watch().where((event) => _normalizePath(event.path) == target);
}

/// Normalizes a path for comparison. Windows file systems are
/// case-insensitive and accept either separator, so fold case and separators
/// there; POSIX paths are compared verbatim.
String _normalizePath(String path) =>
    Platform.isWindows ? path.toLowerCase().replaceAll('/', r'\') : path;

/// Watches a single file for changes and emits debounced [FileWatchEvent]s.
///
/// Usage:
/// ```dart
/// final service = FileWatcherService();
/// final sub = service.events.listen((e) { ... });
/// final stops = service.stopped.listen((s) { /* offer a re-arm */ });
/// service.startWatching('/path/to/dump.vcd');
/// // ...later:
/// service.dispose();
/// ```
///
/// ## Debounce with a maximum wait
///
/// Events are coalesced over a quiet period of [debounceDelay]: a burst of
/// writes produces one [FileWatchEvent] once the writes stop. A plain quiet-
/// period debounce is not enough on its own, because the workload this
/// package exists to serve — a simulator streaming into a dump file for the
/// duration of a run — never goes quiet. Every event would restart the timer
/// and nothing would ever be emitted.
///
/// So the debounce is also bounded: once [maxWait] has elapsed since the
/// *first* event of a burst, an event is emitted regardless of whether writes
/// are still arriving. A continuously-written file therefore produces a steady
/// event roughly every [maxWait] instead of complete silence.
///
/// ## Watch death
///
/// A watch can die without anyone calling [stopWatching] — the parent
/// directory is deleted or renamed (`rm -rf build/ && mkdir build/`), the
/// platform drops the watch, or the watch could never be established because
/// the parent directory did not exist. Those cases surface on [stopped] and
/// leave [isWatching] false, so a host can tell the user auto-reload is no
/// longer live instead of silently never reloading again.
///
/// The internal [StreamController]s are broadcast, so multiple subscribers are
/// allowed. They are kept open for the lifetime of the service; call [dispose]
/// to close them.
///
/// On Flutter Web, [startWatching] is a no-op because `dart:io` file-system
/// watching is unavailable.
class FileWatcherService {
  /// Creates a watcher.
  ///
  /// [watchFactory] is injected in tests to feed deterministic
  /// [FileSystemEvent]s without touching the real filesystem.
  /// [debounceDelay] is the quiet period; [maxWait] bounds how long a
  /// sustained burst can suppress emission (see the class docs).
  ///
  /// [statReader] reads the watched file's size and modification time, which
  /// decide whether a modify event really changed it (see [events]); tests
  /// inject one alongside [watchFactory].
  FileWatcherService({
    WatchFactory? watchFactory,
    FileStatReader? statReader,
    this.debounceDelay = defaultDebounceDelay,
    this.maxWait = defaultMaxWait,
  }) : _watchFactory = watchFactory ?? _defaultFactory,
       _statReader = statReader ?? FileStat.statSync;

  /// Default quiet period before a burst of writes is reported.
  static const Duration defaultDebounceDelay = Duration(milliseconds: 500);

  /// Default upper bound on how long a sustained burst may suppress an
  /// emission. Chosen so a continuously-written dump file still drives
  /// auto-reload at a usable cadence without thrashing the host.
  static const Duration defaultMaxWait = Duration(seconds: 2);

  /// Quiet period after the last event before an emission occurs.
  final Duration debounceDelay;

  /// Upper bound on the delay between the first event of a burst and the
  /// resulting emission.
  final Duration maxWait;

  final WatchFactory _watchFactory;
  final FileStatReader _statReader;

  /// Size and modification time of the watched file when the watch started
  /// or last emitted [FileWatchEvent.modified]; null when unknown.
  ({DateTime modified, int size})? _lastSeen;
  final StreamController<FileWatchEvent> _controller =
      StreamController<FileWatchEvent>.broadcast();
  final StreamController<FileWatchStopped> _stopController =
      StreamController<FileWatchStopped>.broadcast();

  StreamSubscription<FileSystemEvent>? _fsSub;
  Timer? _debounce;
  Timer? _maxWaitTimer;
  FileWatchEvent? _pending;
  String? _watchedPath;

  /// Incremented on every [startWatching] / [stopWatching] so callbacks
  /// belonging to a superseded or deliberately-cancelled watch are ignored
  /// rather than reported as a spontaneous stop.
  int _generation = 0;

  /// Stream of file events. Subscribe before calling [startWatching].
  ///
  /// [FileWatchEvent.modified] means the file's size or modification time
  /// changed since the watch started or last reported. A modify event that
  /// leaves both as last seen is dropped: macOS writes an extended attribute
  /// to a file picked in the open dialog, and treating that as an edit raised
  /// a reload prompt for a file nobody had touched. The event's own
  /// `contentChanged` flag is not consulted, because a `touch` (a new
  /// modification time, the same bytes) arrives with it false and must still
  /// count, as it does for every build tool.
  Stream<FileWatchEvent> get events => _controller.stream;

  /// Stream of spontaneous watch deaths. A deliberate [stopWatching] or
  /// [dispose] never emits here — only a watch that ended on its own.
  Stream<FileWatchStopped> get stopped => _stopController.stream;

  /// Whether a watch is currently live. False before the first
  /// [startWatching], after [stopWatching], and after a [stopped] event.
  bool get isWatching => _fsSub != null;

  /// The path currently being watched, or null when [isWatching] is false.
  String? get watchedPath => _watchedPath;

  /// Starts watching [path] for changes.
  ///
  /// Any previously watched file is stopped first. On web, this is a no-op.
  /// Also the re-arm entry point after a [stopped] event.
  ///
  /// If the watch cannot be established — most commonly because [path]'s
  /// parent directory does not exist — this does not throw; it reports the
  /// failure on [stopped] and leaves [isWatching] false.
  void startWatching(String path) {
    stopWatching();
    if (kIsWeb) return;
    final generation = _generation;
    _watchedPath = path;
    _lastSeen = _readState(path);
    try {
      _fsSub = _watchFactory(path).listen(
        _onFsEvent,
        onError: (Object error, StackTrace stackTrace) => _onWatchDied(
          generation,
          FileWatchStopReason.error,
          error: error,
          stackTrace: stackTrace,
        ),
        onDone: () => _onWatchDied(generation, FileWatchStopReason.watchClosed),
        // A watch that errors is dead: without this, the subscription stays
        // live after the error and can keep delivering events for a watch
        // the service has already reported as stopped.
        cancelOnError: true,
      );
    } on Object catch (error, stackTrace) {
      // Establishing the watch failed outright (missing parent directory,
      // unsupported platform, permission denial). Report it rather than
      // leaving the caller believing the file is watched.
      _fsSub = null;
      _onWatchDied(
        generation,
        FileWatchStopReason.error,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops watching the current file and cancels any pending debounce timers.
  ///
  /// Safe to call when no file is being watched. Never emits on [stopped] —
  /// that stream reports only watches that died on their own.
  void stopWatching() {
    _generation++;
    _cancelTimers();
    _pending = null;
    _watchedPath = null;
    _lastSeen = null;
    unawaited(_fsSub?.cancel());
    _fsSub = null;
  }

  /// Stops watching and closes the event streams.
  ///
  /// After [dispose], calling [startWatching] will throw a [StateError]
  /// because the underlying [StreamController]s are closed.
  void dispose() {
    stopWatching();
    unawaited(_controller.close());
    unawaited(_stopController.close());
  }

  void _cancelTimers() {
    _debounce?.cancel();
    _debounce = null;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
  }

  void _onFsEvent(FileSystemEvent event) {
    _pending =
        (event.type == FileSystemEvent.delete ||
            event.type == FileSystemEvent.move)
        ? FileWatchEvent.deleted
        : FileWatchEvent.modified;

    // Restart the quiet-period timer on every event — that is the debounce.
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, _emitPending);

    // Start the ceiling timer only on the first event of a burst, and leave
    // it running across subsequent events. This is what makes the debounce
    // bounded: a stream of writes that never goes quiet still emits once
    // `maxWait` has elapsed since the burst began.
    _maxWaitTimer ??= Timer(maxWait, _emitPending);
  }

  void _emitPending() {
    _cancelTimers();
    final event = _pending;
    _pending = null;
    if (event == null) return;
    if (_controller.isClosed) return;
    if (event == FileWatchEvent.modified) {
      final path = _watchedPath;
      final now = path == null ? null : _readState(path);
      final before = _lastSeen;
      if (now != null && before != null && now == before) return;
      _lastSeen = now;
    }
    _controller.add(event);
  }

  /// The size and modification time of [path], or null when the file does
  /// not exist or cannot be read, so an unknown state never suppresses an
  /// event.
  ({DateTime modified, int size})? _readState(String path) {
    try {
      final stat = _statReader(path);
      if (stat.type == FileSystemEntityType.notFound) return null;
      return (modified: stat.modified, size: stat.size);
    } on FileSystemException {
      return null;
    }
  }

  void _onWatchDied(
    int generation,
    FileWatchStopReason reason, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // A superseded watch (startWatching called again) or a deliberate
    // stopWatching bumped the generation; its late callbacks are not news.
    if (generation != _generation) return;
    // The watch is dead: retire this generation so any further late
    // callbacks from it are ignored, and cancel the subscription so an
    // errored-but-unclosed source stream cannot keep delivering events.
    _generation++;
    unawaited(_fsSub?.cancel());
    final path = _watchedPath;
    // Flush any debounced-but-unemitted event first. The watch dying does
    // not un-observe the writes that preceded it, and in the common
    // deleted-parent-directory case the pending event is the delete itself
    // — the single most important one to deliver.
    _emitPending();
    _fsSub = null;
    _watchedPath = null;
    if (path == null) return;
    if (_stopController.isClosed) return;
    _stopController.add(
      FileWatchStopped(
        path: path,
        reason: reason,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
