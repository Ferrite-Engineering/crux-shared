// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Build-time flag gating the **Experimental AI Waveform Assistant** across the
/// EDACrux suite.
///
/// The AI assistant ships labeled *Experimental* for the duration of the public
/// beta as a deliberate exit ramp: AI behavior is the least predictable surface
/// in the product, it depends on third-party endpoints the suite does not
/// control, and each product's open-core repo flips to a public OSS license
/// post-beta. Gating the whole feature behind this build flag means a shipping
/// build can omit AI entirely — no Settings panel, no surfaces — and the
/// feature can be held back or removed before the OSS flip *without breaking a
/// shipped promise*, because it was never presented as stable.
///
/// **Default `true`.** The feature has graduated out of "hidden behind a
/// build flag": a normal build now carries the AI surface, still *labeled*
/// Experimental and still gated behind the off-by-default user opt-in
/// (`aiExperimentalEnabledProvider`), so the Settings → AI Assistant section is
/// visible but nothing is active until the user enables it and supplies a key.
/// A build can still omit AI entirely at build time:
///
/// ```bash
/// flutter run --dart-define=AI_EXPERIMENTAL=false
/// ```
///
/// This default lives here — a single source shared across every Crux product
/// that depends on `crux_license`, not a per-repo flag — so changing the
/// suite-wide posture is one line, not a code-archaeology sweep across four
/// product repos.
///
/// This flag is only half the gate. It is combined with a persisted,
/// off-by-default **user** opt-in via `aiExperimentalEnabledProvider`; AI
/// surfaces appear only when *both* are on. The build flag governs whether the
/// feature exists in this build; the user toggle is the runtime opt-in.
///
/// Mirrors the structure of `kBetaPeriod` (feature-gating flag) and
/// `kBetaExpiry` (build shelf-life) — the three are the suite's shared
/// build-time switches, all single-sourced in `crux_license`.
const bool kAiExperimental = bool.fromEnvironment(
  'AI_EXPERIMENTAL',
  defaultValue: true,
);
