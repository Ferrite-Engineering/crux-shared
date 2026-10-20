// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_product_binding.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_runtime.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_settings.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

// The CXP lifecycle as Riverpod providers, all in the root container.
//
// A product overrides two, in its root ProviderScope:
//
//   cruxCxpProductBindingProvider   who it is (required)
//   cruxCxpLaunchSettingsProvider   the settings it loaded before runApp
//
// and, where it has them, cruxCxpRequestHandlerProvider (what it does when a
// peer asks), cruxCxpProductVersionProvider, cruxCxpAttentionRequesterProvider
// and cruxCxpPeerFilterProvider. Everything else is shared.

/// Who this product is on CXP. Every product overrides it; reading it
/// without an override is a wiring error.
final Provider<CruxCxpProductBinding>
cruxCxpProductBindingProvider = Provider<CruxCxpProductBinding>(
  (_) => throw StateError(
    'cruxCxpProductBindingProvider is not overridden: the product must bind '
    'its CruxCxpProductBinding in its root ProviderScope.',
  ),
  name: 'cruxCxpProductBindingProvider',
);

/// The product's handlers for what peers send. Defaults to handling
/// nothing (every request is acknowledged as unsupported).
final Provider<CruxCxpRequestHandler> cruxCxpRequestHandlerProvider =
    Provider<CruxCxpRequestHandler>(
      (_) => const CruxCxpRequestHandler(),
      name: 'cruxCxpRequestHandlerProvider',
    );

/// The version reported to peers; `dev` unless the product overrides it
/// with its build information.
final FutureProvider<String> cruxCxpProductVersionProvider =
    FutureProvider<String>(
      (_) async => 'dev',
      name: 'cruxCxpProductVersionProvider',
    );

/// Asks the window manager for the user's attention (a dock bounce, a
/// taskbar flash) when a peer's request is honoured and the setting is on.
/// Null (the default) asks for nothing.
final Provider<void Function()?> cruxCxpAttentionRequesterProvider =
    Provider<void Function()?>(
      (_) => null,
      name: 'cruxCxpAttentionRequesterProvider',
    );

/// Which peers are offered anywhere: the panel, the badge and every
/// cross-probe menu read the one filtered list. Defaults to every peer; a
/// product applies an organization's allowlist here.
final Provider<bool Function(PeerIdentity peer)> cruxCxpPeerFilterProvider =
    Provider<bool Function(PeerIdentity peer)>(
      (_) => _allowEveryPeer,
      name: 'cruxCxpPeerFilterProvider',
    );

bool _allowEveryPeer(PeerIdentity _) => true;

/// Whether this build runs CXP: loopback sockets and the shared discovery
/// directory, on a desktop. False in a browser and on iOS and Android, where
/// nothing below runs (no suite peer runs beside a phone app).
final Provider<bool> cruxCxpTransportAvailableProvider = Provider<bool>(
  (_) => cruxCxpDesktopHost(),
  name: 'cruxCxpTransportAvailableProvider',
);

/// Whether this process is a desktop build (macOS, Windows or Linux, not the
/// web): the platforms CXP runs on.
bool cruxCxpDesktopHost() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
}

/// What the organization's policy file says about the server, given the
/// user's own setting: returns the effective enable flag. The default
/// returns the user's setting; a product with a server lock in its policy
/// keys (WaveCrux's `resolveCxpServerPolicy`) overrides it.
final Provider<bool Function({required bool userEnabled})>
cruxCxpServerPolicyProvider =
    Provider<bool Function({required bool userEnabled})>(
      (_) => _userSettingWins,
      name: 'cruxCxpServerPolicyProvider',
    );

bool _userSettingWins({required bool userEnabled}) => userEnabled;

/// The suite-shared discovery directory. Tests override it with a temp
/// directory. Never an app-container path: no other product would scan it.
final FutureProvider<String> cruxCxpManifestDirectoryProvider =
    FutureProvider<String>(
      (_) async => sharedCxpManifestDirectory(),
      name: 'cruxCxpManifestDirectoryProvider',
    );

/// Where [CruxCxpSettings] are saved, under the product's own keys.
final Provider<SettingsService<CruxCxpSettings>>
cruxCxpSettingsServiceProvider = Provider<SettingsService<CruxCxpSettings>>(
  (ref) => SettingsService<CruxCxpSettings>(
    ref.watch(cruxCxpProductBindingProvider).settingsCodec,
  ),
  name: 'cruxCxpSettingsServiceProvider',
);

/// Loads the saved CXP settings, for a product's `main` to await before
/// `runApp` and hand to [cruxCxpLaunchSettingsProvider].
Future<CruxCxpSettings> loadCruxCxpLaunchSettings(
  CruxCxpProductBinding binding,
) async {
  try {
    return await SettingsService<CruxCxpSettings>(binding.settingsCodec).load();
  } on Object {
    return binding.settingsCodec.defaults;
  }
}

