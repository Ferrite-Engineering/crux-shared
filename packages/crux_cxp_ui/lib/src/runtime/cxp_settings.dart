// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The four CXP settings every product exposes under Settings > CXP
/// Cross-Probe.
@immutable
class CxpSettings {
  /// Creates a settings value.
  const CxpSettings({
    required this.enabled,
    required this.port,
    this.requestAttention = true,
    this.broadcastSelection = true,
  });

  /// Whether the CXP server runs. Off means no listening socket and no
  /// discovery manifest.
  final bool enabled;

  /// The port the server listens on, 1 to 65535.
  final int port;

  /// Whether a cross-probe from a peer asks for the user's attention (a dock
  /// bounce or a taskbar flash; never a focus steal).
  final bool requestAttention;

  /// Whether this product announces its selection to peers as it changes.
  /// Off, only explicit sends leave.
  final bool broadcastSelection;

  /// Whether [port] is a usable TCP port.
  static bool isValidPort(int port) => port >= 1 && port <= 65535;

  /// A copy with the given fields replaced.
  CxpSettings copyWith({
    bool? enabled,
    int? port,
    bool? requestAttention,
    bool? broadcastSelection,
  }) => CxpSettings(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    requestAttention: requestAttention ?? this.requestAttention,
    broadcastSelection: broadcastSelection ?? this.broadcastSelection,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CxpSettings &&
          other.enabled == enabled &&
          other.port == port &&
          other.requestAttention == requestAttention &&
          other.broadcastSelection == broadcastSelection);

  @override
  int get hashCode =>
      Object.hash(enabled, port, requestAttention, broadcastSelection);

  @override
  String toString() =>
      'CxpSettings(enabled: $enabled, port: $port, '
      'requestAttention: $requestAttention, '
      'broadcastSelection: $broadcastSelection)';
}

/// Reads and writes [CxpSettings] under the keys every product has used
/// since the first release: `<prefix>cxpServerEnabled`,
/// `<prefix>cxpServerPort`, `<prefix>requestAttentionOnCrossProbe` and
/// `<prefix>broadcastSelectionOnCrossProbe`.
///
/// The prefix is the product's own (`settings.` in WaveCrux and LintCrux,
/// `netcrux.` and `simcrux.` in the other two), so a choice saved by an
/// earlier release is read unchanged. A missing or wrong-typed value reads
/// as its default; an out-of-range port reads as [defaultPort].
class CxpSettingsCodec implements SettingsCodec<CxpSettings> {
  /// Creates a codec for one product.
  const CxpSettingsCodec({
    required this.prefix,
    required this.defaultPort,
    this.defaultEnabled = true,
  });

  /// The product's preference-key prefix, including its trailing dot.
  final String prefix;

  /// The product's own default port.
  final int defaultPort;

  /// Whether the server runs when the user has never said.
  final bool defaultEnabled;

  /// The enable key.
  String get enabledKey => '${prefix}cxpServerEnabled';

  /// The port key.
  String get portKey => '${prefix}cxpServerPort';

  /// The request-attention key.
  String get requestAttentionKey => '${prefix}requestAttentionOnCrossProbe';

  /// The broadcast-selection key.
  String get broadcastSelectionKey => '${prefix}broadcastSelectionOnCrossProbe';

  /// The value a product starts with before anything is saved.
  CxpSettings get defaults =>
      CxpSettings(enabled: defaultEnabled, port: defaultPort);

  T _read<T>(SharedPreferences prefs, String key, T fallback) {
    try {
      final value = prefs.get(key);
      return value is T ? value : fallback;
    } on Object {
      return fallback;
    }
  }

  @override
  Future<CxpSettings> load(SharedPreferences prefs) async {
    final port = _read<int>(prefs, portKey, defaultPort);
    return CxpSettings(
      enabled: _read<bool>(prefs, enabledKey, defaultEnabled),
      port: CxpSettings.isValidPort(port) ? port : defaultPort,
      requestAttention: _read<bool>(prefs, requestAttentionKey, true),
      broadcastSelection: _read<bool>(prefs, broadcastSelectionKey, true),
    );
  }

  @override
  Future<void> save(SharedPreferences prefs, CxpSettings settings) async {
    await prefs.setBool(enabledKey, settings.enabled);
    await prefs.setInt(portKey, settings.port);
    await prefs.setBool(requestAttentionKey, settings.requestAttention);
    await prefs.setBool(broadcastSelectionKey, settings.broadcastSelection);
  }
}
