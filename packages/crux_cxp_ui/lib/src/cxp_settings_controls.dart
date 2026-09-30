// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Localized strings for [CruxCxpSettingsControls]. Every user-visible
/// string arrives from the host app's `L10N`, so the shared widget stays
/// locale-agnostic.
@immutable
class CruxCxpSettingsStrings {
  /// Creates the string set.
  const CruxCxpSettingsStrings({
    required this.enableLabel,
    required this.enableHelp,
    required this.portLabel,
    required this.portHelp,
    required this.portError,
    required this.attentionLabel,
    required this.attentionHelp,
    required this.broadcastLabel,
    required this.broadcastHelp,
  });

  /// "Enable CXP server" switch title.
  final String enableLabel;

  /// Switch subtitle.
  final String enableHelp;

  /// Port field label.
  final String portLabel;

  /// Port field helper text.
  final String portHelp;

  /// Port field error for an out-of-range / non-numeric value.
  final String portError;

  /// "Request attention on cross-probe" switch title.
  final String attentionLabel;

  /// Switch subtitle.
  final String attentionHelp;

  /// "Broadcast selection automatically" switch title.
  final String broadcastLabel;

  /// Switch subtitle.
  final String broadcastHelp;
}

/// The four CXP Cross-Probe settings controls every Crux app exposes —
/// enable switch, port field (validated 1–65535 on submit), request-attention
/// switch, broadcast-selection switch — plus an optional app-specific
/// [statusTile] below them (server running / peer count, whose data source
/// differs per app).
///
/// Extracted from four near-identical hand copies (the suite settings
/// consistency pass): the hosts keep their provider wiring and pass values +
/// callbacks; presentation and port validation live here so the section can
/// never drift between apps again. The attention/broadcast switches disable
/// alongside the server switch, matching the prior per-app behavior.
class CruxCxpSettingsControls extends StatefulWidget {
  /// Creates the controls.
  const CruxCxpSettingsControls({
    required this.strings,
    required this.enabled,
    required this.port,
    required this.requestAttention,
    required this.broadcastSelection,
    required this.onEnabledChanged,
    required this.onPortSubmitted,
    required this.onRequestAttentionChanged,
    required this.onBroadcastSelectionChanged,
    this.statusTile,
    super.key,
  });

  /// Localized strings.
  final CruxCxpSettingsStrings strings;

  /// Whether the CXP server is enabled.
  final bool enabled;

  /// The configured listening port.
  final int port;

  /// Whether cross-probe requests raise window attention.
  final bool requestAttention;

  /// Whether selections broadcast automatically.
  final bool broadcastSelection;

  /// Called when the enable switch flips.
  final ValueChanged<bool> onEnabledChanged;

  /// Called with a validated port (1–65535) on field submit.
  final ValueChanged<int> onPortSubmitted;

  /// Called when the request-attention switch flips.
  final ValueChanged<bool> onRequestAttentionChanged;

  /// Called when the broadcast-selection switch flips.
  final ValueChanged<bool> onBroadcastSelectionChanged;

  /// Optional app-specific status row (server running / peers / last error)
  /// rendered under the controls.
  final Widget? statusTile;

  @override
  State<CruxCxpSettingsControls> createState() =>
      _CruxCxpSettingsControlsState();
}

class _CruxCxpSettingsControlsState extends State<CruxCxpSettingsControls> {
  late final TextEditingController _portController = TextEditingController(
    text: widget.port.toString(),
  );
  String? _portError;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  void _submitPort(String value) {
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      setState(() => _portError = widget.strings.portError);
      return;
    }
    setState(() => _portError = null);
    widget.onPortSubmitted(port);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('cxpSettingsEnable'),
          contentPadding: EdgeInsets.zero,
          title: Text(strings.enableLabel),
          subtitle: Text(strings.enableHelp),
          value: enabled,
          onChanged: widget.onEnabledChanged,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('cxpSettingsPort'),
          controller: _portController,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: true,
            labelText: strings.portLabel,
            helperText: strings.portHelp,
            helperMaxLines: 3,
            errorText: _portError,
          ),
          onSubmitted: _submitPort,
        ),
        SwitchListTile(
          key: const ValueKey('cxpSettingsAttention'),
          contentPadding: EdgeInsets.zero,
          title: Text(strings.attentionLabel),
          subtitle: Text(strings.attentionHelp),
          value: widget.requestAttention,
          onChanged: enabled ? widget.onRequestAttentionChanged : null,
        ),
        SwitchListTile(
          key: const ValueKey('cxpSettingsBroadcast'),
          contentPadding: EdgeInsets.zero,
          title: Text(strings.broadcastLabel),
          subtitle: Text(strings.broadcastHelp),
          value: widget.broadcastSelection,
          onChanged: enabled ? widget.onBroadcastSelectionChanged : null,
        ),
        if (widget.statusTile != null) ...[
          const SizedBox(height: 8),
          widget.statusTile!,
        ],
      ],
    );
  }
}
