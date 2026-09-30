// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// An Enterprise administrator's org-wide telemetry decision, as it reaches
/// this package.
///
/// An Enterprise IT admin has a key in the signed
/// `.crux-policy.json` — `telemetry: allow | deny` — and says that when it is
/// present the first-launch dialog is suppressed and the policy decides.
/// Individual engineers do not see a telemetry prompt.
///
/// **This package never reads that file.** It does not know the policy format,
/// where the file lives, or how its signature is validated; `crux_policy` owns
/// all of that, and an *unsigned* policy file must not be self-granting. What
/// lives here is only the shape of the answer and the behaviour it selects, so
/// that binding the loader is one `telemetryPolicyProvider` override against a
/// gate that is already implemented and already tested.
///
/// Pure Dart — no Flutter imports.
enum TelemetryPolicy {
  /// The org mandates collection. Transmit (subject to the beta gate), and
  /// mount no consent surface.
  ///
  /// Overrides a stored `disabled`: the individual's earlier answer was to a
  /// question the org has since taken off the table.
  allow,

  /// The org forbids collection. Never transmit, and mount no consent surface.
  ///
  /// Overrides a stored `enabled` for the same reason [allow] overrides a
  /// stored `disabled` — with the failure direction that matters, since the
  /// consequence of getting this one wrong is transmitting from a machine whose
  /// owner has forbidden it.
  deny,

  /// No policy file governs this installation.
  ///
  /// The state of **every** non-Enterprise installation, and of any Enterprise
  /// one whose admin did not set the key — so it is the default everywhere, and
  /// it must mean "behave exactly as if this seam did not exist": the
  /// individual's consent decides, and both consent surfaces are offered.
  absent,
}
