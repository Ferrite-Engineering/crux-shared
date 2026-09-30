// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

/// Coalesces a burst of calls into a single trailing invocation.
///
/// Each [run] cancels the previously-scheduled callback and reschedules it
/// [duration] into the future, so a rapid sequence — e.g. per-keystroke filter
/// or search updates — fires the expensive reaction only once, [duration]
/// after the last call, and with the last call's value.
///
/// Owners **must** call [dispose] (typically from a widget's `dispose` or a
/// notifier's teardown) to cancel any still-pending callback. Without it, a
/// callback scheduled just before teardown fires after the owner is gone —
/// into a disposed widget's `setState`, or a notifier nobody is listening to
/// anymore.
///
/// A "Clear" or "Reset" affordance next to whatever [run] drives should call
/// [cancel] (or construct a fresh value and call [run] with the cleared
/// value) rather than leaving a prior debounced call free to fire afterward
/// and undo the clear.
///
/// Deliberately dependency-light (only `dart:async`) so it is usable from
/// widgets, notifiers, and services alike, with no Flutter dependency.
class Debouncer {
  /// Creates a debouncer with the given trailing [duration].
  Debouncer({this.duration = const Duration(milliseconds: 200)});

  /// The trailing delay measured from the most recent [run] call.
  final Duration duration;

  Timer? _timer;
  void Function()? _pending;
  bool _disposed = false;

  /// Whether a callback is currently scheduled and not yet fired.
  bool get isActive => _timer?.isActive ?? false;

  /// Schedules [action], cancelling any previously-scheduled (unfired) one.
  ///
  /// Asserts if called after [dispose]; stripped in release builds, where a
  /// post-dispose call is a no-op.
  void run(void Function() action) {
    assert(!_disposed, 'Debouncer.run() called after dispose()');
    if (_disposed) return;
    _timer?.cancel();
    _pending = action;
    _timer = Timer(duration, () {
      _pending = null;
      action();
    });
  }

  /// Cancels a pending callback without firing it. Safe to call when nothing
  /// is scheduled, and safe to call after [dispose].
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  /// Runs a pending callback immediately, exactly once, instead of waiting
  /// out the rest of [duration]. A no-op when nothing is scheduled.
  ///
  /// Asserts if called after [dispose]; stripped in release builds, where a
  /// post-dispose call is a no-op.
  void flush() {
    assert(!_disposed, 'Debouncer.flush() called after dispose()');
    if (_disposed) return;
    final action = _pending;
    if (action == null) return;
    _timer?.cancel();
    _timer = null;
    _pending = null;
    action();
  }

  /// Cancels any pending callback so it can never fire, and marks this
  /// debouncer disposed. Call from the owner's `dispose`.
  ///
  /// [run] and [flush] after [dispose] assert in debug/test builds and are a
  /// no-op in release builds — never a fresh [Timer] and never a stray fire.
  void dispose() {
    cancel();
    _disposed = true;
  }
}
