// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('Debouncer', () {
    test('fires once after the trailing delay', () {
      fakeAsync((async) {
        final d = Debouncer();
        var fired = 0;
        d.run(() => fired++);
        expect(d.isActive, isTrue);

        async.elapse(const Duration(milliseconds: 199));
        expect(fired, 0, reason: 'no fire before the trailing delay elapses');

        async.elapse(const Duration(milliseconds: 1));
        expect(fired, 1, reason: 'fires exactly once once the delay elapses');
        expect(d.isActive, isFalse);

        d.dispose();
      });
    });

    test('rapid calls collapse to one trailing fire with the last value', () {
      fakeAsync((async) {
        final d = Debouncer();
        var fired = 0;
        var lastValue = '';
        for (final v in ['a', 'ab', 'abc']) {
          d.run(() {
            fired++;
            lastValue = v;
          });
          async.elapse(const Duration(milliseconds: 50)); // < duration
        }
        expect(fired, 0, reason: 'no fire while calls keep arriving');

        async.elapse(const Duration(milliseconds: 200));
        expect(fired, 1, reason: 'exactly one trailing fire for the burst');
        expect(lastValue, 'abc', reason: 'fires with the most recent value');

        d.dispose();
      });
    });

    test('a settled call fires, then a later call fires again', () {
      fakeAsync((async) {
        final d = Debouncer();
        var fired = 0;
        d.run(() => fired++);
        async.elapse(const Duration(milliseconds: 200));
        expect(fired, 1);

        d.run(() => fired++);
        async.elapse(const Duration(milliseconds: 200));
        expect(fired, 2);

        d.dispose();
      });
    });

    test('cancel() drops the pending call', () {
      fakeAsync((async) {
        final d = Debouncer()
          ..run(() => fail('the cancelled call must not fire'))
          ..cancel();
        expect(d.isActive, isFalse);

        async.elapse(const Duration(milliseconds: 500));

        d.dispose();
      });
    });

    test('cancel() is a no-op when nothing is pending', () {
      fakeAsync((async) {
        final d = Debouncer();
        expect(d.cancel, returnsNormally);
        expect(d.isActive, isFalse);
        d.dispose();
      });
    });

    test('flush() runs a pending call immediately, exactly once', () {
      fakeAsync((async) {
        final d = Debouncer();
        var fired = 0;
        var lastValue = '';
        d.run(() {
          fired++;
          lastValue = 'queued';
        });

        async.elapse(const Duration(milliseconds: 10)); // well inside the delay
        d.flush();
        expect(fired, 1, reason: 'flush runs the queued action right away');
        expect(lastValue, 'queued');
        expect(d.isActive, isFalse);

        // The delay that would otherwise have fired the action must not
        // still be armed — a second fire here would be a double-invocation.
        async.elapse(const Duration(milliseconds: 500));
        expect(
          fired,
          1,
          reason: 'flush must not leave the timer able to also fire',
        );

        d.dispose();
      });
    });

    test('flush() is a no-op when nothing is pending', () {
      fakeAsync((async) {
        final d = Debouncer();
        expect(d.flush, returnsNormally);
        d.dispose();
      });
    });

    test('dispose() cancels a pending call so it never fires', () {
      fakeAsync((async) {
        Debouncer()
          ..run(() => fail('a call pending at dispose() must not fire'))
          ..dispose();

        async.elapse(const Duration(milliseconds: 500));
      });
    });

    test('cancel() after dispose() is safe', () {
      fakeAsync((async) {
        final d = Debouncer()..dispose();
        expect(d.cancel, returnsNormally);
      });
    });

    // Chosen contract (documented on Debouncer.dispose): a call to run() or
    // flush() after dispose() asserts, so a callback wired to a disposed
    // owner is caught in debug/test builds rather than silently scheduling a
    // Timer that would fire into nothing. Release builds strip the assert,
    // so the same call is a no-op there.
    test('run() after dispose() asserts', () {
      final d = Debouncer()..dispose();
      expect(() => d.run(() {}), throwsA(isA<AssertionError>()));
    });

    test('flush() after dispose() asserts', () {
      final d = Debouncer()..dispose();
      expect(d.flush, throwsA(isA<AssertionError>()));
    });
  });
}
