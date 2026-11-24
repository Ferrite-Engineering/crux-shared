// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Whether the user has answered the telemetry disclosure, and how.
///
/// The state is **tri**-state on purpose. [unset] is not a synonym for
/// [disabled]: it is the state in which the first-launch "help make this
/// product better" disclosure has not been answered yet — whether or not it
/// was ever on screen — and it is the only signal that tells the UI to present
/// it. Collapsing the two would either re-ask a
/// user who has already declined, or silently read "never asked" as consent —
/// and the second of those is the one the whole open-core transparency
/// argument rests on not doing.
///
/// Persisted per **installation** under `telemetry.consent` (see
/// `TelemetryConsentStore`), deliberately outside any product's settings
/// document: consent is a property of this copy of the app on this machine,
/// not a user preference to be carried between machines with a settings file.
///
/// Pure Dart — no Flutter imports.
enum TelemetryConsentState {
  /// The disclosure has not been answered yet — never shown, or shown and left
  /// without an answer. Telemetry is inactive, and any launch whose build
  /// offers the disclosure shows it again.
  unset,

  /// The user (or an Enterprise policy file) allowed collection.
  enabled,

  /// The user (or an Enterprise policy file) declined collection.
  disabled;

  /// Parses a persisted [name], returning `null` for anything this build does
  /// not recognise.
  ///
  /// A `null` return is treated as [unset] by the store, which is the safe
  /// direction: an unreadable value can never be mistaken for consent.
  static TelemetryConsentState? tryParse(String? name) {
    if (name == null) return null;
    for (final value in TelemetryConsentState.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
