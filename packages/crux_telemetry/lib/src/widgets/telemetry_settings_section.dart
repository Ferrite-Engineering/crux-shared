// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_ide_layout/crux_ide_layout.dart' show showCruxInfoSnack;
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
    final storedId = ref.watch(telemetryStoredInstallationIdProvider);
    final copyableId = storedId.value;

    return CruxSettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: CruxFormRow.toggle(
            key: const Key('settingsTelemetrySwitch'),
            label: strings.settingsToggleLabel,
            help: strings.settingsToggleDescription,
            value: consent == TelemetryConsentState.enabled,
            onChanged: (enabled) => unawaited(
              notifier.set(
                enabled
                    ? TelemetryConsentState.enabled
                    : TelemetryConsentState.disabled,
              ),
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
        //
        // Reads the STORED id and never mints one: opening this screen must
        // not create an identifier on an installation that has not opted in.
        // An id left by an earlier opt-in is still shown with measurement
        // off, because it is what a deletion request needs. The live service
        // mints on its first flush and invalidates the stored provider, so
        // turning measurement on here fills the row in without a reopen.
        CruxSettingsControlTile(
          title: strings.settingsInstallationIdLabel,
          description: strings.settingsInstallationIdDescription,
          control: Row(
            children: [
              Expanded(
                // Matched on the value rather than the state class, so a
                // refresh after minting keeps showing what it had rather than
                // flashing the spinner.
                child: switch (storedId) {
                  AsyncValue(value: final value?) => SelectableText(
                    value,
                    key: const Key('settingsTelemetryInstallationId'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  AsyncValue(hasValue: true) => Text(
                    strings.settingsInstallationIdNone,
                    key: const Key('settingsTelemetryInstallationIdNone'),
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
              // Disabled rather than removed when there is nothing to copy,
              // so the row keeps its shape when an id arrives.
              OutlinedButton.icon(
                key: const Key('settingsTelemetryInstallationIdCopy'),
                onPressed: copyableId == null
                    ? null
                    : () => unawaited(_copyId(context, copyableId, strings)),
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
    String id,
    CruxTelemetryStrings strings,
  ) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!context.mounted) return;
    showCruxInfoSnack(context, strings.settingsInstallationIdCopied);
  }
}
