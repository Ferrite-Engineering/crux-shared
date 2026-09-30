// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_eula/src/crux_eula_strings.dart';
import 'package:crux_eula/src/eula_document.dart';
import 'package:crux_eula/src/providers/eula_acceptance_store.dart';
import 'package:crux_eula/src/providers/eula_seam_providers.dart';
import 'package:crux_eula/src/widgets/eula_acceptance_dialog.dart';
import 'package:crux_eula/src/widgets/eula_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mounts the licence agreement over the routed app content until it is
/// accepted.
///
/// Renders [child] unchanged in every state but one — an installation whose
/// stored accepted version is not [kCruxEulaVersion], on a build where the
/// store has finished loading. That covers a genuine first launch, a launch
/// after the agreement was left unanswered, and the section 2.3 re-acceptance
/// after [kCruxEulaVersion] is raised.
///
/// **Where this sits in the nesting, and why it is not a preference.** The gate
/// goes *outside* `TelemetryConsentGate`, so the agreement's modal covers the
/// telemetry disclosure rather than the other way round. The telemetry
/// disclosure asks for consent to a term this agreement defines (section 8), so
/// collecting that consent first inverts the agreement — the user would be
/// answering a question about a contract they had not been shown. It is also
/// the only ordering under which the EEA / UK / CH / KR opt-in default is
/// defensible: consent gathered before the user has accepted the agreement that
/// defines what is collected is not informed consent.
///
/// It goes *inside* any beta-expiry gate, following the same rule that puts the
/// telemetry disclosure there: an expired build's blocking modal wins, because
/// an expired build has nothing to license and nothing the user can do about
/// it.
///
/// So the order, outermost first, is: beta expiry → **EULA** → telemetry
/// consent → update banner → routed content.
///
/// **It waits for the store before it decides.** The acceptance store publishes
/// `null` synchronously and loads asynchronously, so for the first frames of a
/// cold start a returning user looks exactly like a new one. Mounting on that
/// value would flash a licence agreement at someone who accepted it a year ago.
/// The gate therefore renders [child] until
/// [CruxEulaAcceptanceStore.loaded] completes — which, because that completer
/// is signalled in a `finally`, also resolves when the store is unreadable. An
/// unreadable store asks; it never silently proceeds.
///
/// **While the agreement is up, nothing behind it can be reached**, by pointer,
/// keyboard or screen reader: [child] is excluded from focus and semantics
/// (`CruxModalGate` from `crux_a11y`), so Tab cannot walk the hidden app and
/// Enter cannot press one of its buttons. When the agreement is accepted, focus
/// moves to the first control in [child] — the telemetry disclosure's, when
/// that is the next thing waiting — rather than falling to nowhere.
class CruxEulaGate extends ConsumerStatefulWidget {
  /// Creates the gate wrapping [child].
  const CruxEulaGate({
    required this.child,
    this.strings = const CruxEulaStrings(),
    this.metrics = const CruxEulaMetrics(),
    this.isPhoneLayout = false,
    this.presentAgreement = true,
    super.key,
  });

  /// The routed app content the gate wraps.
  final Widget child;

  /// Copy for the acceptance surface. English by decision — see
  /// [CruxEulaStrings].
  final CruxEulaStrings strings;

  /// Sizing for the dialog, from the host's own device metrics.
  final CruxEulaMetrics metrics;

  /// Whether the host classifies the current display as phone-sized. Selects
  /// the sheet presentation over the dialog card.
  final bool isPhoneLayout;

  /// Whether this surface presents the agreement at all.
  ///
  /// False only where the build is embedded in another application's UI — a
  /// VSCode webview owned by the extension, say — and the agreement belongs to
  /// the host rather than to a panel inside it. Every standalone surface
  /// leaves it true, including a plain browser tab, where there is no other
  /// acceptance moment and suppressing it would leave the agreement unshown
  /// entirely.
  ///
  /// Suppressing the surface is **not** an acceptance. Nothing is read as
  /// accepted and nothing is written, so the same install presents the
  /// agreement normally the next time it runs standalone. Recording a consent
  /// that was never given would be the other way to make this dialog go away,
  /// and it is the wrong one.
  final bool presentAgreement;

  @override
  ConsumerState<CruxEulaGate> createState() => _CruxEulaGateState();
}

class _CruxEulaGateState extends ConsumerState<CruxEulaGate> {
  bool _storeLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_awaitStore());
  }

  Future<void> _awaitStore() async {
    await ref.read(cruxEulaAcceptanceStoreProvider.notifier).loaded;
    if (!mounted) return;
    setState(() => _storeLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    return CruxModalGate(modal: _agreement(), child: widget.child);
  }

  /// The acceptance dialog, or `null` when nothing needs accepting.
  Widget? _agreement() {
    if (!widget.presentAgreement) return null;
    if (!_storeLoaded) return null;
    if (!ref.watch(cruxEulaAcceptanceRequiredProvider)) return null;

    // Non-null and different from the current version means they accepted an
    // earlier one; that is the section 2.3 case and the dialog says so.
    final accepted = ref.watch(cruxEulaAcceptanceStoreProvider);
    final onOpenOnline = ref.watch(cruxEulaOpenOnlineProvider);
    final onDecline = ref.watch(cruxEulaOnDeclineProvider);

    return CruxEulaAcceptanceDialog(
      strings: widget.strings,
      metrics: widget.metrics,
      isPhoneLayout: widget.isPhoneLayout,
      isReacceptance: accepted != null,
      onAccept: () => unawaited(
        ref.read(cruxEulaAcceptanceStoreProvider.notifier).accept(),
      ),
      onDecline: onDecline,
      onOpenOnline: onOpenOnline == null
          ? null
          : () => unawaited(onOpenOnline()),
    );
  }
}
