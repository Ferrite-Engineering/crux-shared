// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:crux_telemetry/src/crux_telemetry_strings.dart';
import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_store.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_ui_providers.dart';
import 'package:crux_telemetry/src/providers/telemetry_installation_id.dart';
import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings → Privacy: the permanent home of the telemetry decision.
///
/// Bound to the *same* `telemetry.consent` store the first-launch disclosure
/// writes — so the two surfaces are one setting with two entry points, and a
/// user who flips it here has flipped what the dialog asked about.
///
/// [TelemetryConsentState.unset] renders as off, because that is what it means
/// to the pipeline: `telemetryGateProvider` opens on `enabled` alone.
/// Touching the switch always writes an explicit `enabled`/`disabled`, which
/// also retires the pending disclosure — answering the question in Settings is
/// answering it.
///
/// The host decides *whether* to offer the section: read
/// `telemetryConsentUiVisibleProvider` and omit the whole Privacy category
/// during the beta, so a build incapable of collecting never advertises an
/// opt-out.
class TelemetrySettingsSection extends ConsumerWidget {
  /// Creates the Privacy settings section.
  const TelemetrySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(cruxTelemetryStringsProvider);
    final consent = ref.watch(telemetryConsentStoreProvider);
    final notifier = ref.read(telemetryConsentStoreProvider.notifier);

    return CruxSettingsCard(
      children: [
        SwitchListTile(
          key: const Key('settingsTelemetrySwitch'),
          title: Text(strings.settingsToggleLabel),
          subtitle: Text(strings.settingsToggleDescription),
          value: consent == TelemetryConsentState.enabled,
          onChanged: (enabled) => unawaited(
            notifier.set(
              enabled
                  ? TelemetryConsentState.enabled
                  : TelemetryConsentState.disabled,
            ),
          ),
        ),
        CruxSettingsControlTile(
          title: strings.settingsDocsLabel,
          description: strings.settingsDocsDescription,
          control: OutlinedButton.icon(
            key: const Key('settingsTelemetryDocsButton'),
            onPressed: () => unawaited(openTelemetryDocumentation(ref)),
            icon: const Icon(Icons.open_in_new),
            label: Text(strings.learnMore),
          ),
        ),
        // The deletion path the privacy policy promises. Nothing collected is
        // tied to a person, so a request cannot be honoured by looking anyone
        // up — the id is the only handle, and until it was displayed the path
        // could not be walked at all.
        //
        // Rendered even before the id resolves, so the row never appears late
        // and never shifts the layout under a reader.
        CruxSettingsControlTile(
          title: strings.settingsInstallationIdLabel,
          description: strings.settingsInstallationIdDescription,
          control: Row(
            children: [
              Expanded(
                child: switch (ref.watch(telemetryInstallationIdProvider)) {
                  AsyncData(:final value) => SelectableText(
                    value,
                    key: const Key('settingsTelemetryInstallationId'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  AsyncError() => Text(strings.settingsInstallationIdLabel),
                  _ => const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                },
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('settingsTelemetryInstallationIdCopy'),
                onPressed: () => unawaited(_copyId(context, ref, strings)),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(strings.settingsInstallationIdCopy),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Copies the id, and says so — a value nobody can confirm they copied is a
  /// value they will paste wrong into a support email.
  Future<void> _copyId(
    BuildContext context,
    WidgetRef ref,
    CruxTelemetryStrings strings,
  ) async {
    final id = await ref.read(telemetryInstallationIdProvider.future);
    await Clipboard.setData(ClipboardData(text: id));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(strings.settingsInstallationIdCopied)),
      );
  }
}
