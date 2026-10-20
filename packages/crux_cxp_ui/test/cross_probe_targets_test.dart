// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

PeerIdentity _peer(
  String product,
  int startedAt, {
  Set<String> capabilities = const <String>{},
}) => PeerIdentity(
  peerId: '$product-100-$startedAt',
  productName: product,
  productVersion: '1.2.0',
  capabilities: capabilities,
);

void main() {
  group('target list', () {
    test('no peers: no targets', () {
      expect(crossProbeTargetsFor(const <PeerIdentity>[]), isEmpty);
    });

    test('one per product, in suite order, then others by name', () {
      final targets = crossProbeTargetsFor(<PeerIdentity>[
        _peer('simcrux', 1),
        _peer('zeta', 1),
        _peer('wavecrux', 1),
        _peer('acme', 1),
        _peer('lintcrux', 1),
      ]);
      expect(targets.map((t) => t.label), [
        'WaveCrux',
        'LintCrux',
        'SimCrux',
        'Acme',
        'Zeta',
      ]);
      expect(targets.every((t) => !t.hasSeveralInstances), isTrue);
    });

    test('several windows of one product group under it, oldest first', () {
      final targets = crossProbeTargetsFor(<PeerIdentity>[
        _peer('wavecrux', 30),
        _peer('netcrux', 5),
        _peer('wavecrux', 10),
      ]);
      expect(targets.map((t) => t.productName), ['wavecrux', 'netcrux']);
      final wave = targets.first;
      expect(wave.hasSeveralInstances, isTrue);
      expect(wave.instances.map((p) => p.peerId), [
        'wavecrux-100-10',
        'wavecrux-100-30',
      ]);
    });
  });

  group('element-kind table', () {
    const violation = CrossProbeSelection(
      candidates: <ElementId>[
        ElementId(kind: ElementKind.rule, path: 'W001'),
        ElementId(kind: ElementKind.scope, path: 'top.u_core'),
        ElementId(kind: ElementKind.source, path: '/rtl/core.sv:42'),
      ],
    );
    const testRow = CrossProbeSelection(
      candidates: <ElementId>[
        ElementId(kind: ElementKind.test, path: 'smoke'),
        ElementId(kind: ElementKind.source, path: '/tb/smoke.py:10'),
        ElementId(kind: ElementKind.scope, path: 'top'),
      ],
    );

    ElementKind? kindFor(CrossProbeSelection s, PeerIdentity peer) =>
        crossProbeElementFor(s, peer)?.kind;

    test('keeps what each product sent before the shared table', () {
      // A violation: scope to NetCrux, source to WaveCrux.
      expect(kindFor(violation, _peer('netcrux', 1)), ElementKind.scope);
      expect(kindFor(violation, _peer('wavecrux', 1)), ElementKind.source);
      // A test row: source to WaveCrux, scope to NetCrux and LintCrux.
      expect(kindFor(testRow, _peer('wavecrux', 1)), ElementKind.source);
      expect(kindFor(testRow, _peer('netcrux', 1)), ElementKind.scope);
      expect(kindFor(testRow, _peer('lintcrux', 1)), ElementKind.scope);
    });

    test('a net goes to WaveCrux as a net, not as its scope', () {
      const net = CrossProbeSelection(
        candidates: <ElementId>[
          ElementId(kind: ElementKind.scope, path: 'top'),
          ElementId(kind: ElementKind.net, path: 'top.clk'),
        ],
      );
      expect(kindFor(net, _peer('wavecrux', 1)), ElementKind.net);
    });

    test('a peer that advertises what it accepts is offered only that', () {
      final narrow = _peer(
        'wavecrux',
        1,
        capabilities: <String>{'${kCxpAcceptsCapabilityPrefix}scope'},
      );
      expect(kindFor(violation, narrow), ElementKind.scope);
      final none = _peer(
        'wavecrux',
        1,
        capabilities: <String>{'${kCxpAcceptsCapabilityPrefix}marker'},
      );
      expect(crossProbeElementFor(violation, none), isNull);
    });

    test('an unknown product gets the fallback order', () {
      expect(kindFor(violation, _peer('acme', 1)), ElementKind.scope);
    });

    test('the binding advertises its accepted kinds', () {
      const binding = CruxCxpProductBinding(
        productName: 'netcrux',
        defaultPort: 54323,
        prefsPrefix: 'netcrux.',
        capabilities: <String>{'netcrux.layout'},
        acceptedKinds: <ElementKind>[ElementKind.net, ElementKind.instance],
      );
      expect(binding.advertisedCapabilities, <String>{
        'netcrux.layout',
        'cxp.accepts:net',
        'cxp.accepts:instance',
      });
    });
  });

  group('outcomes', () {
    test('every kind has its sentence; a denial has none; a reasonless '
        'refusal says the target cannot show it', () {
      final s = CruxCxpStrings.forLocale(
        const Locale('en'),
        product: 'LintCrux',
      );
      String? say(CrossProbeOutcomeKind kind, {String? reason}) =>
          CrossProbeOutcome(kind, target: 'NetCrux', reason: reason).message(s);
      expect(say(CrossProbeOutcomeKind.sent), 'Cross-probed to NetCrux');
      expect(
        say(CrossProbeOutcomeKind.refused, reason: 'busy'),
        'Cross-probe to NetCrux: busy',
      );
      expect(
        say(CrossProbeOutcomeKind.refused),
        'NetCrux cannot show this selection',
      );
      expect(
        say(CrossProbeOutcomeKind.noResponse),
        'NetCrux did not answer the cross-probe',
      );
      expect(
        say(CrossProbeOutcomeKind.peerGone),
        'NetCrux is no longer connected',
      );
      expect(say(CrossProbeOutcomeKind.serverOff), s.outcomeServerOff);
      expect(
        say(CrossProbeOutcomeKind.nothingSelected),
        s.outcomeNothingSelected,
      );
      expect(
        say(CrossProbeOutcomeKind.notShowable),
        'NetCrux cannot show this selection',
      );
      expect(say(CrossProbeOutcomeKind.noPeers), s.outcomeNoPeers);
      expect(say(CrossProbeOutcomeKind.denied), isNull);
      expect(
        const CrossProbeOutcome(CrossProbeOutcomeKind.denied).isFailure,
        isFalse,
      );
      expect(
        const CrossProbeOutcome(CrossProbeOutcomeKind.peerGone, target: 'A'),
        const CrossProbeOutcome(CrossProbeOutcomeKind.peerGone, target: 'A'),
      );
      expect(
        const CrossProbeOutcome(CrossProbeOutcomeKind.sent).toString(),
        contains('sent'),
      );
    });

    test('settings value equality', () {
      const a = CruxCxpSettings(enabled: true, port: 1);
      expect(a, const CruxCxpSettings(enabled: true, port: 1));
      expect(
        a.hashCode,
        const CruxCxpSettings(enabled: true, port: 1).hashCode,
      );
      expect(a.copyWith(port: 2), isNot(a));
      expect(a.toString(), contains('port: 1'));
    });

    test('the default handler handles nothing', () async {
      const handler = CruxCxpRequestHandler();
      const from = PeerIdentity(
        peerId: 'x-1-1',
        productName: 'x',
        productVersion: '1',
      );
      expect(
        (await handler.highlight(
          const RequestHighlight(
            element: ElementId(kind: ElementKind.net, path: 'n'),
          ),
          from,
        )).honored,
        isFalse,
      );
      expect(
        (await handler.openSource(
          const RequestOpenSource(filePath: '/a', line: 1),
          from,
        )).reason,
        'unsupported',
      );
      expect(
        (await handler.openArtifact(
          const RequestOpenArtifact(designId: 'd', artifactKind: 'k'),
          from,
        )).honored,
        isFalse,
      );
      handler.selection(const NotifySelection(elements: <ElementId>[]), from);
    });
  });

  group('strings', () {
    test('every suite locale, no em dash and no arrow anywhere', () {
      for (final code in ['en', 'zh', 'ja', 'ko']) {
        final s = CruxCxpStrings.forLocale(Locale(code), product: 'WaveCrux');
        final lines = <String>[
          s.sectionTitle,
          s.enableLabel,
          s.enableHelp,
          s.portLabel,
          s.portHelp,
          s.portError,
          s.attentionLabel,
          s.attentionHelp,
          s.broadcastLabel,
          s.broadcastHelp,
          s.statusLabel,
          s.statusRunning(54322),
          s.statusStopped,
          s.peersConnected(2),
          s.showPanel,
          s.panelTitle,
          s.closePanel,
          s.serverOffline,
          s.peersSection,
          s.noPeers,
          s.sendToPeer,
          s.unreachableSection,
          s.eventsSection,
          s.noEvents,
          s.clearEvents,
          s.eventPeerConnected,
          s.eventPeerDisconnected,
          s.eventSelectionSent,
          s.eventSelectionReceived,
          s.eventHighlightSent,
          s.eventHighlightReceived,
          s.eventOpenArtifact,
          s.eventOther,
          s.crossProbeTo,
          s.crossProbeToProduct('NetCrux'),
          s.noPeersRunning,
          s.noPeersRunningHelp,
          s.selectionCommand,
          s.instanceLabel('WaveCrux', 2),
          s.outcomeSent('NetCrux'),
          s.outcomeRefused('NetCrux', 'no design open'),
          s.outcomeNoResponse('NetCrux'),
          s.outcomePeerGone('NetCrux'),
          s.outcomeServerOff,
          s.outcomeNothingSelected,
          s.outcomeNotShowable('NetCrux'),
          s.outcomeNoPeers,
        ];
        for (final line in lines) {
          expect(line.trim(), isNotEmpty, reason: code);
          expect(line, isNot(contains('—')), reason: '$code: $line');
          expect(line, isNot(matches(RegExp('[←-⇿▶▸]'))));
        }
        expect(s.enableHelp, contains('WaveCrux'));
      }
    });

    test('an unknown locale falls back to English, and a product can reword '
        'its own lines', () {
      final s = CruxCxpStrings.forLocale(
        const Locale('fr'),
        product: 'WaveCrux',
      ).copyWith(portHelp: 'Distinct from the WCP port.');
      expect(s.crossProbeTo, 'Cross-probe to');
      expect(s.portHelp, 'Distinct from the WCP port.');
      expect(s.settings.portHelp, 'Distinct from the WCP port.');
      expect(s.panel.title, 'Cross-Probe');
      expect(s.panel.eventPeerConnected, 'Peer connected');
    });
  });
}
