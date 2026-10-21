// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared CXP lifecycle, end to end over real loopback sockets and a real
// discovery directory: two products in one process, each in its own root
// container, as two apps on one machine.

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Handler extends CruxCxpRequestHandler {
  _Handler({this.hang = false});

  final bool hang;
  final List<ElementId> highlighted = <ElementId>[];
  final List<String> opened = <String>[];
  final List<NotifySelection> selections = <NotifySelection>[];

  @override
  Future<CruxCxpHandlerResult> openSource(
    RequestOpenSource request,
    PeerIdentity from,
  ) async {
    opened.add('${request.filePath}:${request.line}');
    return CruxCxpHandlerResult.ok;
  }

  @override
  Future<CruxCxpHandlerResult> openArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) async {
    throw StateError('no such design');
  }

  @override
  void selection(NotifySelection message, PeerIdentity from) =>
      selections.add(message);

  @override
  Future<CruxCxpHandlerResult> highlight(
    RequestHighlight request,
    PeerIdentity from,
  ) async {
    if (hang) await Completer<void>().future;
    if (request.element.kind != ElementKind.net) {
      return const CruxCxpHandlerResult(
        honored: false,
        reason: 'nothing named that',
      );
    }
    highlighted.add(request.element);
    return CruxCxpHandlerResult.ok;
  }
}

