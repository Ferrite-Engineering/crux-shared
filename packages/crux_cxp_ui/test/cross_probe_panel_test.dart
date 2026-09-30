// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the panel in a themed [MaterialApp], sized like a docked side-panel.
Future<void> pumpPanel(
  WidgetTester tester,
  DemoCrossProbePanelController controller, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 700,
          child: CrossProbePanel(controller: controller),
        ),
      ),
    ),
  );
}

PeerIdentity peer(String product, String id) => PeerIdentity(
  peerId: id,
  productName: product,
  productVersion: '1.0.0',
);

/// A cross-probe event with a fixed timestamp, for concise test setup.
CrossProbeEvent ev(CrossProbeEventKind kind, String peerLabel) =>
    CrossProbeEvent(
      kind: kind,
      peerLabel: peerLabel,
      timestamp: DateTime(2026, 7, 25, 9),
    );

void main() {
  group('CrossProbePanel', () {
    testWidgets('renders connected peers', (tester) async {
      final controller = DemoCrossProbePanelController()
        ..addPeer(peer('NetCrux', 'netcrux-1'))
        ..addPeer(peer('SimCrux', 'simcrux-2'));
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);

      expect(find.text('NetCrux 1.0.0'), findsOneWidget);
      expect(find.text('SimCrux 1.0.0'), findsOneWidget);
      expect(find.text('No peers connected.'), findsNothing);
    });

    testWidgets('shows the no-peers placeholder when empty', (tester) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);

      expect(find.text('No peers connected.'), findsOneWidget);
    });

    testWidgets('renders every event kind, incl. selection-received and '
        'open-artifact', (tester) async {
      final controller = DemoCrossProbePanelController()
        ..addEvent(CrossProbeEvent.peerConnected(peerLabel: 'NetCrux'))
        ..addEvent(ev(CrossProbeEventKind.selectionSent, 'NetCrux'))
        ..addEvent(ev(CrossProbeEventKind.selectionReceived, 'SimCrux'))
        ..addEvent(ev(CrossProbeEventKind.highlightReceived, 'SimCrux'))
        ..addEvent(ev(CrossProbeEventKind.openArtifact, 'NetCrux'))
        ..addEvent(CrossProbeEvent.peerDisconnected(peerLabel: 'SimCrux'));
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);

      expect(find.text('Peer connected'), findsOneWidget);
      expect(find.text('Selection sent'), findsOneWidget);
      expect(find.text('Selection received'), findsOneWidget);
      expect(find.text('Highlight received'), findsOneWidget);
      expect(find.text('Open artifact'), findsOneWidget);
      expect(find.text('Peer disconnected'), findsOneWidget);
    });

    testWidgets('close chevron invokes onClose', (tester) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      await tester.tap(find.byKey(const Key('cross_probe_close')));

      expect(controller.onCloseCount, 1);
    });

    testWidgets('per-peer send invokes onSendTo with that peer', (
      tester,
    ) async {
      final target = peer('SimCrux', 'simcrux-2');
      final controller = DemoCrossProbePanelController()
        ..addPeer(peer('NetCrux', 'netcrux-1'))
        ..addPeer(target);
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      await tester.tap(
        find.byKey(const Key('cross_probe_send_simcrux-2')),
      );

      expect(controller.onSendToCount, 1);
      expect(controller.lastSentTo, target);
    });

    testWidgets('a rejected send raises a toast (R8: never a silent no-op)', (
      tester,
    ) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      // The peer acked honored:false — the panel must surface the reason.
      controller.pushSendFailure(
        const CrossProbeSendFailure(
          peerLabel: 'NetCrux',
          reason: 'element not found in current design',
        ),
      );
      await tester.pump(); // post-frame callback schedules the snackbar
      await tester.pump(); // snackbar animates in

      expect(
        find.byKey(const Key('cross_probe_send_failure')),
        findsOneWidget,
      );
      expect(
        find.text('NetCrux: element not found in current design'),
        findsOneWidget,
      );
    });

    testWidgets('the send-failure toast honors a localized strings builder', (
      tester,
    ) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 700,
              child: CrossProbePanel(
                controller: controller,
                strings: CrossProbePanelStrings(
                  sendRejected: (peer, reason) => 'REJECTED[$peer/$reason]',
                ),
              ),
            ),
          ),
        ),
      );
      controller.pushSendFailure(
        const CrossProbeSendFailure(peerLabel: 'SimCrux', reason: 'no config'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('REJECTED[SimCrux/no config]'), findsOneWidget);
    });

    testWidgets('unreachable peers show a warning section', (tester) async {
      final controller = DemoCrossProbePanelController()
        ..addUnreachable(
          const CxpDialFailure(
            peerId: 'lintcrux-9',
            host: '127.0.0.1',
            port: 51999,
            error: 'refused',
            consecutiveFailures: 2,
            nextRetryAfterTicks: 1,
          ),
        );
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);

      expect(find.byKey(const Key('cross_probe_unreachable')), findsOneWidget);
      expect(find.text('Unreachable peers'), findsOneWidget);
      expect(find.text('lintcrux-9'), findsOneWidget);
      expect(find.text('127.0.0.1:51999'), findsOneWidget);
    });

    testWidgets('no unreachable section when there are none', (tester) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);

      expect(find.byKey(const Key('cross_probe_unreachable')), findsNothing);
    });

    testWidgets('Clear events invokes onClearEvents', (tester) async {
      final controller = DemoCrossProbePanelController()
        ..addEvent(CrossProbeEvent.peerConnected(peerLabel: 'NetCrux'));
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      expect(find.byKey(const Key('cross_probe_clear_events')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cross_probe_clear_events')));
      await tester.pump();

      expect(controller.onClearEventsCount, 1);
      // The demo controller empties its buffer, so the button disappears.
      expect(find.byKey(const Key('cross_probe_clear_events')), findsNothing);
      expect(find.text('No recent events yet.'), findsOneWidget);
    });

    testWidgets('offline banner shows only when server is not running', (
      tester,
    ) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsNothing,
      );

      controller.running = false;
      await tester.pump();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsOneWidget,
      );
    });

    testWidgets('reacts to peers pushed after first build', (tester) async {
      final controller = DemoCrossProbePanelController();
      addTearDown(controller.dispose);

      await pumpPanel(tester, controller);
      expect(find.text('NetCrux 1.0.0'), findsNothing);

      controller.addPeer(peer('NetCrux', 'netcrux-1'));
      await tester.pump();
      expect(find.text('NetCrux 1.0.0'), findsOneWidget);
    });

    testWidgets('renders in both light and dark themes', (tester) async {
      for (final theme in [ThemeData.light(), ThemeData.dark()]) {
        final controller = DemoCrossProbePanelController.populated();
        await pumpPanel(tester, controller, theme: theme);
        expect(find.text('Cross-Probe'), findsOneWidget);
        expect(find.text('Selection received'), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.dispose();
      }
    });
  });
}
