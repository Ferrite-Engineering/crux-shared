// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:crux_yosys/src/process_registry.dart';

/// How a subprocess run ended. [exited] is the normal case (the process
/// reached its own exit, whatever the code); [timedOut] and [cancelled]
/// mean the runner killed the process before it exited on its own.
enum ProcessTermination {
  /// The process exited on its own. [ProcessRunResult.exitCode] is the
  /// real exit status (which may itself be non-zero).
  exited,

  /// The process exceeded the supplied `timeout` and was killed.
  timedOut,

  /// The supplied `cancelSignal` fired and the process was killed.
  cancelled,
}

/// Minimal abstraction over subprocess execution so unit tests can inject a
/// fake runner instead of spawning real subprocesses.
///
/// The shape mirrors [ProcessResult] closely: callers receive an exit
/// code plus stdout/stderr as strings, and a [ProcessTermination] saying
/// whether the process exited on its own or was killed by the runner.
/// Implementations are responsible for picking a sensible encoding (UTF-8
/// is the default everywhere).
///
/// `timeout` and `cancelSignal` bound the process lifetime. A real runner
/// spawns the process with a kill handle and terminates it when the budget
/// elapses or the signal fires, so a hung child can never block the calling
/// future indefinitely. Callers that spawn a tool which may hang — on a
/// stalled network mount, or blocked reading stdin — should always pass at
/// least a `timeout`.
///
/// Nothing in this abstraction is specific to any one tool; it is the
/// domain-neutral core of this package.
abstract class ProcessRunner {
  /// Runs [executable] with [arguments] and returns the captured result.
  ///
  /// Throws on the same conditions as [Process.start] — notably a
  /// [ProcessException] when the binary is not found. The calling service
  /// decides how to surface that to the user.
  ///
  /// When [timeout] is non-null and the process has not exited within
  /// that budget, the runner kills it (`SIGKILL`) and returns a result
  /// with [ProcessRunResult.termination] == [ProcessTermination.timedOut].
  /// When [cancelSignal] completes before the process exits, the runner
  /// kills it and returns [ProcessTermination.cancelled]. The returned
  /// exit code in those cases is the OS-reported status of the killed
  /// process and should be ignored in favor of [ProcessRunResult.termination].
  ///
  /// When [stdoutFilePath] is non-null, the child's stdout is streamed
  /// verbatim to that file instead of being captured into
  /// [ProcessRunResult.stdout], and the returned `stdout` is empty. This
  /// is for tools whose stdout *is* the payload rather than a log — a
  /// `ghdl --synth --out=verilog` emission, say — which must survive
  /// intact rather than be bounded/truncated the way captured log output
  /// is. stderr is still captured (bounded) so diagnostics remain
  /// available. The caller owns the file and is responsible for deleting
  /// it. Implementations that do not spawn real processes may ignore this.
  ///
  /// When [onStderrLine] is non-null it is invoked with each complete
  /// stderr line **as it arrives**, in addition to the bounded capture in
  /// [ProcessRunResult.stderr]. This is the hook for live progress: a tool
  /// that announces its phases on stderr (Yosys printing
  /// `2.1. Executing HIERARCHY pass`) can drive a running-now readout
  /// instead of the caller learning everything only at exit. The callback
  /// runs on the drain subscription, so it must be cheap and must not
  /// throw — an exception there would tear down the capture and lose the
  /// diagnostics the run exists to produce.
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  });
}

/// Plain data: the captured outcome of a [ProcessRunner.run] call.
class ProcessRunResult {
  /// Creates a result. [termination] defaults to [ProcessTermination.exited]
  /// and the truncation flags default to false, so existing call sites and
  /// fakes that only set exit code + streams keep compiling unchanged.
  const ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.termination = ProcessTermination.exited,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
  });

  /// Process exit code. `0` is conventional success. Meaningful only when
  /// [termination] is [ProcessTermination.exited]; for a killed process it
  /// is whatever the OS reported for the terminated child.
  final int exitCode;

  /// Captured stdout, decoded as UTF-8 (malformed bytes tolerated). May be
  /// truncated — see [stdoutTruncated].
  final String stdout;

  /// Captured stderr, decoded as UTF-8 (malformed bytes tolerated). May be
  /// truncated — see [stderrTruncated].
  final String stderr;

  /// Whether the process exited on its own or was killed by the runner.
  final ProcessTermination termination;

  /// True when [stdout] omits part of what the process actually wrote
  /// because the capture limit was reached. The retained text keeps the
  /// head and the tail, with a marker naming the omitted amount in between.
  final bool stdoutTruncated;

  /// True when [stderr] was truncated. See [stdoutTruncated].
  final bool stderrTruncated;
}

