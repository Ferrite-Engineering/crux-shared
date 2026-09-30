// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/src/line_framing.dart';
import 'package:test/test.dart';

Future<List<String>> _split(
  List<String> chunks, {
  int maxLineLength = defaultCxpMaxLineLength,
}) => Stream.fromIterable(
  chunks,
).transform(CappedLineSplitter(maxLineLength: maxLineLength)).toList();

void main() {
  group('CappedLineSplitter', () {
    test('splits lines that span chunk boundaries', () async {
      final lines = await _split(['ab', 'c\nde', 'f\n', 'g\nh']);
      expect(lines, ['abc', 'def', 'g', 'h']);
    });

    test('strips a trailing carriage return', () async {
      final lines = await _split(['a\r\nb\n']);
      expect(lines, ['a', 'b']);
    });

    test('emits trailing data without a final newline', () async {
      final lines = await _split(['a\nrest']);
      expect(lines, ['a', 'rest']);
    });

    test('errors on a terminated line exceeding the cap', () {
      expect(
        _split(['${'x' * 32}\n'], maxLineLength: 16),
        throwsFormatException,
      );
    });

    test('errors on an unterminated line exceeding the cap', () {
      // The overrun must be detected while buffering — before any
      // newline arrives — otherwise a peer that never terminates its
      // line grows the buffer unboundedly.
      expect(
        _split(['x' * 8, 'x' * 16], maxLineLength: 16),
        throwsFormatException,
      );
    });

    test('accepts lines exactly at the cap', () async {
      final lines = await _split(['${'x' * 16}\n'], maxLineLength: 16);
      expect(lines, ['x' * 16]);
    });

    test(
      'an over-long frame followed by more data in the SAME chunk does not '
      'add to the closed controller',
      () async {
        // fail() closes the controller immediately but can only
        // `unawaited(cancel())` upstream. Cancellation is asynchronous, so
        // the rest of this chunk — and any chunk already queued behind it
        // — still reached handleChunk, which then called controller.add on
        // a closed controller and threw StateError from inside a stream
        // data handler. This is the exact TCP shape: an over-long frame
        // and the frames after it arriving in one segment.
        await expectLater(
          _split(
            ['${'x' * 64}\nshort1\nshort2\n'],
            maxLineLength: 16,
          ),
          throwsFormatException,
          reason: 'the cap breach itself must still surface as an error',
        );
      },
    );

    test(
      'chunks that arrive after the cap breach — because cancellation has '
      'not taken effect yet — do not touch the closed controller',
      () async {
        // The splitter forwards through a non-sync controller, so every
        // emission needs a turn of the event loop to land.
        Future<void> pump() => Future<void>.delayed(Duration.zero);

        // The actual defect: fail() closes the controller immediately but
        // can only `unawaited(cancel())` upstream. Cancellation is
        // asynchronous, so a chunk already queued behind the offending one
        // still reaches handleChunk, which then called controller.add on a
        // closed controller — a StateError thrown out of a stream data
        // handler. A cooperative source (StreamController, fromIterable)
        // honours cancel promptly and cannot reproduce it; this source
        // models the in-flight window by ignoring cancel outright.
        final source = _UncancellableSource();
        final emitted = <String>[];
        final errors = <Object>[];

        source
            .transform(const CappedLineSplitter(maxLineLength: 16))
            .listen(emitted.add, onError: errors.add, cancelOnError: false);

        source.push('ok\n');
        await pump();
        expect(emitted, ['ok']);

        // Breaches the cap: the splitter fails and closes downstream.
        source.push('${'x' * 64}\n');
        await pump();
        expect(errors, hasLength(1));
        expect(errors.single, isA<FormatException>());

        // The window. Without the `failed` guard each of these throws
        // StateError('Cannot add event after closing') straight out of
        // the data handler.
        expect(
          () => source
            ..push('short1\n')
            ..push('short2\n'),
          returnsNormally,
          reason: 'a failed splitter must ignore in-flight chunks',
        );
        await pump();
        expect(
          emitted,
          ['ok'],
          reason: 'nothing may be emitted after the splitter has failed',
        );
      },
    );

    test('emits no further lines after the cap is breached', () async {
      final emitted = <String>[];
      Object? error;
      final done = Completer<void>();
      Stream<String>.fromIterable([
            'ok\n',
            '${'x' * 64}\nafter1\nafter2\n',
          ])
          .transform(const CappedLineSplitter(maxLineLength: 16))
          .listen(
            emitted.add,
            onError: (Object e) {
              error ??= e;
            },
            onDone: done.complete,
            cancelOnError: false,
          );
      await done.future;
      expect(error, isA<FormatException>());
      expect(
        emitted,
        ['ok'],
        reason: 'a failed splitter is terminal — no post-failure lines',
      );
    });
  });
}

/// A `Stream<String>` whose subscription ignores `cancel()`, so chunks
/// keep being delivered after a downstream transformer has torn itself
/// down.
///
/// This is not a pathological source — it is the in-flight window every
/// real socket has, made deterministic. `StreamSubscription.cancel` is
/// asynchronous, so between a transformer calling it and it taking effect
/// the source may legitimately deliver more data.
class _UncancellableSource extends Stream<String> {
  void Function(String)? _onData;

  /// Deliver a chunk to the current listener, if any.
  void push(String chunk) => _onData?.call(chunk);

  @override
  StreamSubscription<String> listen(
    void Function(String)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    return _NoopSubscription<String>();
  }
}

class _NoopSubscription<T> implements StreamSubscription<T> {
  @override
  Future<void> cancel() async {}

  @override
  bool get isPaused => false;

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  void onData(void Function(T)? handleData) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  void onError(Function? handleError) {}

  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}
