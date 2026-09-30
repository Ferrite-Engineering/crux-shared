// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry/src/models/telemetry_policy.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_store.dart';
import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this build offers the telemetry consent surfaces at all — the
/// first-launch disclosure and the Settings → Privacy section.
///
/// The same conditions that gate transmission (`telemetryGateProvider`), read
/// through the same override seams, minus the consent term:
///
///  1. **The beta.** During the beta and without the dev flag there is nothing
///     to consent to, so asking would be asking about a pipeline that is inert.
///     That is an extension of the beta-inert guarantee to the UI rather than a
///     second gate — a beta build must not even *mention* collection it is
///     incapable of doing.
///  2. **An Enterprise policy.** Under [TelemetryPolicy.allow] or
///     [TelemetryPolicy.deny] neither surface mounts, because individual
///     engineers on a managed seat do not see a telemetry prompt: the decision
///     was made for the fleet and the engineer cannot change it. That covers
///     *both* surfaces, not just the first-launch disclosure — a Settings
///     toggle the gate ignores is worse than no toggle, since it tells the user
///     they have a choice and then discards it. Under
///     [TelemetryPolicy.absent], which is every non-Enterprise installation,
///     nothing here changes.
final Provider<bool> telemetryConsentUiVisibleProvider = Provider<bool>(
  (ref) {
    if (!ref.watch(telemetryDevModeProvider) &&
        ref.watch(telemetryBetaPeriodProvider)) {
      return false;
    }
    // The EFFECTIVE policy, so that an `allow` downgraded to `absent` by the
    // region rule still offers the consent surface. If it did not, a user in
    // a consent-required region could never consent: telemetry would stay
    // off with no way to turn it on, and the organization would believe it
    // was on.
    return ref.watch(telemetryEffectivePolicyProvider) ==
        TelemetryPolicy.absent;
  },
  name: 'telemetryConsentUiVisibleProvider',
);

/// Resolves once [TelemetryConsentStore] has read its persisted value back.
///
/// Exists so the disclosure can distinguish "never answered" from "answered,
/// not loaded yet" — see [TelemetryConsentStore.loaded] for why the state alone
/// cannot.
final FutureProvider<void> telemetryConsentReadyProvider = FutureProvider<void>(
  (ref) => ref.watch(telemetryConsentStoreProvider.notifier).loaded,
  name: 'telemetryConsentReadyProvider',
);

/// Whether the first-launch disclosure should be on screen right now.
///
/// True only when the build offers the surfaces at all, the persisted consent
/// has settled, and it settled on [TelemetryConsentState.unset]. Consent leaves
/// `unset` exclusively through the disclosure itself or the Settings toggle,
/// and neither ever writes it back — so "never shown again once answered"
/// needs no separate "already shown" flag to enforce it, and cannot drift out
/// of sync with one. The converse holds too: an installation that quit without
/// answering is still `unset`, and gets the disclosure again on its next
/// launch.
///
/// An Enterprise policy file suppresses this by way of
/// [telemetryConsentUiVisibleProvider] — a `.crux-policy.json` carrying
/// `telemetry: allow | deny` decides org-wide and the individual engineer is
/// never prompted. That is handled one level up rather than here so that the
/// Settings → Privacy section, which reads the same visibility provider,
/// disappears with the dialog instead of surviving it. Both this and the
/// visibility provider stay plain [Provider]s, so an overlay that needs to
/// suppress the prompt for some reason this package does not model can still do
/// it with a single `overrideWithValue(false)`.
final Provider<bool> telemetryConsentPromptVisibleProvider = Provider<bool>(
  (ref) {
    if (!ref.watch(telemetryConsentUiVisibleProvider)) return false;
    if (!ref.watch(telemetryConsentReadyProvider).hasValue) return false;
    return ref.watch(telemetryConsentStoreProvider) ==
        TelemetryConsentState.unset;
  },
  name: 'telemetryConsentPromptVisibleProvider',
);

/// Opens the suite telemetry disclosure page in the system browser.
///
/// Shared by the first-launch disclosure and by Settings → Privacy so the two
/// surfaces cannot come to point at different pages. The URL comes from
/// `CruxTelemetryConfig.documentationUri`, which defaults to the one suite page
/// all four products link to.
Future<void> openTelemetryDocumentation(WidgetRef ref) async {
  final uri = ref.read(cruxTelemetryConfigProvider).documentationUri;
  await ref.read(telemetryUrlLauncherProvider)(uri);
}