/// The settings the product loaded before `runApp`
/// ([loadCruxCxpLaunchSettings]). Null (not overridden) makes the settings load
/// in the background, during which the server stays off: a launch with CXP
/// off never starts the server or writes a manifest, even briefly, either
/// way.
final Provider<CruxCxpSettings?> cruxCxpLaunchSettingsProvider =
    Provider<CruxCxpSettings?>(
      (_) => null,
      name: 'cruxCxpLaunchSettingsProvider',
    );

/// The live CXP settings. Each setter saves at once.
final NotifierProvider<CruxCxpSettingsNotifier, CruxCxpSettings>
cruxCxpSettingsProvider =
    NotifierProvider<CruxCxpSettingsNotifier, CruxCxpSettings>(
      CruxCxpSettingsNotifier.new,
      name: 'cruxCxpSettingsProvider',
    );

/// Backs [cruxCxpSettingsProvider].
///
/// The port rule, the same in every product: a valid new port restarts a
/// running server on it at once; with the server off it is saved and used
/// at the next start.
class CruxCxpSettingsNotifier extends Notifier<CruxCxpSettings> {
  final Completer<void> _loaded = Completer<void>();

  /// Completes once the saved settings are in [state].
  Future<void> get loaded => _loaded.future;

  @override
  CruxCxpSettings build() {
    final launch = ref.read(cruxCxpLaunchSettingsProvider);
    if (launch != null) {
      _loaded.complete();
      return launch;
    }
    unawaited(_load());
    // Off until the saved value is known.
    return ref
        .read(cruxCxpProductBindingProvider)
        .settingsCodec
        .defaults
        .copyWith(enabled: false);
  }

  Future<void> _load() async {
    CruxCxpSettings value;
    try {
      value = await ref.read(cruxCxpSettingsServiceProvider).load();
    } on Object {
      value = ref.read(cruxCxpProductBindingProvider).settingsCodec.defaults;
    }
    if (!ref.mounted) return;
    state = value;
    if (!_loaded.isCompleted) _loaded.complete();
  }

  Future<void> _update(CruxCxpSettings next) async {
    await loaded;
    if (!ref.mounted || next == state) return;
    state = next;
    try {
      await ref.read(cruxCxpSettingsServiceProvider).save(next);
    } on Object {
      // No preferences backend: the change holds for this session.
    }
  }

  /// Turns the server on or off.
  Future<void> setEnabled({required bool enabled}) =>
      _update(state.copyWith(enabled: enabled));

  /// Changes the port; an invalid port is ignored.
  Future<void> setPort(int port) async {
    if (!CruxCxpSettings.isValidPort(port)) return;
    await _update(state.copyWith(port: port));
  }

  /// Turns the attention request on or off.
  Future<void> setRequestAttention({required bool requestAttention}) =>
      _update(state.copyWith(requestAttention: requestAttention));

  /// Turns the automatic selection broadcast on or off.
  Future<void> setBroadcastSelection({required bool broadcastSelection}) =>
      _update(state.copyWith(broadcastSelection: broadcastSelection));
}

/// The running CXP runtime, or null when CXP is off (by the user's setting
/// or the organization's policy), there is no transport, or it has not
/// started yet.
///
/// Rebuilt only when the enable flag or the port changes, never on the
/// other two settings. The previous runtime is stopped (goodbye sent,
/// manifest removed) before the next one binds.
final FutureProvider<CruxCxpRuntime?>
cruxCxpRuntimeProvider = FutureProvider<CruxCxpRuntime?>((ref) async {
  if (!ref.watch(cruxCxpTransportAvailableProvider)) return null;
  final (:enabled, :port) = ref.watch(
    cruxCxpSettingsProvider.select((s) => (enabled: s.enabled, port: s.port)),
  );
  if (!ref.watch(cruxCxpServerPolicyProvider)(userEnabled: enabled)) {
    return null;
  }
  final binding = ref.watch(cruxCxpProductBindingProvider);
  final directory = await ref.watch(cruxCxpManifestDirectoryProvider.future);
  final version = await ref.watch(cruxCxpProductVersionProvider.future);
  final runtime = CruxCxpRuntime(
    binding: binding,
    productVersion: version,
    manifestDirectory: directory,
    port: port,
    handler: () => ref.read(cruxCxpRequestHandlerProvider),
    onAttention: () => ref.read(cruxCxpAttentionRequesterProvider)?.call(),
    attentionEnabled: () => ref.read(cruxCxpSettingsProvider).requestAttention,
  );
  // Registered before start(), so a superseded build stops a runtime whose
  // start is still in flight instead of orphaning its socket.
  ref.onDispose(() => unawaited(runtime.dispose()));
  await runtime.start();
  return runtime;
}, name: 'cruxCxpRuntimeProvider');

/// What Settings shows under the CXP controls.
typedef CruxCxpServerStatus = ({bool running, int? port, String? problem});

