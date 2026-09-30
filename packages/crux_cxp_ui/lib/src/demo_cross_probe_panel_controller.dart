// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/cross_probe_panel_controller.dart';
import 'package:flutter/foundation.dart';

/// In-package fake/demo implementation of [CrossProbePanelController].
///
/// Two jobs:
///
/// 1. **Testability in isolation** — the shared `CrossProbePanel` needs no app
///    to be rendered or driven. Tests construct this, push peers/events/failures
///    through the mutators, and assert on the invocation counters
///    ([onCloseCount], [lastSentTo], …).
/// 2. **A live demo** — [DemoCrossProbePanelController.populated] seeds a
///    representative snapshot (two peers, one unreachable, one of every event
///    kind) so the panel can be exercised in a scratch app or a golden without
///    wiring real CXP.
///
/// It is deliberately backed by plain [ValueNotifier]s — the same shape an app
/// adapter typically uses — so it doubles as a reference implementation of the
/// interface.
class DemoCrossProbePanelController implements CrossProbePanelController {
  /// Creates an empty controller (server running, no peers/events).
  DemoCrossProbePanelController();

  /// Creates a controller pre-seeded with a representative snapshot for demos
  /// and goldens: two connected peers, one unreachable peer, and one event of
  /// every [CrossProbeEventKind].
  factory DemoCrossProbePanelController.populated() {
    final c = DemoCrossProbePanelController()
      ..addPeer(
        const PeerIdentity(
          peerId: 'netcrux-42-1700000000000',
          productName: 'NetCrux',
          productVersion: '0.9.0',
        ),
      )
      ..addPeer(
        const PeerIdentity(
          peerId: 'simcrux-43-1700000000001',
          productName: 'SimCrux',
          productVersion: '0.9.0',
        ),
      )
      ..addUnreachable(
        const CxpDialFailure(
          peerId: 'lintcrux-44-1700000000002',
          host: '127.0.0.1',
          port: 51824,
          error: 'Connection refused',
          consecutiveFailures: 3,
          nextRetryAfterTicks: 3,
        ),
      );
    final base = DateTime(2026, 7, 25, 9);
    var n = 0;
    DateTime at() => base.add(Duration(seconds: n++));
    c
      ..addEvent(
        CrossProbeEvent.peerConnected(peerLabel: 'NetCrux', timestamp: at()),
      )
      ..addEvent(
        CrossProbeEvent(
          kind: CrossProbeEventKind.selectionSent,
          direction: CrossProbeEventDirection.outbound,
          peerLabel: 'NetCrux',
          summary: 'top.u_cdc.sample_a',
          messageKind: CxpMessageKind.notifySelection,
          timestamp: at(),
        ),
      )
      ..addEvent(
        CrossProbeEvent(
          kind: CrossProbeEventKind.selectionReceived,
          direction: CrossProbeEventDirection.inbound,
          peerLabel: 'SimCrux',
          summary: 'top.u_cdc.sample_a[3:0]',
          messageKind: CxpMessageKind.notifySelection,
          timestamp: at(),
        ),
      )
      ..addEvent(
        CrossProbeEvent(
          kind: CrossProbeEventKind.openArtifact,
          direction: CrossProbeEventDirection.inbound,
          peerLabel: 'NetCrux',
          summary: 'cdc_capture · trace',
          messageKind: CxpMessageKind.requestOpenArtifact,
          timestamp: at(),
        ),
      )
      ..addEvent(
        CrossProbeEvent.peerDisconnected(peerLabel: 'SimCrux', timestamp: at()),
      );
    return c;
  }

  @override
  final ValueNotifier<List<PeerIdentity>> peers =
      ValueNotifier<List<PeerIdentity>>(const <PeerIdentity>[]);

  @override
  final ValueNotifier<List<CrossProbeEvent>> events =
      ValueNotifier<List<CrossProbeEvent>>(const <CrossProbeEvent>[]);

  @override
  final ValueNotifier<List<CxpDialFailure>> unreachable =
      ValueNotifier<List<CxpDialFailure>>(const <CxpDialFailure>[]);

  @override
  final ValueNotifier<bool> serverRunning = ValueNotifier<bool>(true);

  @override
  final ValueNotifier<CrossProbeSendFailure?> sendFailure =
      ValueNotifier<CrossProbeSendFailure?>(null);

  /// The peer passed to the most recent [onSendTo], or null.
  PeerIdentity? lastSentTo;

  /// How many times [onSendTo] has been invoked.
  int onSendToCount = 0;

  /// How many times [onOpenPanel] has been invoked.
  int onOpenPanelCount = 0;

  /// How many times [onClose] has been invoked.
  int onCloseCount = 0;

  /// How many times [onClearEvents] has been invoked.
  int onClearEventsCount = 0;

  @override
  void onSendTo(PeerIdentity peer) {
    lastSentTo = peer;
    onSendToCount++;
  }

  @override
  void onOpenPanel() => onOpenPanelCount++;

  @override
  void onClose() => onCloseCount++;

  @override
  void onClearEvents() {
    onClearEventsCount++;
    events.value = const <CrossProbeEvent>[];
  }

  // ── Mutators (test/demo drivers) ──────────────────────────────────────────

  /// Appends [peer] to the connected-peers list.
  void addPeer(PeerIdentity peer) =>
      peers.value = <PeerIdentity>[...peers.value, peer];

  /// Appends [event] to the event buffer (oldest-first).
  void addEvent(CrossProbeEvent event) =>
      events.value = <CrossProbeEvent>[...events.value, event];

  /// Appends [failure] to the unreachable-peers list.
  void addUnreachable(CxpDialFailure failure) =>
      unreachable.value = <CxpDialFailure>[...unreachable.value, failure];

  /// Pushes a rejected-send [failure] so the panel raises its toast (tests /
  /// demos).
  // ignore: use_setters_to_change_properties
  void pushSendFailure(CrossProbeSendFailure failure) =>
      sendFailure.value = failure;

  /// Whether the local CXP server is reported as running.
  bool get running => serverRunning.value;

  /// Sets whether the local CXP server is reported as running.
  set running(bool value) => serverRunning.value = value;

  /// Disposes the backing notifiers.
  void dispose() {
    peers.dispose();
    events.dispose();
    unreachable.dispose();
    serverRunning.dispose();
    sendFailure.dispose();
  }
}
