// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/src/workspace.dart';
import 'package:crux_workspace/src/workspace_notifier.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps a [child] and flushes the pending workspace save when the app
/// transitions to `paused` or `detached` (i.e. backgrounded on mobile,
/// closed on desktop).
///
/// Use this as a top-level widget in the product's `MaterialApp` subtree:
///
/// ```dart
/// WorkspaceLifecycleObserver<MyPayload>(
///   provider: workspaceProvider,
///   child: MyApp(),
/// );
/// ```
///
/// The observer reads `WorkspaceNotifier.flushPendingSave` via the supplied
/// `provider`. Products that wire their own `WidgetsBindingObserver` can
/// skip this widget and call `flushPendingSave()` directly.
///
/// ### IMPORTANT: it only reaches its own scope
///
/// The observer resolves [provider] against the container it is mounted in.
/// It is mounted **above** the per-tab and per-pane scopes (that is the point
/// — it has to outlive them), so anything debounced *inside* a tab scope is
/// invisible to it and will NOT be flushed on pause/detach. On mobile, where
/// `paused` is routinely the last callback before the process is killed, that
/// is silent data loss.
///
/// Products with per-scope pending writes pass them as [additionalFlushes]:
///
/// ```dart
/// WorkspaceLifecycleObserver<MyPayload>(
///   provider: workspaceProvider,
///   additionalFlushes: [
///     // Walk the live tab containers and flush each one's pending write.
///     () => Future.wait([
///       for (final c in tabContainers.liveContainers)
///         c.read(myPerTabStoreProvider.notifier).flush(),
///     ]),
///   ],
///   child: MyApp(),
/// );
/// ```
class WorkspaceLifecycleObserver<P> extends ConsumerStatefulWidget {
  /// Creates a workspace lifecycle observer that flushes [provider] on
  /// `AppLifecycleState.paused` / `detached`.
  const WorkspaceLifecycleObserver({
    required this.provider,
    required this.child,
    this.additionalFlushes = const [],
    super.key,
  });

  /// Provider exposing the [WorkspaceNotifier] whose pending save must be
  /// flushed on lifecycle transitions.
  final AsyncNotifierProvider<WorkspaceNotifier<P>, Workspace<P>> provider;

  /// Extra flush hooks invoked alongside the workspace notifier's own
  /// pending-save flush, for state the observer's container cannot reach —
  /// per-tab and per-pane scopes above all. Each is invoked once per
  /// `paused` / `detached` transition; a hook that throws is logged and does
  /// not prevent the others from running.
  final List<Future<void> Function()> additionalFlushes;

  /// Subtree that owns the rest of the app.
  final Widget child;

  @override
  ConsumerState<WorkspaceLifecycleObserver<P>> createState() =>
      _WorkspaceLifecycleObserverState<P>();
}

class _WorkspaceLifecycleObserverState<P>
    extends ConsumerState<WorkspaceLifecycleObserver<P>>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    unawaited(_flushAll());
  }

  Future<void> _flushAll() async {
    final futures = <Future<void>>[
      ref.read(widget.provider.notifier).flushPendingSave(),
      for (final flush in widget.additionalFlushes) _guarded(flush),
    ];
    // Wait on all of them, not the first failure: one product-side hook
    // blowing up must not abandon the workspace's own pending write.
    await Future.wait(futures.map(_swallow));
  }

  Future<void> _guarded(Future<void> Function() flush) {
    try {
      return flush();
    } on Object catch (e, s) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'crux_workspace',
          context: ErrorDescription(
            'invoking a WorkspaceLifecycleObserver additionalFlushes hook',
          ),
        ),
      );
      return Future<void>.value();
    }
  }

  Future<void> _swallow(Future<void> f) {
    return f.catchError((Object e, StackTrace s) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: s,
          library: 'crux_workspace',
          context: ErrorDescription(
            'flushing pending workspace state on pause',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
