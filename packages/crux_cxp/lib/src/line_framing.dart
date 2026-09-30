// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// Default upper bound, in UTF-16 code units, on one newline-delimited
/// CXP frame.
///
/// Generous for the v1 vocabulary (selection lists, highlight requests):
/// a legitimate envelope is a few hundred bytes; even a bulk multi-select
/// stays far below 1 MiB. The cap exists so a peer that streams bytes
/// without ever sending a newline cannot make the receiver buffer
/// unboundedly.
const int defaultCxpMaxLineLength = 1024 * 1024;

/// Default upper bound, in UTF-16 code units, on the outbound bytes a
/// single peer connection may have buffered but not yet flushed.
///
/// The inbound direction has always been capped ([defaultCxpMaxLineLength]);
/// this is its outbound counterpart. `Socket` is an `IOSink`, so `write`
/// buffers in the sender's heap whenever the peer stops draining its
/// receive window — a peer that handshakes and then blocks (a modal
/// dialog, a wedged isolate) would otherwise grow the sender without
/// bound. A connection that exceeds this cap is dropped, exactly as an
/// over-long inbound frame is.
///
/// 8 MiB is ~8 000 worst-case v1 frames; the real vocabulary is
/// human-driven selection gossip, so reaching it means the peer is not
/// reading at all.
const int defaultCxpMaxPendingWriteBytes = 8 * 1024 * 1024;

/// Newline splitter with an upper bound on line length.
///
/// `dart:convert`'s `LineSplitter` buffers an unterminated line without
/// limit, so a malicious or broken peer could grow the receiver's memory
/// indefinitely by never sending `\n`. This transformer emits complete
/// lines (stripping a trailing `\r`) and raises a [FormatException] on
/// the stream as soon as a line — terminated or not — exceeds
/// [maxLineLength], then tears the pipeline down. Both `LocalCxpServer`
/// and `LocalCxpClient` treat that error as a fatal connection error and
/// drop the socket.
///
/// The implementation forwards events through a controller rather than
/// an `async*` generator: cancelling a generator parked in `await for`
/// on a silent socket only completes once the socket emits again, which
/// would wedge connection teardown. With the controller, cancelling the
/// downstream subscription cancels the socket subscription directly.
class CappedLineSplitter extends StreamTransformerBase<String, String> {
  /// Creates a splitter with the given [maxLineLength] cap.
  const CappedLineSplitter({this.maxLineLength = defaultCxpMaxLineLength});

  /// Maximum accepted line length in UTF-16 code units.
  final int maxLineLength;

  @override
  Stream<String> bind(Stream<String> stream) {
    final buffer = StringBuffer();
    late final StreamController<String> controller;
    StreamSubscription<String>? subscription;
    // Set the instant the cap is breached. Cancelling the upstream
    // subscription is asynchronous, so a chunk already queued behind the
    // offending one still reaches handleChunk after the controller has
    // been closed — adding to it would throw a StateError from inside a
    // stream data handler. The flag makes the tear-down synchronous from
    // this transformer's point of view.
    var failed = false;

    void fail(String message) {
      if (failed) return;
      failed = true;
      controller.addError(FormatException(message));
      final active = subscription;
      subscription = null;
      if (active != null) unawaited(active.cancel());
      unawaited(controller.close());
    }

    void handleChunk(String chunk) {
      if (failed) return;
      var start = 0;
      while (true) {
        final newline = chunk.indexOf('\n', start);
        if (newline < 0) {
          buffer.write(chunk.substring(start));
          if (buffer.length > maxLineLength) {
            fail(
              'Unterminated line of ${buffer.length} code units exceeds '
              'the $maxLineLength-code-unit cap.',
            );
          }
          return;
        }
        buffer.write(chunk.substring(start, newline));
        var line = buffer.toString();
        buffer.clear();
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        if (line.length > maxLineLength) {
          fail(
            'Line of ${line.length} code units exceeds the '
            '$maxLineLength-code-unit cap.',
          );
          return;
        }
        controller.add(line);
        start = newline + 1;
      }
    }

    controller = StreamController<String>(
      onListen: () {
        subscription = stream.listen(
          handleChunk,
          onError: (Object e, StackTrace s) {
            if (failed) return;
            controller.addError(e, s);
          },
          onDone: () {
            if (failed) return;
            // Trailing data without a final newline: emit it for parity
            // with LineSplitter (the cap already bounded it).
            if (buffer.isNotEmpty) {
              controller.add(buffer.toString());
            }
            unawaited(controller.close());
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