Future<void> _until(bool Function() done, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('timed out waiting${reason == null ? '' : ' for $reason'}');
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dir = await Directory.systemTemp.createTemp('crux_cxp_lifecycle_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  List<String> manifests() => dir.existsSync()
      ? dir.listSync().map((e) => e.path).toList()
      : const <String>[];

  ProviderContainer product(
    String name, {
    CruxCxpSettings? launch = const CruxCxpSettings(enabled: true, port: 0),
    CruxCxpRequestHandler handler = const CruxCxpRequestHandler(),
    void Function()? attention,
    bool transport = true,
    void Function(CrossProbeSendRecord record)? observer,
    bool Function({required bool userEnabled})? policy,
  }) {
    final container =
        ProviderContainer(
            overrides: [
              cruxCxpProductBindingProvider.overrideWithValue(
                CruxCxpProductBinding(
                  productName: name,
                  defaultPort: 54329,
                  prefsPrefix: '$name.',
                ),
              ),
              cruxCxpManifestDirectoryProvider.overrideWith(
                (_) async => dir.path,
              ),
              cruxCxpTransportAvailableProvider.overrideWithValue(transport),
              cruxCxpRequestHandlerProvider.overrideWithValue(handler),
              cruxCxpAttentionRequesterProvider.overrideWithValue(attention),
              crossProbeSendObserverProvider.overrideWithValue(observer),
              if (policy != null)
                cruxCxpServerPolicyProvider.overrideWithValue(policy),
              if (launch != null)
                cruxCxpLaunchSettingsProvider.overrideWithValue(launch),
            ],
          )
          // Keep the peer and unreachable streams subscribed, as the panel and
          // the toolbar badge do.
          ..listen(cruxCxpPeersProvider, (_, _) {})
          ..listen(cruxCxpUnreachablePeersProvider, (_, _) {})
          ..listen(cruxCxpEventLogProvider, (_, _) {});
    addTearDown(container.dispose);
    return container;
  }

  Future<CruxCxpRuntime?> runtimeOf(ProviderContainer c) =>
      c.read(cruxCxpRuntimeProvider.future);

  test('settings survive a relaunch, under the product keys', () async {
    final first = product('netcrux', launch: null, transport: false);
    final settings = first.read(cruxCxpSettingsProvider.notifier);
    await settings.loaded;
    await settings.setEnabled(enabled: false);
    await settings.setPort(50123);
    await settings.setBroadcastSelection(broadcastSelection: false);
    first.dispose();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('netcrux.cxpServerEnabled'), isFalse);
    expect(prefs.getInt('netcrux.cxpServerPort'), 50123);

    final again = product('netcrux', launch: null, transport: false);
    await again.read(cruxCxpSettingsProvider.notifier).loaded;
    expect(
      again.read(cruxCxpSettingsProvider),
      const CruxCxpSettings(
        enabled: false,
        port: 50123,
        broadcastSelection: false,
      ),
    );
    // The launch loader reads the same thing for main() to hand in.
    expect(
      await loadCruxCxpLaunchSettings(
        again.read(cruxCxpProductBindingProvider),
      ),
      again.read(cruxCxpSettingsProvider),
    );
  });

  test(
    'a launch with CXP off never starts the server or writes a manifest',
    () async {
      final off = product(
        'wavecrux',
        launch: const CruxCxpSettings(enabled: false, port: 0),
      );
      expect(await runtimeOf(off), isNull);
      expect(off.read(cruxCxpServerStatusProvider).running, isFalse);
      expect(manifests(), isEmpty);
    },
  );

  test("the organization's policy can hold the server off whatever the user "
      'set', () async {
    final c = product(
      'wavecrux',
      policy: ({required userEnabled}) => false,
    );
    expect(c.read(cruxCxpSettingsProvider).enabled, isTrue);
    expect(await runtimeOf(c), isNull);
    expect(manifests(), isEmpty);
  });

  test('CXP runs on the desktop only', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final desktop = <TargetPlatform>{
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(platform);
      expect(cruxCxpDesktopHost(), desktop, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('saved settings that say off keep the server off while they load, and '
      'after', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lintcrux.cxpServerEnabled': false,
    });
    final c = product('lintcrux', launch: null);
    expect(c.read(cruxCxpSettingsProvider).enabled, isFalse);
    expect(await runtimeOf(c), isNull);
    await c.read(cruxCxpSettingsProvider.notifier).loaded;
    expect(await runtimeOf(c), isNull);
    expect(manifests(), isEmpty);
  });

  test('two products find each other; turning CXP off empties the peer list '
      'and the badge', () async {
    final wave = product('wavecrux');
    expect((await runtimeOf(wave))!.isAvailable, isTrue);
    expect(manifests(), hasLength(1));
    final net = product('netcrux');
    await runtimeOf(net);
    await _until(
      () => wave.read(cruxCxpPeersProvider).isNotEmpty,
      reason: 'WaveCrux to see NetCrux',
    );
    await _until(
      () => net.read(cruxCxpPeersProvider).isNotEmpty,
      reason: 'NetCrux to see WaveCrux',
    );
    expect(wave.read(cruxCxpConnectedPeerCountProvider), 1);
    expect(wave.read(crossProbeTargetsProvider).single.label, 'NetCrux');

    await wave
        .read(cruxCxpSettingsProvider.notifier)
        .setEnabled(enabled: false);
    expect(await runtimeOf(wave), isNull);
    await _until(() => wave.read(cruxCxpPeersProvider).isEmpty);
    expect(wave.read(cruxCxpConnectedPeerCountProvider), 0);
    expect(wave.read(crossProbeTargetsProvider), isEmpty);
    // The manifest went with the server.
    await _until(() => manifests().length == 1, reason: 'manifest removal');
  });

  test('a new port restarts a running server on it at once', () async {
    final c = product('simcrux');
    final before = await runtimeOf(c);
    expect(before!.isAvailable, isTrue);
    final port = await _freePort();
    await c.read(cruxCxpSettingsProvider.notifier).setPort(port);
    final after = await runtimeOf(c);
    expect(after, isNot(same(before)));
    expect(after!.boundPort, port);
    expect(before.isAvailable, isFalse, reason: 'the old server stopped');
  });

  test(
    'a port change with the server off is kept for the next start',
    () async {
      final c = product(
        'simcrux',
        launch: const CruxCxpSettings(enabled: false, port: 0),
      );
      final port = await _freePort();
      await c.read(cruxCxpSettingsProvider.notifier).setPort(port);
      expect(await runtimeOf(c), isNull);
      await c.read(cruxCxpSettingsProvider.notifier).setEnabled(enabled: true);
      expect((await runtimeOf(c))!.boundPort, port);
    },
  );

  group('sending', () {
    late ProviderContainer wave;
    late ProviderContainer net;
    late _Handler handler;
    late int attention;
    late PeerIdentity netPeer;
    late List<CrossProbeSendRecord> observed;

    setUp(() async {
      handler = _Handler();
      attention = 0;
      observed = <CrossProbeSendRecord>[];
      wave = product('wavecrux', observer: observed.add);
      await runtimeOf(wave);
      net = product('netcrux', handler: handler, attention: () => attention++);
      await runtimeOf(net);
      await _until(() => wave.read(cruxCxpPeersProvider).isNotEmpty);
      await _until(() => net.read(cruxCxpPeersProvider).isNotEmpty);
      netPeer = wave.read(cruxCxpPeersProvider).single;
    });

    CrossProbeSelection selection(ElementKind kind) => CrossProbeSelection(
      candidates: <ElementId>[ElementId(kind: kind, path: 'top.clk')],
    );

    test('an acknowledged send lands, asks for attention, and is logged on '
        'both sides', () async {
      final outcome = await wave
          .read(crossProbeDispatcherProvider)
          .send(netPeer, selection(ElementKind.net));
      expect(outcome.kind, CrossProbeOutcomeKind.sent);
      expect(outcome.target, 'NetCrux');
      expect(handler.highlighted.single.path, 'top.clk');
      expect(attention, 1);
      expect(
        wave.read(cruxCxpEventLogProvider).map((e) => e.kind),
        contains(CrossProbeEventKind.highlightSent),
      );
      await _until(
        () => net
            .read(cruxCxpEventLogProvider)
            .any((e) => e.kind == CrossProbeEventKind.highlightReceived),
      );
    });

    test('open-source and open-artifact requests reach the handler and are '
        'acknowledged; a selection broadcast follows its setting', () async {
      final runtime = (await runtimeOf(wave))!;
      expect(
        runtime.sendTo(
          netPeer.peerId,
          const RequestOpenSource(filePath: '/rtl/top.sv', line: 12),
        ),
        isTrue,
      );
      expect(
        runtime.sendTo(
          netPeer.peerId,
          const RequestOpenArtifact(designId: 'abc', artifactKind: 'netlist'),
        ),
        isTrue,
      );
      await _until(() => handler.opened.isNotEmpty);
      expect(handler.opened.single, '/rtl/top.sv:12');
      expect(attention, 1, reason: 'an honoured open asks for attention');
      await _until(
        () => net
            .read(cruxCxpEventLogProvider)
            .any((e) => e.kind == CrossProbeEventKind.openArtifact),
      );

      broadcastCruxCxpSelection(
        wave.read,
        const NotifySelection(
          elements: <ElementId>[ElementId(kind: ElementKind.net, path: 'a')],
        ),
      );
      await _until(() => handler.selections.isNotEmpty);
      await wave
          .read(cruxCxpSettingsProvider.notifier)
          .setBroadcastSelection(broadcastSelection: false);
      broadcastCruxCxpSelection(
        wave.read,
        const NotifySelection(
          elements: <ElementId>[ElementId(kind: ElementKind.net, path: 'b')],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(handler.selections, hasLength(1));
      expect(
        wave.read(cruxCxpEventLogProvider).map((e) => e.kind),
        contains(CrossProbeEventKind.selectionSent),
      );
    });

    test('the attention request follows its setting', () async {
      await net
          .read(cruxCxpSettingsProvider.notifier)
          .setRequestAttention(requestAttention: false);
      await wave
          .read(crossProbeDispatcherProvider)
          .send(netPeer, selection(ElementKind.net));
      expect(attention, 0);
    });

    test('the send observer hears every outcome with what was sent', () async {
      final dispatcher = wave.read(crossProbeDispatcherProvider);
      await dispatcher.send(netPeer, selection(ElementKind.net));
      await dispatcher.send(netPeer, selection(ElementKind.rule));
      expect(observed.map((r) => r.outcome.kind), [
        CrossProbeOutcomeKind.sent,
        CrossProbeOutcomeKind.notShowable,
      ]);
      expect(observed.first.element?.kind, ElementKind.net);
      expect(observed.first.peer, netPeer);
      expect(observed.last.element, isNull);
    });

    test('a refusal carries the peer reason', () async {
      final outcome = await wave
          .read(crossProbeDispatcherProvider)
          .send(netPeer, selection(ElementKind.scope));
      expect(outcome.kind, CrossProbeOutcomeKind.refused);
      expect(outcome.reason, 'nothing named that');
      expect(attention, 0);
    });

    test('a kind the target cannot show is not sent', () async {
      final outcome = await wave
          .read(crossProbeDispatcherProvider)
          .send(netPeer, selection(ElementKind.rule));
      expect(outcome.kind, CrossProbeOutcomeKind.notShowable);
      expect(handler.highlighted, isEmpty);
    });

    test(
      'nothing selected, a peer gone, and the server off each say so',
      () async {
        final dispatcher = wave.read(crossProbeDispatcherProvider);
        expect(
          (await dispatcher.send(netPeer, null)).kind,
          CrossProbeOutcomeKind.nothingSelected,
        );
        expect(
          (await dispatcher.send(
            const PeerIdentity(
              peerId: 'netcrux-1-1',
              productName: 'netcrux',
              productVersion: '1',
            ),
            selection(ElementKind.net),
          )).kind,
          CrossProbeOutcomeKind.peerGone,
        );
        await wave
            .read(cruxCxpSettingsProvider.notifier)
            .setEnabled(enabled: false);
        await runtimeOf(wave);
        expect(
          (await dispatcher.send(netPeer, selection(ElementKind.net))).kind,
          CrossProbeOutcomeKind.serverOff,
        );
      },
    );
  });

  test('a peer that never acknowledges is reported as no response', () async {
    final wave = product('wavecrux');
    await runtimeOf(wave);
    final net = product('netcrux', handler: _Handler(hang: true));
    await runtimeOf(net);
    await _until(() => wave.read(cruxCxpPeersProvider).isNotEmpty);
    final outcome =
        await CrossProbeDispatcher(
          wave.read,
          timeout: const Duration(milliseconds: 300),
        ).send(
          wave.read(cruxCxpPeersProvider).single,
          const CrossProbeSelection(
            candidates: <ElementId>[
              ElementId(kind: ElementKind.net, path: 'n'),
            ],
          ),
        );
    expect(outcome.kind, CrossProbeOutcomeKind.noResponse);
  });

  test('an unreachable peer is listed, and leaves when its manifest goes; a '
      'stop clears the list', () async {
    final dead = await _freePort();
    final ghost = CxpManifestWriter(manifestDirectory: dir.path);
    await ghost.write(
      identity: const PeerIdentity(
        peerId: 'ghost-1-1',
        productName: 'ghost',
        productVersion: '1',
      ),
      host: '127.0.0.1',
      port: dead,
    );
    final runtime = CruxCxpRuntime(
      binding: const CruxCxpProductBinding(
        productName: 'wavecrux',
        defaultPort: 54322,
        prefsPrefix: 'settings.',
      ),
      productVersion: 'test',
      manifestDirectory: dir.path,
      port: 0,
      handler: () => const CruxCxpRequestHandler(),
      discoveryFactory: (directory, self) => CxpDiscovery(
        manifestDirectory: directory,
        selfPeerId: self,
        scanInterval: const Duration(milliseconds: 100),
      ),
    );
    addTearDown(runtime.dispose);
    await runtime.start();
    await _until(
      () => runtime.unreachablePeers.isNotEmpty,
      reason: 'the dial to fail',
    );
    expect(runtime.unreachablePeers.single.peerId, 'ghost-1-1');

    await ghost.remove();
    await ghost.dispose();
    await _until(
      () => runtime.unreachablePeers.isEmpty,
      reason: 'the ghost to be forgotten',
    );

    await runtime.stop();
    expect(runtime.unreachablePeers, isEmpty);
    expect(runtime.peers, isEmpty);
  });

  test('a discovery scan that outlasts its stop is reported by stop() after '
      'the manifest is removed and the server is down', () async {
    final runtime = CruxCxpRuntime(
      binding: const CruxCxpProductBinding(
        productName: 'wavecrux',
        defaultPort: 54322,
        prefsPrefix: 'settings.',
      ),
      productVersion: 'test',
      manifestDirectory: dir.path,
      port: 0,
      handler: () => const CruxCxpRequestHandler(),
      discoveryFactory: (directory, self) =>
          _StuckDiscovery(manifestDirectory: directory, selfPeerId: self),
    );
    await runtime.start();
    expect(runtime.isAvailable, isTrue);
    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      isNotEmpty,
    );

    await expectLater(runtime.dispose(), throwsA(isA<TimeoutException>()));

    expect(
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
      isEmpty,
      reason: 'the manifest must go even when discovery reports a timeout',
    );
    expect(runtime.isAvailable, isFalse);
    expect(runtime.peers, isEmpty);
  });
}

/// A discovery whose stop reports a scan that would not finish.
class _StuckDiscovery extends CxpDiscovery {
  _StuckDiscovery({required super.manifestDirectory, super.selfPeerId});

  @override
  Future<void> stop() async {
    await super.stop();
    throw TimeoutException('scan still running', const Duration(seconds: 5));
  }
}
