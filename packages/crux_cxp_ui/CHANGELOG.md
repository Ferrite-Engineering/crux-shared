# Changelog

## Unreleased

- **The shared CXP lifecycle.** `cruxCxpRuntimeProvider` runs one product's CXP
  presence (`CruxCxpRuntime`: server, manifest, discovery, connector) from
  `cruxCxpSettingsProvider`, which saves `CruxCxpSettings` under the keys every
  product already uses (`CruxCxpSettingsCodec`, `<prefix>cxpServerEnabled` and
  its three siblings) and is seeded before `runApp` through
  `cruxCxpLaunchSettingsProvider` / `loadCruxCxpLaunchSettings`. A launch with CXP off
  never starts the server or writes a manifest. One port rule: a valid new
  port restarts a running server on it at once. `cruxCxpPeersProvider` (empty
  whenever the server is off), `cruxCxpConnectedPeerCountProvider`,
  `cruxCxpUnreachablePeersProvider` (cleared on every stop and restart),
  `cruxCxpEventLogProvider`, `cruxCxpServerStatusProvider` and
  `broadcastCruxCxpSelection`. A product supplies `cruxCxpProductBindingProvider`
  (`CruxCxpProductBinding`: name, default port, key prefix, capabilities, the
  element kinds it accepts, containment, name resolver) and
  `cruxCxpRequestHandlerProvider` (`CruxCxpRequestHandler`; the runtime sends every
  acknowledgement), plus optional version, attention and peer-filter
  providers.
- **Sending a cross-probe, one way.** `crossProbeTargetsProvider` /
  `crossProbeTargetsFor` (one `CrossProbeTarget` per product in suite order,
  several windows as instances), `CrossProbeSelection`, the element-kind
  table `kCrossProbeTargetKinds` / `crossProbeElementFor` (narrowed by a
  peer's `cxp.accepts:<kind>` capabilities), `CrossProbeDispatcher` (always
  an acknowledged `request_highlight`, `kCruxCxpAckTimeout`, one
  `CrossProbeOutcome` vocabulary), the optional `CrossProbeGate`, and the
  surfaces on them: `crossProbeMenuEntry` (the "Cross-probe to" submenu),
  `runCrossProbeSelection` (the Cross-probe Selection command: one target
  sends, several open a menu, never a dialog), `CrossProbeToButton`,
  `sendCrossProbe` and `reportCrossProbeOutcome`.
- **Bound widgets.** `CruxCrossProbePanel` (the panel on the lifecycle and
  the shared send) and `CruxCxpSettingsSection` (the settings controls on
  `cruxCxpSettingsProvider`, with a status line).
- **`CruxCxpStrings`**: every string above in English, Simplified Chinese,
  Japanese and Korean, so no product keeps its own copy;
  `cruxCxpStringsCustomizerProvider` for a product's own line.
- `CrossProbePanelStrings` gains the event-log labels (English defaults);
  the panel no longer hard-codes them.
- New dependencies: `crux_settings`, `flutter_riverpod`, `shared_preferences`.

- **`CruxCxpSettingsControls` is built on `CruxFormRow`.** The three switches
  are `CruxFormRow.toggle` rows (a `CruxSwitch` on desktop, keys unchanged)
  and the port is a label-left row. The send-failure message is
  `showCruxErrorSnack` under the same `cross_probe_send_failure` key. New
  dependencies on `crux_ide_layout` and `crux_settings_ui`.

- `CrossProbePanel.sendBadgeBuilder` (`CrossProbeSendBadgeBuilder`): an
  optional per-row badge rendered on the leading side of each peer's
  direct-send button, so a product that prices cross-probe origination can
  show its tier badge before the click. Null by default, and a builder may
  return null for a row; either leaves the button alone. The badge labels the
  button; gating stays in the product's `onSendTo`. The badge's key is
  `cross_probe_send_badge_<peerId>`.

## 0.1.0

- Initial release — the shared cross-probe side-panel.
- `CrossProbePanel` — the one shared **docked** cross-probe side-panel all four
  products adopt, leveled up to WaveCrux's richness and beyond: Connected Peers
  with a per-peer direct-send control, a persistent
  Unreachable-peers warning surface, a Recent Events log (with "Clear events")
  that renders every event kind — including the additions **selection received**
  and **open-artifact** the divergent per-app logs were missing — a
  header with a **close chevron**, and an offline banner. Theme-aware
  (light/dark) via the ambient `ColorScheme`.
- `CrossProbePanelController` — the app-agnostic contract the widget renders
  against (reactive `peers` / `events` / `unreachable` / `serverRunning`
  `ValueListenable`s; `onSendTo` / `onOpenPanel` / `onClose` / `onClearEvents`
  commands). The single seam each app implements to adopt the panel; the widget
  depends on nothing but this and `crux_cxp` value types.
- `CrossProbePanelStrings` — an English-default localization seam.
- `CrossProbeEvent` / `CrossProbeEventKind` / `CrossProbeEventDirection` — the
  app-agnostic, pure-Dart event-log value types.
- `DemoCrossProbePanelController` — an in-package fake/demo controller (with a
  `.populated()` snapshot) so the widget builds, demos, and tests in isolation.
