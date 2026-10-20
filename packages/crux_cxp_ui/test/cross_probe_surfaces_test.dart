// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

/// Every send any fake dispatcher saw in the current test.
final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher(this.result) : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  final CrossProbeOutcomeKind Function(PeerIdentity peer) result;
  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return CrossProbeOutcome(
      result(peer),
      target: label,
      reason: 'no design open',
    );
  }
}

class _SeededLog extends CruxCxpEventLog {
  @override
  List<CrossProbeEvent> build() => <CrossProbeEvent>[
    CrossProbeEvent.peerConnected(peerLabel: 'WaveCrux'),
  ];
}

class _DenyGate implements CrossProbeGate {
  int asked = 0;

  @override
  Future<bool> admit(BuildContext context, PeerIdentity peer) async {
    asked++;
    return false;
  }
}

PeerIdentity _peer(String product, int startedAt) => PeerIdentity(
  peerId: '$product-7-$startedAt',
  productName: product,
  productVersion: '1.2.0',
);

const _selection = CrossProbeSelection(
  candidates: <ElementId>[ElementId(kind: ElementKind.net, path: 'top.clk')],
);

void main() {
  late CrossProbeOutcomeKind Function(PeerIdentity) result;

  setUp(() {
    result = (_) => CrossProbeOutcomeKind.sent;
    _sent.clear();
  });

  Widget host({
    required List<PeerIdentity> peers,
    required Widget Function(BuildContext context, WidgetRef ref) child,
    bool serverRunning = true,
    List<Override> extra = const <Override>[],
  }) {
    return ProviderScope(
      overrides: [
        cruxCxpProductBindingProvider.overrideWithValue(
          const CruxCxpProductBinding(
            productName: 'lintcrux',
            defaultPort: 54324,
            prefsPrefix: 'settings.',
          ),
        ),
        cruxCxpPeersProvider.overrideWithValue(peers),
        cruxCxpServerStatusProvider.overrideWithValue((
          running: serverRunning,
          port: serverRunning ? 54324 : null,
          problem: null,
        )),
        crossProbeDispatcherProvider.overrideWith((ref) {
          return _FakeDispatcher((p) => result(p));
        }),
        cruxCxpRuntimeProvider.overrideWith((_) async => null),
        ...extra,
      ],
      child: MaterialApp(
        theme: ThemeData(
          extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
        ),
        home: Scaffold(
          body: Center(
            child: Consumer(builder: (context, ref, _) => child(context, ref)),
          ),
        ),
      ),
    );
  }

  Widget overflow({
    CrossProbeSelection? Function()? selection,
  }) => Builder(
    builder: (context) => Consumer(
      builder: (context, ref, _) => CruxOverflowMenu(
        tooltip: 'More',
        entries: <CruxMenuEntry>[
          CruxMenuItem(label: 'Copy', onSelected: () {}),
          crossProbeMenuEntry(
            context,
            ref,
            selection: selection ?? () => _selection,
          ),
        ],
      ),
    ),
  );

  group('"Cross-probe to" submenu', () {
    testWidgets('no peers: one disabled item that says what to start', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(peers: const [], child: (_, _) => overflow()),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Cross-probe to (no peers running)'), findsOneWidget);
      final item = tester.widget<PopupMenuItem<int>>(
        find.byKey(const ValueKey('crossProbeSubmenu')),
      );
      expect(item.enabled, isFalse);
      expect(
        find.byTooltip(
          'Start WaveCrux, NetCrux, LintCrux or SimCrux with CXP on to '
          'cross-probe to it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one item per product, in suite order, and the chosen one '
        'gets the selection', (tester) async {
      await tester.pumpWidget(
        host(
          peers: [_peer('simcrux', 1), _peer('wavecrux', 1)],
          child: (_, _) => overflow(),
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cross-probe to'));
      await tester.pumpAndSettle();
      final wave = tester.getTopLeft(find.text('WaveCrux'));
      final sim = tester.getTopLeft(find.text('SimCrux'));
      expect(wave.dy, lessThan(sim.dy));

      await tester.tap(find.text('SimCrux'));
      await tester.pumpAndSettle();
      expect(_sent.single.$1.productName, 'simcrux');
      expect(_sent.single.$2, same(_selection));
    });

    testWidgets('several windows of a product are sub-items', (tester) async {
      await tester.pumpWidget(
        host(
          peers: [_peer('wavecrux', 20), _peer('wavecrux', 10)],
          child: (_, _) => overflow(),
        ),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cross-probe to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WaveCrux'));
      await tester.pumpAndSettle();
      expect(find.text('WaveCrux 1'), findsOneWidget);
      await tester.tap(find.text('WaveCrux 2'));
      await tester.pumpAndSettle();
      expect(_sent.single.$1.peerId, 'wavecrux-7-20');
    });

    testWidgets('a refused send is an error toast with the peer reason', (
      tester,
    ) async {
      result = (_) => CrossProbeOutcomeKind.refused;
      await tester.pumpWidget(
        host(peers: [_peer('netcrux', 1)], child: (_, _) => overflow()),
      );
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cross-probe to'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NetCrux'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cross-probe to NetCrux: no design open'),
        findsOneWidget,
      );
    });
  });

  group('Cross-probe Selection command', () {
    Widget command({CrossProbeSelection? selection = _selection}) => Builder(
      builder: (context) => Consumer(
        builder: (context, ref, _) => ElevatedButton(
          onPressed: () =>
              runCrossProbeSelection(context, ref, selection: selection),
          child: const Text('Run'),
        ),
      ),
    );

    testWidgets('one target: sends straight away, no menu', (tester) async {
      final announced = AnnouncementRecorder.attach(tester);
      await tester.pumpWidget(
        host(peers: [_peer('netcrux', 1)], child: (_, _) => command()),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(_sent, hasLength(1));
      expect(find.byType(PopupMenuItem<int>), findsNothing);
      expect(announced.messages, contains('Cross-probed to NetCrux'));
    });

    testWidgets('several targets: the target list as a menu, never a dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          peers: [_peer('netcrux', 1), _peer('wavecrux', 1)],
          child: (_, _) => command(),
        ),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(_sent, isEmpty);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('WaveCrux'), findsOneWidget);
      expect(find.text('NetCrux'), findsOneWidget);
      await tester.tap(find.text('WaveCrux'));
      await tester.pumpAndSettle();
      expect(_sent.single.$1.productName, 'wavecrux');
    });

    testWidgets('nothing selected, server off, no peers: each reported', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          peers: [_peer('netcrux', 1)],
          child: (_, _) => command(
            selection: null,
          ),
        ),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select something to cross-probe first.'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        host(
          peers: [_peer('netcrux', 1)],
          serverRunning: false,
          child: (_, _) => command(),
        ),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The CXP server is off. Turn it on in Settings > CXP Cross-Probe.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        host(peers: const [], child: (_, _) => command()),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(
        find.text('No peers are running to cross-probe to.'),
        findsOneWidget,
      );
      expect(_sent, isEmpty);
    });

    testWidgets('a gate that denies stops the send and adds nothing of its '
        'own', (tester) async {
      final gate = _DenyGate();
      await tester.pumpWidget(
        host(
          peers: [_peer('netcrux', 1)],
          extra: [crossProbeGateProvider.overrideWithValue(gate)],
          child: (_, _) => command(),
        ),
      );
      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      expect(gate.asked, 1);
      expect(_sent, isEmpty);
      expect(find.byKey(const ValueKey('crossProbeOutcome')), findsNothing);
    });
  });

  group('one-click button', () {
    Widget button() => CrossProbeToButton(
      productName: 'wavecrux',
      selection: () => _selection,
    );

    testWidgets('disabled, saying why, while the product is not running', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(peers: [_peer('netcrux', 1)], child: (_, _) => button()),
      );
      final widget = tester.widget<IconButton>(
        find.byKey(const ValueKey('crossProbeTo:wavecrux')),
      );
      expect(widget.onPressed, isNull);
      expect(widget.tooltip, startsWith('Cross-probe to WaveCrux.'));
    });

    testWidgets('one window: sends; several: lists them below itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(peers: [_peer('wavecrux', 1)], child: (_, _) => button()),
      );
      await tester.tap(find.byKey(const ValueKey('crossProbeTo:wavecrux')));
      await tester.pumpAndSettle();
      expect(_sent, hasLength(1));

      await tester.pumpWidget(
        host(
          peers: [_peer('wavecrux', 1), _peer('wavecrux', 2)],
          child: (_, _) => button(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('crossProbeTo:wavecrux')));
      await tester.pumpAndSettle();
      expect(find.text('WaveCrux 1'), findsOneWidget);
      expect(find.text('WaveCrux 2'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the bound panel shows the shared strings in the locale, and a '
      'peer row sends through the shared send', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cruxCxpProductBindingProvider.overrideWithValue(
            const CruxCxpProductBinding(
              productName: 'simcrux',
              defaultPort: 54325,
              prefsPrefix: 'simcrux.',
            ),
          ),
          cruxCxpPeersProvider.overrideWithValue([_peer('wavecrux', 1)]),
          cruxCxpServerStatusProvider.overrideWithValue((
            running: true,
            port: 54325,
            problem: null,
          )),
          cruxCxpUnreachablePeersProvider.overrideWith(
            (_) => Stream<List<CxpDialFailure>>.value(const []),
          ),
          crossProbeDispatcherProvider.overrideWith(
            (ref) => _FakeDispatcher((p) => result(p)),
          ),
          cruxCxpRuntimeProvider.overrideWith((_) async => null),
          cruxCxpEventLogProvider.overrideWith(_SeededLog.new),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: const [Locale('en'), Locale('ja')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: CruxCrossProbePanel(
              selection: () => _selection,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('接続中のピア'), findsOneWidget);
    expect(find.text('ピアが接続しました'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-7-1')));
    await tester.pumpAndSettle();
    expect(_sent.single.$1.productName, 'wavecrux');
  });
}
