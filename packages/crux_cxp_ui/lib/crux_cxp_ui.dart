// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Shared cross-probe **UI and lifecycle** for the EDACrux suite.
///
/// `crux_cxp` is pure Dart and holds the protocol; a Flutter widget or a
/// Riverpod provider cannot live there. This companion package holds
/// everything between the protocol and a product:
///
/// - **The lifecycle** (`cruxCxpRuntimeProvider` and its siblings): settings
///   saved under each product's existing keys and loaded before `runApp`,
///   the server started, stopped and restarted from them under one port
///   rule, discovery, the peer list (empty whenever the server is off),
///   unreachable peers, the event log, and acknowledged replies to what peers
///   send. A product supplies a `CruxCxpProductBinding` (who it is) and a
///   `CruxCxpRequestHandler` (what it does when asked).
/// - **Sending**: the target list (`crossProbeTargetsProvider`, one entry per
///   product in suite order, windows as sub-items), the element-kind table
///   (`crossProbeElementFor`), the one dispatcher (`CrossProbeDispatcher`,
///   always an acknowledged `request_highlight` with one timeout and one
///   outcome vocabulary) and its optional gate, and the three surfaces built
///   on them: the "Cross-probe to" submenu (`crossProbeMenuEntry`), the
///   Cross-probe Selection command (`runCrossProbeSelection`) and the
///   one-click `CrossProbeToButton`.
/// - **The panel**: `CrossProbePanel` and its controller contract, and
///   `CruxCrossProbePanel`, the panel already bound to the lifecycle; the
///   settings controls and `CruxCxpSettingsSection`, bound likewise.
/// - **The words**: `CruxCxpStrings`, every string above in the suite's
///   locales, so no product keeps its own copy.
///
/// Everything depends only on this package, `crux_cxp` and the shared
/// layout components, never on a single product.
library;

export 'src/cross_probe_event.dart';
export 'src/cross_probe_panel.dart';
export 'src/cross_probe_panel_controller.dart';
export 'src/cxp_settings_controls.dart';
export 'src/cxp_strings.dart';
export 'src/demo_cross_probe_panel_controller.dart'
    hide DemoCrossProbePanelController;
export 'src/runtime/cxp_bound_widgets.dart';
export 'src/runtime/cxp_product_binding.dart' hide kCxpAcceptsCapabilityPrefix;
export 'src/runtime/cxp_providers.dart'
    hide
        cruxCxpPeersStreamProvider,
        cruxCxpSettingsServiceProvider,
        kCruxCxpEventLogCapacity;
export 'src/runtime/cxp_runtime.dart' hide kCruxCxpAckTimeout;
export 'src/runtime/cxp_settings.dart';
export 'src/send/cross_probe_dispatcher.dart';
export 'src/send/cross_probe_surfaces.dart';
export 'src/send/cross_probe_targets.dart'
    hide
        crossProbeTargetsFor,
        kCrossProbeFallbackKinds,
        kCrossProbeSuiteOrder,
        kCrossProbeTargetKinds;