/// Default production runner that spawns the process via [Process.start]
/// so it retains a kill handle. (`Process.run` is unusable here because it
/// offers no way to terminate a hung child.) stdout/stderr are drained
/// concurrently to avoid the OS pipe buffer filling and wedging the child.
/// Available only off the web target since `dart:io` is required.
///
/// Captured output is bounded: a verbose run on a large input can emit
/// hundreds of megabytes, and joining all of it grows the parent heap to
/// match for output no human will read. Both streams are still drained in
/// full — that is what keeps the child from wedging — but only the head and
/// tail are retained. See [outputHeadLimit] and [outputTailLimit].
///
/// Every spawned process is registered with a [ProcessRegistry] for the
/// duration of the run so a host can terminate orphans at shutdown.
class DefaultProcessRunner implements ProcessRunner {
  /// Creates a runner.
  ///
  /// [registry] defaults to [ProcessRegistry.instance]. Pass an explicit
  /// registry in tests, or when a host wants shutdown termination scoped to
  /// a subsystem rather than the whole process.
  ///
  /// [spawnHost] defaults to `SpawnHost.current()`. Pass one in tests to run
  /// the Windows resolution on any machine.
  const DefaultProcessRunner({
    this.outputHeadLimit = defaultOutputHeadLimit,
    this.outputTailLimit = defaultOutputTailLimit,
    this.registry,
    this.drainGrace = defaultDrainGrace,
    this.spawnHost,
  });

  /// Default number of leading characters retained per stream (256 KiB).
  /// The head holds the banner and the first errors, which is where the
  /// actionable content of a failing run almost always is.
  static const int defaultOutputHeadLimit = 256 * 1024;

  /// Default number of trailing characters retained per stream (256 KiB).
  /// The tail holds the summary and the final error, which is where the
  /// actionable content of a run that fails late almost always is.
  static const int defaultOutputTailLimit = 256 * 1024;

  /// Leading characters retained per stream before truncation begins.
  final int outputHeadLimit;

  /// Trailing characters retained per stream when truncation occurs.
  final int outputTailLimit;

  /// Registry the spawned process is recorded in for the duration of the
  /// run. Null means [ProcessRegistry.instance].
  final ProcessRegistry? registry;

  /// The host the executable is resolved against before it is spawned. Null
  /// means `SpawnHost.current()`, the live process.
  ///
  /// On Windows a bare name is resolved to an absolute path on the `PATH` the
  /// child will get, and a name nothing on that `PATH` answers to throws the
  /// same [ProcessException] a missing binary does, with nothing spawned.
  /// Off Windows the name is spawned as given.
  final SpawnHost? spawnHost;

  /// How long to keep waiting for stdout/stderr to reach EOF after the
  /// process itself has exited.
  ///
  /// Normally EOF arrives immediately — at most a pipe buffer's worth of
  /// bytes is left, so this never comes into play. The grace exists for the
  /// case where a killed process left a grandchild holding the inherited
  /// pipe open, which would otherwise make [run] hang indefinitely *after*
  /// a timeout had already fired. It is the difference between a bounded
  /// run and a bounded-looking one.
  ///
  /// This is the worst-case tail added to [run] beyond `timeout`, so a
  /// caller on a user-facing path may want it shorter.
  final Duration drainGrace;

  // Tolerate malformed bytes rather than throwing: tool logs are usually
  // ASCII, but a corrupt include or a non-UTF-8 source comment must not
  // crash the capture.
  static const Utf8Decoder _decoder = Utf8Decoder(allowMalformed: true);

  /// Default value for [drainGrace].
  static const Duration defaultDrainGrace = Duration(seconds: 2);

