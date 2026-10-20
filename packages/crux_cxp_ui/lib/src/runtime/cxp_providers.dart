// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_product_binding.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_runtime.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_settings.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

// The CXP lifecycle as Riverpod providers, all in the root container.
//
// A product overrides two, in its root ProviderScope:
//
//   cxpProductBindingProvider   who it is (required)
//   cxpLaunchSettingsProvider   the settings it loaded before runApp
//
// and, where it has them, cxpRequestHandlerProvider (what it does when a peer
// asks), cxpProductVersionProvider, cxpAttentionRequesterProvider and
// cxpPeerFilterProvider. Everything else is shared.

/// Who this product is on CXP. Every product overrides it; reading it
/// without an override is a wiring error.
final Provider<CxpProductBinding> cxpProductBindingProvider =
    Provider<CxpProductBinding>(
      (_) => throw StateError(
        'cxpProductBindingProvider is not overridden: the product must bind '
        'its CxpProductBinding in its root ProviderScope.',
      ),
      name: 'cxpProductBindingProvider',
    );

/// The product's handlers for what peers send. Defaults to handling
/// nothing (every request is acknowledged as unsupported).
final Provider<CxpRequestHandler> cxpRequestHandlerProvider =
    Provider<CxpRequestHandler>(
      (_) => const CxpRequestHandler(),
      name: 'cxpRequestHandlerProvider',
    );

/// The version reported to peers; `dev` unless the product overrides it
/// with its build information.
final FutureProvider<String> cxpProductVersionProvider = FutureProvider<String>(
  (_) async => 'dev',
  name: 'cxpProductVersionProvider',
);

/// Asks the window manager for the user's attention (a dock bounce, a
/// taskbar flash) when a peer's request is honoured and the setting is on.
/// Null (the default) asks for nothing.
final Provider<void Function()?> cxpAttentionRequesterProvider =
    Provider<void Function()?>(
      (_) => null,
      name: 'cxpAttentionRequesterProvider',
    );

/// Which peers are offered anywhere: the panel, the badge and every
/// cross-probe menu read the one filtered list. Defaults to every peer; a
/// product applies an organization's allowlist here.
final Provider<bool Function(PeerIdentity peer)> cxpPeerFilterProvider =
    Provider<bool Function(PeerIdentity peer)>(
      (_) => _allowEveryPeer,
      name: 'cxpPeerFilterProvider',
    );

bool _allowEveryPeer(PeerIdentity _) => true;

/// Whether this build has a CXP transport: loopback sockets and the shared
/// discovery directory. False in a browser, where nothing below runs.
final Provider<bool> cxpTransportAvailableProvider = Provider<bool>(
  (_) => !kIsWeb,
  name: 'cxpTransportAvailableProvider',
);

/// The suite-shared discovery directory. Tests override it with a temp
/// directory. Never an app-container path: no other product would scan it.
final FutureProvider<String> cxpManifestDirectoryProvider =
    FutureProvider<String>(
      (_) async => sharedCxpManifestDirectory(),
      name: 'cxpManifestDirectoryProvider',
    );

/// Where [CxpSettings] are saved, under the product's own keys.
final Provider<SettingsService<CxpSettings>> cxpSettingsServiceProvider =
    Provider<SettingsService<CxpSettings>>(
      (ref) => SettingsService<CxpSettings>(
        ref.watch(cxpProductBindingProvider).settingsCodec,
      ),
      name: 'cxpSettingsServiceProvider',
    );

/// Loads the saved CXP settings, for a product's `main` to await before
/// `runApp` and hand to [cxpLaunchSettingsProvider].
Future<CxpSettings> loadCxpLaunchSettings(CxpProductBinding binding) async {
  try {
    return await SettingsService<CxpSettings>(binding.settingsCodec).load();
  } on Object {
    return binding.settingsCodec.defaults;
  }
}

/// The settings the product loaded before `runApp`
/// ([loadCxpLaunchSettings]). Null (not overridden) makes the settings load
/// in the background, during which the server stays off: a launch with CXP
/// off never starts the server or writes a manifest, even briefly, either
/// way.
final Provider<CxpSettings?> cxpLaunchSettingsProvider = Provider<CxpSettings?>(
  (_) => null,
  name: 'cxpLaunchSettingsProvider',
);

