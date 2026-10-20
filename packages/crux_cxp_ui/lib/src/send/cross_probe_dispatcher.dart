// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cxp_strings.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_providers.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_runtime.dart';
import 'package:crux_cxp_ui/src/send/cross_probe_targets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a cross-probe send ended. One vocabulary for every surface in every
/// product.
enum CrossProbeOutcomeKind {
  /// The peer acknowledged and showed it.
  sent,

  /// The peer acknowledged and declined, with a reason.
  refused,

  /// The send left but no acknowledgement came back in time.
  noResponse,

  /// The peer was gone by the time of the send.
  peerGone,

  /// This product's CXP server is off.
  serverOff,

  /// Nothing was selected.
  nothingSelected,

  /// The target can show none of the selection's element kinds.
  notShowable,

  /// No peer is running.
  noPeers,

  /// The product's originate gate refused, and has explained why itself.
  denied,
}

/// The result of one cross-probe send.
@immutable
class CrossProbeOutcome {
  /// Creates an outcome.
  const CrossProbeOutcome(this.kind, {this.target, this.reason});

  /// What happened.
  final CrossProbeOutcomeKind kind;

  /// The target's label (`WaveCrux`, or `WaveCrux 2` for one of several
  /// windows), when there was one.
  final String? target;

  /// The peer's reason, for [CrossProbeOutcomeKind.refused].
  final String? reason;

  /// Whether the user must be told something went wrong.
  bool get isFailure =>
      kind != CrossProbeOutcomeKind.sent &&
      kind != CrossProbeOutcomeKind.denied;

  /// The sentence the user reads (or hears) for this outcome; null for
  /// [CrossProbeOutcomeKind.denied], which the gate reported already.
  String? message(CruxCxpStrings strings) {
    final who = target ?? '';
    return switch (kind) {
      CrossProbeOutcomeKind.sent => strings.outcomeSent(who),
      CrossProbeOutcomeKind.refused =>
        reason == null || reason!.isEmpty
            ? strings.outcomeNotShowable(who)
            : strings.outcomeRefused(who, reason!),
      CrossProbeOutcomeKind.noResponse => strings.outcomeNoResponse(who),
      CrossProbeOutcomeKind.peerGone => strings.outcomePeerGone(who),
      CrossProbeOutcomeKind.serverOff => strings.outcomeServerOff,
      CrossProbeOutcomeKind.nothingSelected => strings.outcomeNothingSelected,
      CrossProbeOutcomeKind.notShowable => strings.outcomeNotShowable(who),
      CrossProbeOutcomeKind.noPeers => strings.outcomeNoPeers,
      CrossProbeOutcomeKind.denied => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CrossProbeOutcome &&
          other.kind == kind &&
          other.target == target &&
          other.reason == reason);

  @override
  int get hashCode => Object.hash(kind, target, reason);

  @override
  String toString() => 'CrossProbeOutcome(${kind.name}, $target, $reason)';
}

/// A product's say over whether a cross-probe may leave.
///
/// Cross-probing is free in every tier, so no product installs one today;
/// the seam exists so a later pricing decision is one override, never four
/// surfaces. [admit] runs before every send; when it returns false it has
/// already shown the product's own explanation (its upgrade dialog), and
/// the send ends as [CrossProbeOutcomeKind.denied].
abstract interface class CrossProbeGate {
  /// Whether the send to [peer] may proceed.
  Future<bool> admit(BuildContext context, PeerIdentity peer);
}

/// The originate gate; null (the default) admits every send.
final Provider<CrossProbeGate?> crossProbeGateProvider =
    Provider<CrossProbeGate?>((_) => null, name: 'crossProbeGateProvider');

/// Sends cross-probes the one way every surface does: always an
/// acknowledged `request_highlight`, one timeout, one outcome vocabulary.
class CrossProbeDispatcher {
  /// Creates a dispatcher reading providers through the given reader.
  CrossProbeDispatcher(this._read, {this.timeout = kCxpAckTimeout});

  final CxpProviderReader _read;

  /// How long a send waits for the acknowledgement.
  final Duration timeout;

  /// Sends [selection] to [peer]. [label] names the target in the outcome
  /// (defaults to the product's display name).
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    final who = label ?? cxpProductDisplayName(peer.productName);
    if (selection == null || selection.isEmpty) {
      return const CrossProbeOutcome(CrossProbeOutcomeKind.nothingSelected);
    }
    final runtime = _read(cxpRuntimeProvider).value;
    if (runtime == null || !runtime.isAvailable) {
      return const CrossProbeOutcome(CrossProbeOutcomeKind.serverOff);
    }
    final element = crossProbeElementFor(selection, peer);
    if (element == null) {
      return CrossProbeOutcome(CrossProbeOutcomeKind.notShowable, target: who);
    }
    final delivery = await runtime.requestHighlight(
      peer.peerId,
      RequestHighlight(
        element: element,
        metadata: selection.metadata,
        coordinate: selection.coordinate,
      ),
      timeout: timeout,
      summary: selection.displayName ?? element.path,
    );
    if (!delivery.delivered) {
      return CrossProbeOutcome(CrossProbeOutcomeKind.peerGone, target: who);
    }
    final ack = delivery.ack;
    if (ack == null) {
      return CrossProbeOutcome(CrossProbeOutcomeKind.noResponse, target: who);
    }
    if (!ack.honored) {
      return CrossProbeOutcome(
        CrossProbeOutcomeKind.refused,
        target: who,
        reason: ack.reason,
      );
    }
    return CrossProbeOutcome(CrossProbeOutcomeKind.sent, target: who);
  }
}

/// The dispatcher.
final Provider<CrossProbeDispatcher> crossProbeDispatcherProvider =
    Provider<CrossProbeDispatcher>(
      (ref) => CrossProbeDispatcher(ref.read),
      name: 'crossProbeDispatcherProvider',
    );