  /// Subscribes to [raw], decodes it, and feeds it into [capture],
  /// completing [done] when the stream ends for any reason.
  ///
  /// A subscription rather than `forEach` so the caller can cancel it when
  /// the drain grace expires instead of leaking a live listener onto a pipe
  /// nobody is going to close.
  static StreamSubscription<String> _drain(
    Stream<List<int>> raw,
    _BoundedCapture capture,
    Completer<void> done, {
    void Function(String line)? onLine,
  }) {
    void complete() {
      if (!done.isCompleted) done.complete();
    }

    // Chunk boundaries are arbitrary, so a line can straddle two chunks.
    // Buffer the partial tail rather than emitting half a line — a
    // progress parser fed `2.1. Executing HIER` would match nothing and
    // the user would see the phase flicker or never appear.
    final pending = StringBuffer();
    void emitLines(String chunk) {
      if (onLine == null) return;
      pending.write(chunk);
      final text = pending.toString();
      final parts = text.split('\n');
      pending
        ..clear()
        ..write(parts.removeLast());
      for (final line in parts) {
        try {
          onLine(line);
        } on Object {
          // A throwing progress callback must not cancel the drain and
          // lose the diagnostics this run exists to capture.
        }
      }
    }

    return raw
        .transform(_decoder)
        .listen(
          (chunk) {
            capture.add(chunk);
            emitLines(chunk);
          },
          onDone: complete,
          // A pipe read error (the child was killed mid-write) ends the
          // capture; it is not a failure of the run itself, whose outcome
          // is decided by the exit code and termination reason.
          onError: (Object _, StackTrace _) => complete(),
          cancelOnError: true,
        );
  }