/// The live CXP settings. Each setter saves at once.
final NotifierProvider<CxpSettingsNotifier, CxpSettings> cxpSettingsProvider =
    NotifierProvider<CxpSettingsNotifier, CxpSettings>(
      CxpSettingsNotifier.new,
      name: 'cxpSettingsProvider',
    );

/// Backs [cxpSettingsProvider].
///
/// The port rule, the same in every product: a valid new port restarts a
/// running server on it at once; with the server off it is saved and used
/// at the next start.
class CxpSettingsNotifier extends Notifier<CxpSettings> {
  final Completer<void> _loaded = Completer<void>();

  /// Completes once the saved settings are in [state].
  Future<void> get loaded => _loaded.future;

  @override
  CxpSettings build() {
    final launch = ref.read(cxpLaunchSettingsProvider);
    if (launch != null) {
      _loaded.complete();
      return launch;
    }
    unawaited(_load());
    // Off until the saved value is known.
    return ref
        .read(cxpProductBindingProvider)
        .settingsCodec
        .defaults
        .copyWith(enabled: false);
  }

  Future<void> _load() async {
    CxpSettings value;
    try {
      value = await ref.read(cxpSettingsServiceProvider).load();
    } on Object {
      value = ref.read(cxpProductBindingProvider).settingsCodec.defaults;
    }
    if (!ref.mounted) return;
    state = value;
    if (!_loaded.isCompleted) _loaded.complete();
  }

  Future<void> _update(CxpSettings next) async {
    await loaded;
    if (!ref.mounted || next == state) return;
    state = next;
    try {
      await ref.read(cxpSettingsServiceProvider).save(next);
    } on Object {
      // No preferences backend: the change holds for this session.
    }
  }

  /// Turns the server on or off.
  Future<void> setEnabled({required bool enabled}) =>
      _update(state.copyWith(enabled: enabled));

  /// Changes the port; an invalid port is ignored.
  Future<void> setPort(int port) async {
    if (!CxpSettings.isValidPort(port)) return;
    await _update(state.copyWith(port: port));
  }

  /// Turns the attention request on or off.
  Future<void> setRequestAttention({required bool requestAttention}) =>
      _update(state.copyWith(requestAttention: requestAttention));

  /// Turns the automatic selection broadcast on or off.
  Future<void> setBroadcastSelection({required bool broadcastSelection}) =>
      _update(state.copyWith(broadcastSelection: broadcastSelection));
}

/// The running CXP runtime, or null when CXP is off, there is no transport,
/// or it has not started yet.
///
/// Rebuilt only when the enable flag or the port changes, never on the
/// other two settings. The previous runtime is stopped (goodbye sent,
/// manifest removed) before the next one binds.
final FutureProvider<CxpRuntime?> cxpRuntimeProvider =
    FutureProvider<CxpRuntime?>((ref) async {
      if (!ref.watch(cxpTransportAvailableProvider)) return null;
      final (:enabled, :port) = ref.watch(
        cxpSettingsProvider.select((s) => (enabled: s.enabled, port: s.port)),
      );
      if (!enabled) return null;
      final binding = ref.watch(cxpProductBindingProvider);
      final directory = await ref.watch(cxpManifestDirectoryProvider.future);
      final version = await ref.watch(cxpProductVersionProvider.future);
      final runtime = CxpRuntime(
        binding: binding,
        productVersion: version,
        manifestDirectory: directory,
        port: port,
        handler: () => ref.read(cxpRequestHandlerProvider),
        onAttention: () => ref.read(cxpAttentionRequesterProvider)?.call(),
        attentionEnabled: () => ref.read(cxpSettingsProvider).requestAttention,
      );
      // Registered before start(), so a superseded build stops a runtime whose
      // start is still in flight instead of orphaning its socket.
      ref.onDispose(() => unawaited(runtime.dispose()));
      await runtime.start();
      return runtime;
    }, name: 'cxpRuntimeProvider');

/// What Settings shows under the CXP controls.
typedef CxpServerStatus = ({bool running, int? port, String? problem});

/// The server's state for the settings status row.
final Provider<CxpServerStatus> cxpServerStatusProvider =
    Provider<CxpServerStatus>((ref) {
      final runtime = ref.watch(cxpRuntimeProvider).value;
      if (runtime == null) return (running: false, port: null, problem: null);
      return (
        running: runtime.isAvailable,
        port: runtime.boundPort,
        problem: runtime.unavailableReason,
      );
    }, name: 'cxpServerStatusProvider');

