// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// How long [collectProcessOutput] and [drainProcessOutput] keep reading
/// after the process has exited.
///
/// Normally both pipes reach end-of-file with the process, so this never
/// comes into play. It bounds one case: a child the process spawned outlives
/// it and still holds the inherited pipes open. Waiting on those without a
/// bound would hang the caller, and a cancel of the run, until that child
/// exits.
const Duration kProcessOutputDrainGrace = Duration(seconds: 5);

/// How many non-blank lines [ProcessOutputIncompleteException.excerpt]
/// carries at most.
const int kProcessOutputExcerptLines = 10;

/// Why the output of a process that exited could not be vouched for.
enum ProcessOutputLoss {
  /// A stream was still open when the grace after the exit ran out.
  streamStillOpen,

  /// Reading a stream failed before it reached its end.
  readFailed,
}

/// Thrown by [collectProcessOutput] and [drainProcessOutput] instead of
/// returning output that may be missing lines.
///
/// The exit code and the output of a child reach Dart on separate channels,
/// and nothing orders them: `exitCode` routinely completes while the last
/// lines (often the only lines, for a tool that prints one error and quits)
/// are still in flight. A caller that reports the output it has at that
/// moment reports a clean run for a tool that found something. The
/// alternative to this exception was a result that looked complete and was
/// not, so the output is withheld and the reason is named.
class ProcessOutputIncompleteException implements Exception {
  /// Creates the exception. [excerpt] carries the first lines that were
  /// read, so an error report can still show what the tool said.
  const ProcessOutputIncompleteException({
    required this.exitCode,
    required this.loss,
    required this.drainGrace,
    this.readError,
    this.excerpt = const <String>[],
  });

  /// The exit code the process reported. Its output, not its exit, is what
  /// could not be trusted.
  final int exitCode;

  /// What went wrong with the output.
  final ProcessOutputLoss loss;

  /// The grace that ran out, for [ProcessOutputLoss.streamStillOpen].
  final Duration drainGrace;

  /// The first read error, for [ProcessOutputLoss.readFailed].
  final Object? readError;

  /// Up to [kProcessOutputExcerptLines] non-blank lines read before the
  /// loss, stdout first.
  final List<String> excerpt;

  /// A one-sentence, tool-neutral description a caller can embed in its own
  /// failure: `exited 0 but its output was still open 5 s later, so the
  /// captured output may be incomplete`.
  String get message => switch (loss) {
    ProcessOutputLoss.streamStillOpen =>
      'exited $exitCode but its output was still open '
          '${formatDrainGrace(drainGrace)} later, so the captured output '
          'may be incomplete',
    ProcessOutputLoss.readFailed =>
      'exited $exitCode but reading its output failed ($readError), so the '
          'captured output may be incomplete',
  };

  /// `5 s` for a whole number of seconds, else `500 ms`.
  static String formatDrainGrace(Duration grace) =>
      grace.inSeconds >= 1 && grace.inMilliseconds % 1000 == 0
      ? '${grace.inSeconds} s'
      : '${grace.inMilliseconds} ms';

  @override
  String toString() => 'ProcessOutputIncompleteException: $message';
}

/// One stream of a child process read to its end.
///
/// Subscribes to `stream` at construction, so a chatty child can never stall
/// on a full pipe while its exit is awaited, and hands every event to
/// `onData`. [done] completes when the stream ends, cleanly or with an error;
/// [error] records the first error. [cancel] releases the subscription, which
/// is how a stream a grandchild keeps open is let go once the grace is spent.
///
/// `onData` runs on the subscription. An exception it throws ends the drain
/// and is recorded as a read failure rather than escaping to the zone, where
/// it would be an unhandled error in whatever happened to be awaiting.
class ProcessStreamDrain<T> {
  /// Starts draining [stream], passing each event to [onData].
  ProcessStreamDrain(Stream<T> stream, void Function(T event) onData) {
    _subscription = stream.listen(
      (event) {
        try {
          onData(event);
        } on Object catch (e) {
          _error ??= e;
          _finish();
          unawaited(_subscription.cancel());
        }
      },
      onError: (Object e, StackTrace _) {
        _error ??= e;
        _finish();
      },
      onDone: _finish,
      cancelOnError: true,
    );
  }

  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<T> _subscription;
  Object? _error;

  /// Completes when the stream has ended, cleanly or with an error.
  Future<void> get done => _done.future;

  /// Whether the stream has ended.
  bool get isDone => _done.isCompleted;

  /// The first read error, or `null` when the stream ended cleanly or has
  /// not ended.
  Object? get error => _error;

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  /// Releases the subscription. A no-op for a stream that already ended.
  Future<void> cancel() => _subscription.cancel();
}

