// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/src/cross_probe_event.dart';
import 'package:crux_cxp_ui/src/cross_probe_panel_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Builds the badge shown beside one peer row's direct-send button, or
/// returns null for no badge.
///
/// The panel cannot know any product's tiers, so a product that prices
/// cross-probe origination supplies this to label the button before it is
/// pressed: the suite's badge-before-click convention, which a gate that
/// only answers after the click does not meet on its own. [peer] is the row's
/// peer, for a product whose answer differs per peer; most ignore it.
typedef CrossProbeSendBadgeBuilder =
    Widget? Function(BuildContext context, PeerIdentity peer);

/// The shared, docked cross-probe side-panel.
///
/// One reusable panel adopted by all four Crux products, richer than any
/// current app's: a **Connected Peers** list with a per-peer direct-send
/// control, a persistent **Unreachable peers** warning surface, and a
/// **Recent Events** log that includes the categories the divergent
/// per-app logs were missing (selection *received* and *open-artifact*).
///
/// It is a **docked side-panel**, not a modal dialog: it fills whatever
/// bounds its host docks it into and carries its own header with a **close
/// chevron** (mirroring the collapse affordance of the suite's other docked
/// panels). WaveCrux's old modal `Dialog` presentation is retired in favour of
/// this.
///
/// The widget depends on nothing but a [CrossProbePanelController] and
/// `crux_cxp` value types — see that interface for the app-adoption contract.
/// It is theme-aware: every colour comes from the ambient [ColorScheme], so it
/// renders correctly in both light and dark themes.
class CrossProbePanel extends StatelessWidget {
  /// Creates a docked cross-probe panel bound to [controller].
  const CrossProbePanel({
    required this.controller,
    this.strings = const CrossProbePanelStrings(),
    this.showHeader = true,
    this.sendBadgeBuilder,
    super.key,
  });

  /// The app-supplied adapter over its live CXP state and commands.
  final CrossProbePanelController controller;

  /// User-facing strings (localization seam); English by default.
  final CrossProbePanelStrings strings;

  /// Whether to render the panel's own icon + title + close-chevron header.
  ///
  /// Hosts that dock the panel as a `CruxDock` tab pass `false`: the tab
  /// already carries the icon, the label and the `×`, and a second header
  /// saying the same three things directly underneath is the duplicated
  /// chrome the dock model exists to remove. Defaults to true for
  /// standalone embeddings.
  final bool showHeader;

  /// Builds the badge each peer row shows beside its direct-send button,
  /// typically the suite's feature-tier chip for the tier that originating a
  /// cross-probe requires.
  ///
  /// Optional: null (the default), or a builder that returns null for a row,
  /// renders the send button alone, so a product with no licence model keeps
  /// a fully usable panel. The badge labels the button and does not gate it;
  /// the product's [CrossProbePanelController.onSendTo] still owns the
  /// decision and the explanation of a denial.
  final CrossProbeSendBadgeBuilder? sendBadgeBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SendFailureToaster(
      failures: controller.sendFailure,
      messageFor: (failure) =>
          strings.sendRejected(failure.peerLabel, failure.reason),
      child: Material(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              _Header(strings: strings, onClose: controller.onClose),
              const Divider(height: 1),
            ],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: controller.serverRunning,
                    builder: (context, running, _) => running
                        ? const SizedBox.shrink()
                        : _OfflineBanner(strings),
                  ),
                  _SectionHeader(strings.peersSectionTitle),
                  ValueListenableBuilder<List<PeerIdentity>>(
                    valueListenable: controller.peers,
                    builder: (context, peers, _) => _PeersSection(
                      peers: peers,
                      strings: strings,
                      onSendTo: controller.onSendTo,
                      sendBadgeBuilder: sendBadgeBuilder,
                    ),
                  ),
                  ValueListenableBuilder<List<CxpDialFailure>>(
                    valueListenable: controller.unreachable,
                    builder: (context, failures, _) => _UnreachableSection(
                      failures: failures,
                      strings: strings,
                    ),
                  ),
                  const Divider(),
                  ValueListenableBuilder<List<CrossProbeEvent>>(
                    valueListenable: controller.events,
                    builder: (context, events, _) => _EventsSection(
                      events: events,
                      strings: strings,
                      onClearEvents: controller.onClearEvents,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps [child] and surfaces each non-null [failures] transition as a
/// transient snackbar via the ambient [ScaffoldMessenger] — the shared home for
/// the "peer rejected the cross-probe" toast (R8: never a silent no-op). Every
/// app that adopts the panel gets it for free; a controller that reports no
/// failures (a constant null notifier) shows nothing. Stateful so the listener
/// is attached once and re-bound when the panel swaps controllers.
class _SendFailureToaster extends StatefulWidget {
  const _SendFailureToaster({
    required this.failures,
    required this.messageFor,
    required this.child,
  });

  final ValueListenable<CrossProbeSendFailure?> failures;
  final String Function(CrossProbeSendFailure failure) messageFor;
  final Widget child;

  @override
  State<_SendFailureToaster> createState() => _SendFailureToasterState();
}

class _SendFailureToasterState extends State<_SendFailureToaster> {
  @override
  void initState() {
    super.initState();
    widget.failures.addListener(_onFailure);
  }

  @override
  void didUpdateWidget(_SendFailureToaster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.failures, widget.failures)) {
      oldWidget.failures.removeListener(_onFailure);
      widget.failures.addListener(_onFailure);
    }
  }

  @override
  void dispose() {
    widget.failures.removeListener(_onFailure);
    super.dispose();
  }

  void _onFailure() {
    final failure = widget.failures.value;
    if (failure == null) return;
    // Defer to after the frame: the listener can fire mid-build (an app pushes
    // the failure from a send handler), and showing a snackbar synchronously
    // during build asserts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const Key('cross_probe_send_failure'),
            content: Text(widget.messageFor(failure)),
          ),
        );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Header extends StatelessWidget {
  const _Header({required this.strings, required this.onClose});

  final CrossProbePanelStrings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Icon(Icons.sensors, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              strings.title,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('cross_probe_close'),
            icon: const Icon(Icons.chevron_right),
            tooltip: strings.closeTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner(this.strings);

  final CrossProbePanelStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('cross_probe_offline_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: scheme.errorContainer,
      child: Text(
        strings.serverOffline,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.outline),
    ),
  );
}

class _PeersSection extends StatelessWidget {
  const _PeersSection({
    required this.peers,
    required this.strings,
    required this.onSendTo,
    required this.sendBadgeBuilder,
  });