/// The connected peers, filtered by [cxpPeerFilterProvider]. Empty whenever
/// the server is off: the cross-probe panel, the toolbar badge and every
/// cross-probe menu read this one list.
final StreamProvider<List<PeerIdentity>> cxpPeersStreamProvider =
    StreamProvider<List<PeerIdentity>>((ref) async* {
      final runtime = ref.watch(cxpRuntimeProvider).value;
      if (runtime == null) {
        yield const <PeerIdentity>[];
        return;
      }
      final allowed = ref.watch(cxpPeerFilterProvider);
      List<PeerIdentity> filter(List<PeerIdentity> peers) =>
          List<PeerIdentity>.unmodifiable(peers.where(allowed));
      yield filter(runtime.peers);
      await for (final peers in runtime.peerChanges) {
        yield filter(peers);
      }
    }, name: 'cxpPeersStreamProvider');

/// [cxpPeersStreamProvider]'s latest value, synchronously; empty until the
/// first snapshot.
final Provider<List<PeerIdentity>> cxpPeersProvider =
    Provider<List<PeerIdentity>>(
      (ref) =>
          ref.watch(cxpPeersStreamProvider).value ?? const <PeerIdentity>[],
      name: 'cxpPeersProvider',
    );

/// The toolbar badge's number: connected peers.
final Provider<int> cxpConnectedPeerCountProvider = Provider<int>(
  (ref) => ref.watch(cxpPeersProvider).length,
  name: 'cxpConnectedPeerCountProvider',
);

/// Peers discovered but not reachable. Empty when the server is off, and
/// so cleared by every stop and restart; an entry leaves when its peer
/// connects or goes away.
final StreamProvider<List<CxpDialFailure>> cxpUnreachablePeersProvider =
    StreamProvider<List<CxpDialFailure>>((ref) async* {
      final runtime = ref.watch(cxpRuntimeProvider).value;
      if (runtime == null) {
        yield const <CxpDialFailure>[];
        return;
      }
      yield runtime.unreachablePeers;
      yield* runtime.unreachableChanges;
    }, name: 'cxpUnreachablePeersProvider');

/// How many events the panel's log keeps.
const int kCxpEventLogCapacity = 200;

/// The cross-probe event log, oldest first, across server restarts. Only
/// the user's Clear empties it.
final NotifierProvider<CxpEventLog, List<CrossProbeEvent>> cxpEventLogProvider =
    NotifierProvider<CxpEventLog, List<CrossProbeEvent>>(
      CxpEventLog.new,
      name: 'cxpEventLogProvider',
    );

/// Backs [cxpEventLogProvider].
class CxpEventLog extends Notifier<List<CrossProbeEvent>> {
  StreamSubscription<CrossProbeEvent>? _subscription;

  @override
  List<CrossProbeEvent> build() {
    ref
      ..listen<AsyncValue<CxpRuntime?>>(cxpRuntimeProvider, (_, next) {
        _follow(next.value);
      }, fireImmediately: true)
      ..onDispose(() => unawaited(_subscription?.cancel()));
    return const <CrossProbeEvent>[];
  }

  void _follow(CxpRuntime? runtime) {
    unawaited(_subscription?.cancel());
    _subscription = runtime?.events.listen(add);
  }

  /// Appends [event], dropping the oldest past [kCxpEventLogCapacity].
  void add(CrossProbeEvent event) {
    final next = <CrossProbeEvent>[...state, event];
    final overflow = next.length - kCxpEventLogCapacity;
    state = List<CrossProbeEvent>.unmodifiable(
      overflow > 0 ? next.sublist(overflow) : next,
    );
  }

  /// Empties the log.
  void clear() => state = const <CrossProbeEvent>[];
}

/// Reads a provider: `ref.read` of a `Ref`, a `WidgetRef` or a container.
typedef CxpProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Announces [message] to every peer when the user has automatic selection
/// broadcast on; a no-op otherwise or when the server is off. Products call
/// it from their selection listeners, passing `ref.read`.
void broadcastCxpSelection(CxpProviderReader read, NotifySelection message) {
  if (!read(cxpSettingsProvider).broadcastSelection) return;
  read(cxpRuntimeProvider).value?.broadcast(message);
}