/// Waits for every drain of a process that has exited with [exitCode] to
/// reach its end, then releases them all.
///
/// Waits at most [drainGrace] past the call. When a drain is still open after
/// that, or a drain failed rather than ended, throws
/// [ProcessOutputIncompleteException] rather than letting the caller report
/// output it cannot vouch for. [excerpt] supplies the lines the exception
/// carries, and is called only when one is thrown.
///
/// [terminatedByCaller] is asked, after the wait, whether the caller killed
/// the process itself (a timeout, a cancel). When it answers true nothing is
/// thrown: the output of a killed process is incomplete by definition, the
/// caller's result already says the process did not run to completion, and
/// the pipe a grandchild inherited is the expected reason the wait ran out.
/// The default answers false.
///
/// The drains are cancelled whatever the outcome, so the subscriptions of a
/// pipe nobody is going to close do not leak.
Future<void> drainProcessOutput({
  required int exitCode,
  required List<ProcessStreamDrain<Object?>> drains,
  Duration drainGrace = kProcessOutputDrainGrace,
  List<String> Function()? excerpt,
  bool Function()? terminatedByCaller,
}) async {
  try {
    final drained = await Future.wait(<Future<void>>[
      for (final drain in drains) drain.done,
    ]).then((_) => true).timeout(drainGrace, onTimeout: () => false);
    if (terminatedByCaller?.call() ?? false) return;
    if (!drained) {
      throw ProcessOutputIncompleteException(
        exitCode: exitCode,
        loss: ProcessOutputLoss.streamStillOpen,
        drainGrace: drainGrace,
        excerpt: excerpt?.call() ?? const <String>[],
      );
    }
    for (final drain in drains) {
      final readError = drain.error;
      if (readError != null) {
        throw ProcessOutputIncompleteException(
          exitCode: exitCode,
          loss: ProcessOutputLoss.readFailed,
          drainGrace: drainGrace,
          readError: readError,
          excerpt: excerpt?.call() ?? const <String>[],
        );
      }
    }
  } finally {
    for (final drain in drains) {
      await drain.cancel();
    }
  }
}

/// Everything one subprocess wrote, and how it exited.
class CapturedProcessOutput {
  /// Creates a [CapturedProcessOutput].
  const CapturedProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// The process exit code.
  final int exitCode;

  /// Every stdout line, in order, through end-of-file.
  final List<String> stdout;

  /// Every stderr line, in order, through end-of-file.
  final List<String> stderr;
}

/// Reads a process to completion: its exit code AND all of its output.
///
/// [stdout] and [stderr] are the child's output as lines; [exitCode] is its
/// exit. Both streams are subscribed before the exit is awaited, so a chatty
/// child can never stall on a full pipe, and the result is returned only once
/// both have reached end-of-file, not when the exit arrives. The lines that
/// arrive after the exit (which, measured on macOS, was the whole of a
/// one-line stderr report in 22 runs out of 300) are therefore in the result.
///
/// Throws [ProcessOutputIncompleteException] rather than returning output it
/// cannot vouch for: when a stream is still open [drainGrace] after the exit,
/// or when reading a stream failed. Either way the result could be missing
/// lines, and a tool whose findings are read from its output would be
/// reported clean.
///
/// The streams are released whatever the outcome.
Future<CapturedProcessOutput> collectProcessOutput({
  required Stream<String> stdout,
  required Stream<String> stderr,
  required Future<int> exitCode,
  Duration drainGrace = kProcessOutputDrainGrace,
}) async {
  final out = <String>[];
  final err = <String>[];
  final drains = <ProcessStreamDrain<String>>[
    ProcessStreamDrain<String>(stdout, out.add),
    ProcessStreamDrain<String>(stderr, err.add),
  ];
  final int code;
  try {
    code = await exitCode;
  } on Object {
    for (final drain in drains) {
      await drain.cancel();
    }
    rethrow;
  }
  await drainProcessOutput(
    exitCode: code,
    drains: drains,
    drainGrace: drainGrace,
    excerpt: () => processOutputExcerpt(<String>[...out, ...err]),
  );
  return CapturedProcessOutput(exitCode: code, stdout: out, stderr: err);
}

/// The first [kProcessOutputExcerptLines] non-blank lines of [lines], for
/// [ProcessOutputIncompleteException.excerpt].
List<String> processOutputExcerpt(Iterable<String> lines) => lines
    .where((line) => line.trim().isNotEmpty)
    .take(kProcessOutputExcerptLines)
    .toList(growable: false);