  final List<PeerIdentity> peers;
  final CrossProbePanelStrings strings;
  final void Function(PeerIdentity peer) onSendTo;
  final CrossProbeSendBadgeBuilder? sendBadgeBuilder;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return _Placeholder(strings.noPeers);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final peer in peers)
          ListTile(
            dense: true,
            leading: const Icon(Icons.adjust),
            title: Text('${peer.productName} ${peer.productVersion}'),
            subtitle: Text(
              peer.peerId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _sendControl(context, peer),
          ),
      ],
    );
  }

  Widget _sendControl(BuildContext context, PeerIdentity peer) {
    final button = IconButton(
      key: Key('cross_probe_send_${peer.peerId}'),
      icon: const Icon(Icons.send),
      tooltip: strings.sendTooltip,
      onPressed: () => onSendTo(peer),
    );
    final badge = sendBadgeBuilder?.call(context, peer);
    if (badge == null) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: Key('cross_probe_send_badge_${peer.peerId}'),
          child: badge,
        ),
        const SizedBox(width: 4),
        button,
      ],
    );
  }
}

class _UnreachableSection extends StatelessWidget {
  const _UnreachableSection({required this.failures, required this.strings});

  final List<CxpDialFailure> failures;
  final CrossProbePanelStrings strings;

  @override
  Widget build(BuildContext context) {
    if (failures.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const Key('cross_probe_unreachable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(strings.unreachableSectionTitle),
        for (final failure in failures)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failure.peerId,
                        style: TextStyle(color: scheme.error),
                      ),
                      Text(
                        '${failure.host}:${failure.port}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EventsSection extends StatelessWidget {
  const _EventsSection({
    required this.events,
    required this.strings,
    required this.onClearEvents,
  });

  final List<CrossProbeEvent> events;
  final CrossProbePanelStrings strings;
  final VoidCallback onClearEvents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.eventsSectionTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (events.isNotEmpty)
                TextButton(
                  key: const Key('cross_probe_clear_events'),
                  onPressed: onClearEvents,
                  child: Text(strings.clearEventsLabel),
                ),
            ],
          ),
        ),
        if (events.isEmpty)
          _Placeholder(strings.noEvents)
        else
          // Newest-first: the buffer appends, so iterate in reverse.
          for (var i = events.length - 1; i >= 0; i--)
            _EventRow(event: events[i]),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CrossProbeEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final descriptor = _EventDescriptor.of(event, scheme);
    final subtitle = event.summary == null
        ? event.peerLabel
        : '${event.peerLabel} · ${event.summary}';
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(descriptor.icon, size: 18, color: descriptor.color),
      title: Text(descriptor.label),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _formatTime(event.timestamp),
        style: TextStyle(color: scheme.outline, fontSize: 11),
      ),
    );
  }

  static String _formatTime(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(ts.hour)}:${two(ts.minute)}:${two(ts.second)}';
  }
}

/// Maps a [CrossProbeEvent] to the icon, colour, and label the row renders.
///
/// Kept as a small value so a widget test can assert on the same label the UI
/// shows for each [CrossProbeEventKind], including selection received and
/// open-artifact.
class _EventDescriptor {
  const _EventDescriptor(this.icon, this.color, this.label);

  factory _EventDescriptor.of(CrossProbeEvent event, ColorScheme scheme) {
    switch (event.kind) {
      case CrossProbeEventKind.peerConnected:
        return _EventDescriptor(Icons.link, scheme.primary, 'Peer connected');
      case CrossProbeEventKind.peerDisconnected:
        return _EventDescriptor(
          Icons.link_off,
          scheme.outline,
          'Peer disconnected',
        );
      case CrossProbeEventKind.selectionSent:
        return _EventDescriptor(
          Icons.north_east,
          scheme.primary,
          'Selection sent',
        );
      case CrossProbeEventKind.selectionReceived:
        return _EventDescriptor(
          Icons.south_west,
          scheme.tertiary,
          'Selection received',
        );
      case CrossProbeEventKind.highlightSent:
        return _EventDescriptor(
          Icons.north_east,
          scheme.primary,
          'Highlight sent',
        );
      case CrossProbeEventKind.highlightReceived:
        return _EventDescriptor(
          Icons.south_west,
          scheme.tertiary,
          'Highlight received',
        );
      case CrossProbeEventKind.openArtifact:
        return _EventDescriptor(
          Icons.file_open,
          scheme.secondary,
          'Open artifact',
        );
      case CrossProbeEventKind.other:
        return _EventDescriptor(
          Icons.swap_horiz,
          scheme.outline,
          event.messageKind ?? 'Event',
        );
    }
  }

  final IconData icon;
  final Color color;
  final String label;
}
