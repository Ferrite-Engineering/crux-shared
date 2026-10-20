// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/cross_probe_panel.dart';
import 'package:crux_cxp_ui/src/cross_probe_panel_controller.dart';
import 'package:crux_cxp_ui/src/cxp_settings_controls.dart';
import 'package:crux_cxp_ui/src/runtime/cxp_providers.dart';
import 'package:crux_cxp_ui/src/send/cross_probe_surfaces.dart';
import 'package:crux_cxp_ui/src/send/cross_probe_targets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared cross-probe panel bound to the shared runtime: the peers, the
/// unreachable peers and the event log come from the CXP providers, and each
/// peer row's send goes through the same send as every other surface.
///
/// A product mounts this as its dock tab and supplies only what is its own:
/// how to read the current selection, and how to close the panel.
class CruxCrossProbePanel extends ConsumerStatefulWidget {
  /// Creates the bound panel.
  const CruxCrossProbePanel({
    required this.selection,
    required this.onClose,
    this.showHeader = false,
    this.sendBadgeBuilder,
    super.key,
  });

  /// Resolves the current selection when a peer row's send is pressed.
  final CrossProbeSelection? Function() selection;

  /// Closes the panel (the header chevron, when shown).
  final VoidCallback onClose;

  /// Whether to draw the panel's own header; a dock tab already has one.
  final bool showHeader;

  /// See [CrossProbePanel.sendBadgeBuilder].
  final CrossProbeSendBadgeBuilder? sendBadgeBuilder;

  @override
  ConsumerState<CruxCrossProbePanel> createState() =>
      _CruxCrossProbePanelState();
}

class _CruxCrossProbePanelState extends ConsumerState<CruxCrossProbePanel>
    implements CrossProbePanelController {
  final ValueNotifier<List<PeerIdentity>> _peers =
      ValueNotifier<List<PeerIdentity>>(const <PeerIdentity>[]);
  final ValueNotifier<List<CrossProbeEvent>> _events =
      ValueNotifier<List<CrossProbeEvent>>(const <CrossProbeEvent>[]);
  final ValueNotifier<List<CxpDialFailure>> _unreachable =
      ValueNotifier<List<CxpDialFailure>>(const <CxpDialFailure>[]);
  final ValueNotifier<bool> _serverRunning = ValueNotifier<bool>(false);
  // The shared send reports its own outcome, so the panel's toaster has
  // nothing to show.
  final ValueNotifier<CrossProbeSendFailure?> _sendFailure =
      ValueNotifier<CrossProbeSendFailure?>(null);

  @override
  void initState() {
    super.initState();
    ref
      ..listenManual<List<PeerIdentity>>(
        cxpPeersProvider,
        (_, next) => _peers.value = next,
        fireImmediately: true,
      )
      ..listenManual<List<CrossProbeEvent>>(
        cxpEventLogProvider,
        (_, next) => _events.value = next,
        fireImmediately: true,
      )
      ..listenManual<AsyncValue<List<CxpDialFailure>>>(
        cxpUnreachablePeersProvider,
        (_, next) => _unreachable.value = next.value ?? const [],
        fireImmediately: true,
      )
      ..listenManual<CxpServerStatus>(
        cxpServerStatusProvider,
        (_, next) => _serverRunning.value = next.running,
        fireImmediately: true,
      );
  }

  @override
  void dispose() {
    _peers.dispose();
    _events.dispose();
    _unreachable.dispose();
    _serverRunning.dispose();
    _sendFailure.dispose();
    super.dispose();
  }

  @override
  ValueListenable<List<PeerIdentity>> get peers => _peers;

  @override
  ValueListenable<List<CrossProbeEvent>> get events => _events;

  @override
  ValueListenable<List<CxpDialFailure>> get unreachable => _unreachable;

  @override
  ValueListenable<bool> get serverRunning => _serverRunning;

  @override
  ValueListenable<CrossProbeSendFailure?> get sendFailure => _sendFailure;

  @override
  void onSendTo(PeerIdentity peer) => unawaited(
    sendCrossProbe(context, ref, peer: peer, selection: widget.selection()),
  );

  @override
  void onOpenPanel() {}

  @override
  void onClose() => widget.onClose();

  @override
  void onClearEvents() => ref.read(cxpEventLogProvider.notifier).clear();

  @override
  Widget build(BuildContext context) {
    return CrossProbePanel(
      controller: this,
      strings: cxpStringsOf(context, ref.read).panel,
      showHeader: widget.showHeader,
      sendBadgeBuilder: widget.sendBadgeBuilder,
    );
  }
}

/// Settings > CXP Cross-Probe, bound to [cxpSettingsProvider]: the four
/// shared controls and a status line (running on which port, how many
/// peers, and why the server is unavailable when it is).
class CruxCxpSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const CruxCxpSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = cxpStringsOf(context, ref.read);
    final settings = ref.watch(cxpSettingsProvider);
    final notifier = ref.read(cxpSettingsProvider.notifier);
    final status = ref.watch(cxpServerStatusProvider);
    final peerCount = ref.watch(cxpConnectedPeerCountProvider);
    final theme = Theme.of(context);
    final statusText = <String>[
      if (status.running && status.port != null)
        strings.statusRunning(status.port!)
      else
        strings.statusStopped,
      if (status.running) strings.peersConnected(peerCount),
    ].join(', ');
    return CruxCxpSettingsControls(
      // A new port from elsewhere re-seeds the field.
      key: ValueKey<int>(settings.port),
      strings: strings.settings,
      enabled: settings.enabled,
      port: settings.port,
      requestAttention: settings.requestAttention,
      broadcastSelection: settings.broadcastSelection,
      onEnabledChanged: (value) =>
          unawaited(notifier.setEnabled(enabled: value)),
      onPortSubmitted: (port) => unawaited(notifier.setPort(port)),
      onRequestAttentionChanged: (value) =>
          unawaited(notifier.setRequestAttention(requestAttention: value)),
      onBroadcastSelectionChanged: (value) =>
          unawaited(notifier.setBroadcastSelection(broadcastSelection: value)),
      statusTile: MergeSemantics(
        child: Column(
          key: const ValueKey('cxpSettingsStatus'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.statusLabel, style: theme.textTheme.labelMedium),
            Text(statusText, style: theme.textTheme.bodySmall),
            if (status.problem != null)
              Text(
                status.problem!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