/// The server's state for the settings status row.
final Provider<CruxCxpServerStatus> cruxCxpServerStatusProvider =
    Provider<CruxCxpServerStatus>((ref) {
      final runtime = ref.watch(cruxCxpRuntimeProvider).value;
      if (runtime == null) return (running: false, port: null, problem: null);
      return (
        running: runtime.isAvailable,
        port: runtime.boundPort,
        problem: runtime.unavailableReason,
      );
    }, name: 'cruxCxpServerStatusProvider');

/// The connected peers, filtered by [cruxCxpPeerFilterProvider]. Empty whenever
/// the server is off: the cross-probe panel, the toolbar badge and every
/// cross-probe menu read this one list.
final StreamProvider<List<PeerIdentity>> cruxCxpPeersStreamProvider =
    StreamProvider<List<PeerIdentity>>((ref) async* {
      final runtime = ref.watch(cruxCxpRuntimeProvider).value;
      if (runtime == null) {
        yield const <PeerIdentity>[];
        return;
      }
      final allowed = ref.watch(cruxCxpPeerFilterProvider);
      List<PeerIdentity> filter(List<PeerIdentity> peers) =>
          List<PeerIdentity>.unmodifiable(peers.where(allowed));
      yield filter(runtime.peers);
      await for (final peers in runtime.peerChanges) {
        yield filter(peers);
      }
    }, name: 'cruxCxpPeersStreamProvider');

/// [cruxCxpPeersStreamProvider]'s latest value, synchronously; empty until the
/// first snapshot.
final Provider<List<PeerIdentity>> cruxCxpPeersProvider =
    Provider<List<PeerIdentity>>(
      (ref) =>
          ref.watch(cruxCxpPeersStreamProvider).value ?? const <PeerIdentity>[],
      name: 'cruxCxpPeersProvider',
    );

/// The toolbar badge's number: connected peers.
final Provider<int> cruxCxpConnectedPeerCountProvider = Provider<int>(
  (ref) => ref.watch(cruxCxpPeersProvider).length,
  name: 'cruxCxpConnectedPeerCountProvider',
);

/// Peers discovered but not reachable. Empty when the server is off, and
/// so cleared by every stop and restart; an entry leaves when its peer
/// connects or goes away.
final StreamProvider<List<CxpDialFailure>> cruxCxpUnreachablePeersProvider =
    StreamProvider<List<CxpDialFailure>>((ref) async* {
      final runtime = ref.watch(cruxCxpRuntimeProvider).value;
      if (runtime == null) {
        yield const <CxpDialFailure>[];
        return;
      }
      yield runtime.unreachablePeers;
      yield* runtime.unreachableChanges;
    }, name: 'cruxCxpUnreachablePeersProvider');

/// How many events the panel's log keeps.
const int kCruxCxpEventLogCapacity = 200;

/// The cross-probe event log, oldest first, across server restarts. Only
/// the user's Clear empties it.
final NotifierProvider<CruxCxpEventLog, List<CrossProbeEvent>>
cruxCxpEventLogProvider =
    NotifierProvider<CruxCxpEventLog, List<CrossProbeEvent>>(
      CruxCxpEventLog.new,
      name: 'cruxCxpEventLogProvider',
    );

/// Backs [cruxCxpEventLogProvider].
class CruxCxpEventLog extends Notifier<List<CrossProbeEvent>> {
  StreamSubscription<CrossProbeEvent>? _subscription;

  @override
  List<CrossProbeEvent> build() {
    ref
      ..listen<AsyncValue<CruxCxpRuntime?>>(cruxCxpRuntimeProvider, (_, next) {
        _follow(next.value);
      }, fireImmediately: true)
      ..onDispose(() => unawaited(_subscription?.cancel()));
    return const <CrossProbeEvent>[];
  }

  void _follow(CruxCxpRuntime? runtime) {
    unawaited(_subscription?.cancel());
    _subscription = runtime?.events.listen(add);
  }

  /// Appends [event], dropping the oldest past [kCruxCxpEventLogCapacity].
  void add(CrossProbeEvent event) {
    final next = <CrossProbeEvent>[...state, event];
    final overflow = next.length - kCruxCxpEventLogCapacity;
    state = List<CrossProbeEvent>.unmodifiable(
      overflow > 0 ? next.sublist(overflow) : next,
    );
  }

  /// Empties the log.
  void clear() => state = const <CrossProbeEvent>[];
}

/// Reads a provider: `ref.read` of a `Ref`, a `WidgetRef` or a container.
typedef CruxCxpReader = T Function<T>(ProviderListenable<T> provider);

/// Announces [message] to every peer when the user has automatic selection
/// broadcast on; a no-op otherwise or when the server is off. Products call
/// it from their selection listeners, passing `ref.read`.
void broadcastCruxCxpSelection(CruxCxpReader read, NotifySelection message) {
  if (!read(cruxCxpSettingsProvider).broadcastSelection) return;
  read(cruxCxpRuntimeProvider).value?.broadcast(message);
}
