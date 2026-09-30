// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_telemetry/src/models/telemetry_consent_state.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_store.dart';
import 'package:crux_telemetry/src/providers/telemetry_consent_ui_providers.dart';
import 'package:crux_telemetry/src/providers/telemetry_seam_providers.dart';
import 'package:crux_telemetry/src/widgets/telemetry_consent_disclosure.dart';
import 'package:crux_telemetry/src/widgets/telemetry_consent_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mounts the first-launch telemetry disclosure over the routed app content.
///
/// Renders [child] unchanged in every state but one — an installation that has
/// reached a settled [TelemetryConsentState.unset] on a build where the
/// pipeline can actually transmit. That includes every launch after one that
/// was left without an answer: the disclosure keeps returning until the user
/// taps Continue. During the beta with no dev flag the
/// disclosure never mounts at all: `telemetryConsentPromptVisibleProvider` is
/// false, so a beta build shows nothing of it and nothing in [child] is
/// excluded. That is the dark launch extended to the surface.
///
/// Mount it inside `MaterialApp` (so the host's localization delegates resolve
/// for the strings adapter) and *inside* any beta-expiry gate, so an
/// expired-beta blocking modal covers this one rather than the other way
/// round — an expired build has nothing to collect and nothing the user can do
/// about it.
///
/// **While the disclosure is up, nothing behind it can be reached**, by
/// pointer, keyboard or screen reader: [child] is excluded from focus and
/// semantics (`CruxModalGate` from `crux_a11y`), so Tab cannot walk the hidden
/// app and Enter cannot press one of its buttons. When the user answers, focus
/// moves to the first control in [child] rather than falling to nowhere.
class TelemetryConsentGate extends ConsumerWidget {
  /// Creates the gate wrapping [child].
  const TelemetryConsentGate({
    required this.child,
    this.metrics = const CruxTelemetryConsentMetrics(),
    this.isPhoneLayout = false,
    super.key,
  });

  /// The routed app content the gate wraps.
  final Widget child;

  /// Sizing for the disclosure, from the host's own device metrics.
  final CruxTelemetryConsentMetrics metrics;

  /// Whether the host classifies the current display as phone-sized. Selects
  /// the sheet presentation over the dialog card.
  final bool isPhoneLayout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showing = ref.watch(telemetryConsentPromptVisibleProvider);
    return CruxModalGate(
      modal: showing
          ? TelemetryConsentDisclosure(
              strings: ref.watch(cruxTelemetryStringsProvider),
              initialEnabled: ref.watch(telemetryDefaultConsentProvider),
              metrics: metrics,
              isPhoneLayout: isPhoneLayout,
              onContinue: (enabled) => unawaited(
                ref
                    .read(telemetryConsentStoreProvider.notifier)
                    .set(
                      enabled
                          ? TelemetryConsentState.enabled
                          : TelemetryConsentState.disabled,
                    ),
              ),
              onLearnMore: () => unawaited(openTelemetryDocumentation(ref)),
            )
          : null,
      child: child,
    );
  }
}
