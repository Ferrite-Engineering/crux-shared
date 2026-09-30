// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Shared cross-probe **UI** for the EDACrux suite.
///
/// `crux_cxp` is pure Dart and holds the protocol; a Flutter widget cannot live
/// there. This companion package holds the Flutter half of cross-probing: the
/// one docked cross-probe side-panel all four products
/// adopt, richer than any current app's, plus the app-agnostic controller
/// contract the widget renders against.
///
/// Exports:
///
/// - `CrossProbePanel` — the docked side-panel widget (Connected Peers with
///   per-peer direct send, Unreachable peers warnings, Recent Events including
///   selection-received and open-artifact, header close chevron).
/// - `CrossProbePanelController` — the interface each app implements to bind
///   the panel to its live CXP state and commands. **The adoption contract.**
/// - `CrossProbePanelStrings` — the (English-default) localization seam.
/// - `CrossProbeEvent` / `CrossProbeEventKind` / `CrossProbeEventDirection` —
///   the app-agnostic event-log value types.
/// - `DemoCrossProbePanelController` — an in-package fake/demo controller so
///   the widget builds, demos, and tests in isolation.
///
/// The widget depends on **only** this package's types and `crux_cxp` value
/// types — never on any single app — so all four products render identical
/// cross-probe chrome.
library;

export 'src/cross_probe_event.dart';
export 'src/cross_probe_panel.dart';
export 'src/cross_probe_panel_controller.dart';
export 'src/cxp_settings_controls.dart';
export 'src/demo_cross_probe_panel_controller.dart';
