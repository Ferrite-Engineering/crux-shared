// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:flutter/foundation.dart';

/// The app-agnostic contract the shared `CrossProbePanel` renders against.
///
/// This is the **key handoff** for per-app adoption: the shared widget depends
/// on *only* this interface plus `crux_cxp` value types, never on any single
/// product's CXP server/client, Riverpod providers, or localization. Each
/// of the four Crux apps implements one `CrossProbePanelController` that
/// adapts its live CXP state (`CxpServer` connected peers, `CxpPeerConnector`
/// dial-failures, its event log) into the reactive getters below, and routes
/// the panel's commands back into its own selection/name resolver.
///
/// ### Reactive surface
///
/// The three list getters and [serverRunning] are [ValueListenable]s: the panel
/// wraps each in a `ValueListenableBuilder`, so pushing a new value into the
/// backing notifier is all an app must do to update the panel. Apps typically
/// back these with a `ValueNotifier` bridged from their reactive store (a
/// Riverpod `ref.listen`, a `ChangeNotifier`, a stream `.listen`).
///
/// ### Command surface
///
/// The `on*` methods are the panel's outbound commands. They are deliberately
/// side-effecting (not `Future`-returning): the panel fires them and forgets;
/// any result is reflected back through the reactive getters (e.g. a send shows
/// up as a new `selectionSent` event).
abstract interface class CrossProbePanelController {
  /// Currently-connected peers, one row each. Reactive.
  ValueListenable<List<PeerIdentity>> get peers;

  /// Recent cross-probe events, oldest-first (the panel renders newest-first).
  /// Reactive.
  ValueListenable<List<CrossProbeEvent>> get events;

  /// Peers that were discovered but cannot be dialed — one-way connectivity
  /// the healthy-looking peer list would otherwise hide. Reactive.
  ValueListenable<List<CxpDialFailure>> get unreachable;

  /// Whether the local CXP server is running. Drives the offline banner.
  /// Reactive.
  ValueListenable<bool> get serverRunning;

  /// The most recent per-peer send a peer REJECTED — it acked `honored: false`,
  /// or the ack timed out — for the panel to surface as a transient toast. This
  /// is the sender half of R8's "never a silent no-op": a directed send whose
  /// target could not act on the reference must tell the user, not vanish.
  ///
  /// Reactive: the panel shows a snackbar on each non-null transition. A
  /// controller pushes a fresh [CrossProbeSendFailure] per rejection (the app
  /// may reset it to `null` afterwards); one with nothing to report exposes a
  /// constant `ValueNotifier<CrossProbeSendFailure?>(null)`.
  ValueListenable<CrossProbeSendFailure?> get sendFailure;

  /// Resolve the current selection and send it directly to [peer] (the
  /// panel-side entry point for a direct send). The app wires this to its
  /// selection + name resolver; a no-op is acceptable when there is nothing
  /// selected.
  void onSendTo(PeerIdentity peer);

  /// Request that the host reveal/open the docked panel. Wired to the app's
  /// toolbar toggle button; part of this contract so the whole panel command
  /// surface lives in one place. The panel widget itself never calls this
  /// (it is already visible when built).
  void onOpenPanel();

  /// The header close chevron was pressed — the host should collapse/hide the
  /// docked panel.
  void onClose();

  /// The "Clear events" action was pressed — the app should empty its event
  /// buffer (which flows back through [events]).
  void onClearEvents();
}

/// A directed cross-probe send that a peer rejected (or that timed out waiting
/// for its ack), surfaced by the panel as a toast.
///
/// Carries only display data — the human-readable [peerLabel] and the peer's
/// `honored: false` [reason] (null when the send timed out with no ack). The
/// panel composes the toast text via [CrossProbePanelStrings.sendRejected], so
/// the message stays localizable without this value knowing any locale.
@immutable
class CrossProbeSendFailure {
  /// Creates a send-failure record for [peerLabel], with an optional [reason].
  const CrossProbeSendFailure({required this.peerLabel, this.reason});

  /// Human-readable label of the peer that rejected the send.
  final String peerLabel;

  /// The peer's `honored: false` reason, or null when the ack never arrived.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CrossProbeSendFailure &&
          other.peerLabel == peerLabel &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(peerLabel, reason);

  @override
  String toString() =>
      'CrossProbeSendFailure(peerLabel: $peerLabel, reason: $reason)';
}

/// User-facing strings for `CrossProbePanel`, with English defaults.
///
/// A lightweight localization seam: the shared widget can't reach any app's
/// L10N, so an app that wants localized chrome passes a translated
/// [CrossProbePanelStrings]. Everything defaults to sensible English, so the
/// panel is fully usable without one.
@immutable
class CrossProbePanelStrings {
  /// Creates a set of panel strings; every field defaults to English.
  const CrossProbePanelStrings({
    this.title = 'Cross-Probe',
    this.closeTooltip = 'Close cross-probe panel',
    this.serverOffline = 'Cross-probe server is offline.',
    this.peersSectionTitle = 'Connected peers',
    this.noPeers = 'No peers connected.',
    this.sendTooltip = 'Send selection to this peer',
    this.unreachableSectionTitle = 'Unreachable peers',
    this.eventsSectionTitle = 'Recent events',
    this.noEvents = 'No recent events yet.',
    this.clearEventsLabel = 'Clear events',
    this.sendRejected = _defaultSendRejected,
  });

  static String _defaultSendRejected(String peerLabel, String? reason) =>
      reason == null || reason.isEmpty
      ? '$peerLabel could not act on the cross-probe'
      : '$peerLabel: $reason';

  /// Panel header title.
  final String title;

  /// Tooltip on the header close chevron.
  final String closeTooltip;

  /// Banner shown when [CrossProbePanelController.serverRunning] is false.
  final String serverOffline;

  /// "Connected peers" section header.
  final String peersSectionTitle;

  /// Placeholder when there are no connected peers.
  final String noPeers;

  /// Tooltip on each peer row's direct-send button.
  final String sendTooltip;

  /// "Unreachable peers" section header.
  final String unreachableSectionTitle;

  /// "Recent events" section header.
  final String eventsSectionTitle;

  /// Placeholder when the event buffer is empty.
  final String noEvents;

  /// Label on the "Clear events" button.
  final String clearEventsLabel;

  /// Builds the toast text shown when a directed send is rejected — given the
  /// peer's label and its `honored: false` reason (null on an ack timeout). The
  /// default composes an English message; apps pass a localized builder.
  final String Function(String peerLabel, String? reason) sendRejected;
}