  /// Streams the raw bytes of [raw] straight to [sink] (no decoding, no
  /// bounding), completing [done] when the stream ends for any reason.
  /// Used for the [ProcessRunner.run] `stdoutFilePath` mode, where stdout
  /// is a payload that must survive intact rather than a log to be
  /// truncated.
  static StreamSubscription<List<int>> _drainToSink(
    Stream<List<int>> raw,
    IOSink sink,
    Completer<void> done,
  ) {
    void complete() {
      if (!done.isCompleted) done.complete();
    }

    return raw.listen(
      sink.add,
      onDone: complete,
      onError: (Object _, StackTrace _) => complete(),
      cancelOnError: true,
    );
  }

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) async {
    final target = registry ?? ProcessRegistry.instance;
    // A bare engine name is resolved to an absolute path first, against the
    // PATH the child will get. On Windows, CreateProcess searches the
    // launching process's current directory before PATH, and that directory
    // is often the user's repository, so a `yosys.exe` committed there would
    // otherwise run in place of the installed one. A name nothing on PATH
    // answers to throws the not-found ProcessException here, before anything
    // is spawned, which callers already report as "not installed".
    final resolved = (spawnHost ?? SpawnHost.current()).requireExecutable(
      executable,
      childEnvironment: environment,
    );
    final process = await Process.start(
      resolved,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    target.register(process);

    IOSink? stdoutSink;
    try {
      // Drain both streams eagerly so a chatty child cannot deadlock on a
      // full pipe buffer while we wait on exitCode. Draining is complete
      // even though retention is bounded.
      //
      // stdout has two modes: the default bounded string capture (for log
      // output), or — when stdoutFilePath is set — a verbatim stream to a
      // file (for output that is itself the payload and must not be
      // truncated). stderr is always captured bounded so diagnostics stay
      // available in both modes.
      _BoundedCapture? stdoutCapture;
      final stderrCapture = _BoundedCapture(outputHeadLimit, outputTailLimit);
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final StreamSubscription<Object?> stdoutSub;
      if (stdoutFilePath != null) {
        stdoutSink = File(stdoutFilePath).openWrite();
        stdoutSub = _drainToSink(process.stdout, stdoutSink, stdoutDone);
      } else {
        final capture = _BoundedCapture(outputHeadLimit, outputTailLimit);
        stdoutCapture = capture;
        stdoutSub = _drain(process.stdout, capture, stdoutDone);
      }
      final stderrSub = _drain(
        process.stderr,
        stderrCapture,
        stderrDone,
        onLine: onStderrLine,
      );

      var termination = ProcessTermination.exited;
      var settled = false;

      Timer? timer;
      if (timeout != null) {
        timer = Timer(timeout, () {
          if (!settled) {
            termination = ProcessTermination.timedOut;
            process.kill(ProcessSignal.sigkill);
          }
        });
      }

      StreamSubscription<void>? cancelSub;
      if (cancelSignal != null) {
        // `.asStream().listen` rather than `.then` so we can cancel the
        // listener once the process exits and avoid a dangling callback.
        cancelSub = cancelSignal.asStream().listen(
          (_) {
            if (!settled) {
              termination = ProcessTermination.cancelled;
              process.kill(ProcessSignal.sigkill);
            }
          },
          // A cancelSignal that completes with an error is ambiguous: the
          // caller asked to be told when to cancel, not that cancelling
          // failed. Killing on it would let an unrelated error in the
          // caller's future tear down a healthy run, so we let the process
          // finish. What we must not do is leave the error unhandled — a
          // Future error with no handler escalates to the zone's uncaught
          // handler and, in a test, fails an unrelated test.
          onError: (Object _, StackTrace _) {},
        );
      }

      final exitCode = await process.exitCode;
      settled = true;
      timer?.cancel();
      await cancelSub?.cancel();

      // Wait for the pipes to reach EOF, but only for a bounded grace.
      //
      // A process the runner killed can leave grandchildren alive that
      // inherited its stdout/stderr — a wrapper script killed while the tool
      // it spawned keeps running is the common shape. Those pipes stay open,
      // so waiting on them unconditionally hangs `run` forever *despite* the
      // timeout that just fired. The timeout is only meaningful if this wait
      // is bounded too. Whatever was captured by the deadline is returned.
      await Future.wait(<Future<void>>[
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(drainGrace, onTimeout: () => const <void>[]);
      await stdoutSub.cancel();
      await stderrSub.cancel();

      // Flush the file sink before returning so the caller sees the
      // complete payload; the close happens in the finally.
      if (stdoutSink != null) {
        try {
          await stdoutSink.flush();
        } on Exception {
          // A flush failure (disk full, killed mid-write) is reflected by
          // the exit code / termination the caller already inspects.
        }
      }

      return ProcessRunResult(
        exitCode: exitCode,
        stdout: stdoutCapture?.build() ?? '',
        stderr: stderrCapture.build(),
        termination: termination,
        stdoutTruncated: stdoutCapture?.truncated ?? false,
        stderrTruncated: stderrCapture.truncated,
      );
    } finally {
      if (stdoutSink != null) {
        try {
          await stdoutSink.close();
        } on Exception {
          // Best-effort close; the file's contents are already flushed.
        }
      }
      target.unregister(process);
    }
  }
}

/// Accumulates a text stream while retaining only a bounded head and tail.
///
/// Chunks are appended to the head until [_headLimit] characters have been
/// kept, after which they go into a sliding tail window capped at
/// [_tailLimit]. Everything that falls out of the middle is counted, not
/// kept, and reported in the marker [build] emits.
class _BoundedCapture {
  _BoundedCapture(this._headLimit, this._tailLimit);

  final int _headLimit;
  final int _tailLimit;

  final StringBuffer _head = StringBuffer();
  int _headLength = 0;

  final Queue<String> _tail = Queue<String>();
  int _tailLength = 0;

  int _dropped = 0;

  /// True when any characters were discarded from the middle.
  bool get truncated => _dropped > 0;

  void add(String chunk) {
    var remaining = chunk;
    if (_headLength < _headLimit) {
      final take = _headLimit - _headLength < remaining.length
          ? _headLimit - _headLength
          : remaining.length;
      _head.write(
        take == remaining.length ? remaining : remaining.substring(0, take),
      );
      _headLength += take;
      if (take == remaining.length) return;
      remaining = remaining.substring(take);
    }

    _tail.addLast(remaining);
    _tailLength += remaining.length;

    // Evict from the front of the tail window until it fits. Whole chunks
    // go first; the last one is sliced so the window lands exactly on the
    // limit rather than under it.
    while (_tailLength > _tailLimit && _tail.isNotEmpty) {
      final front = _tail.removeFirst();
      if (_tailLength - front.length >= _tailLimit) {
        _tailLength -= front.length;
        _dropped += front.length;
      } else {
        final excess = _tailLength - _tailLimit;
        _tail.addFirst(front.substring(excess));
        _tailLength -= excess;
        _dropped += excess;
      }
    }
  }

  String build() {
    if (_dropped == 0) return _head.toString();
    return '$_head\n'
        '[output truncated: $_dropped characters omitted]\n'
        '${_tail.join()}';
  }
}
