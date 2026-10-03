# Changelog

## Unreleased

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
