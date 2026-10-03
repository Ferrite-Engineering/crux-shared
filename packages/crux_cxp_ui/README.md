# crux_cxp_ui

Shared CXP cross-probe **UI** for the EDACrux suite — the Flutter companion to
the pure-Dart [`crux_cxp`](../crux_cxp) protocol package.

`crux_cxp` is pure Dart, so a Flutter widget cannot live there. This package
holds the Flutter half of cross-probing: **one** docked
cross-probe side-panel that all four Crux products adopt (WaveCrux, NetCrux,
LintCrux, SimCrux), richer than any current app's, plus the app-agnostic
controller contract the widget renders against.

## What it provides

- **`CrossProbePanel`** — a docked side-panel (not a modal dialog) with:
  - a **header** with the panel title and a **close chevron** (collapse
    affordance mirroring the suite's other docked panels),
  - a **Connected Peers** list, each row carrying a per-peer **direct send**
    button (the panel-side entry point for sending a selection to one peer),
  - a persistent **Unreachable peers** warning surface (one-way connectivity
    the healthy-looking peer list would otherwise hide),
  - a **Recent Events** log with a **Clear events** action, rendering every
    event kind including **selection received** and
    **open-artifact**,
  - an **offline banner** when the local CXP server is not running.
  - It is theme-aware: every colour comes from the ambient `ColorScheme`, so it
    renders correctly in both light and dark themes.

- **`CrossProbePanelController`** — the interface each app implements. **This is
  the adoption contract** (see below).

- **`CrossProbePanelStrings`** — an English-default localization seam.

- **`CrossProbeEvent` / `CrossProbeEventKind` / `CrossProbeEventDirection`** —
  the app-agnostic event-log value types (pure Dart, no Flutter).

- **`DemoCrossProbePanelController`** — an in-package fake/demo controller so the
  widget builds, demos (`.populated()`), and tests in isolation.

## The adoption contract

The panel depends on **only** `CrossProbePanelController` and `crux_cxp` value
types — never on any single app's CXP server/client, Riverpod providers, or
localization. Each app writes one adapter:

```dart
abstract interface class CrossProbePanelController {
  // Reactive state — the panel wraps each in a ValueListenableBuilder.
  ValueListenable<List<PeerIdentity>>   get peers;        // connected peers
  ValueListenable<List<CrossProbeEvent>> get events;      // recent events
  ValueListenable<List<CxpDialFailure>>  get unreachable; // one-way peers
  ValueListenable<bool>                  get serverRunning;// offline banner

  // Commands the panel fires (side-effecting, fire-and-forget).
  void onSendTo(PeerIdentity peer); // direct send to a peer
  void onOpenPanel();               // reveal panel (wired to the toolbar toggle)
  void onClose();                   // header close chevron pressed
  void onClearEvents();             // "Clear events" pressed
}
```

Apps typically back the `ValueListenable`s with a `ValueNotifier` bridged from
their reactive store (a Riverpod `ref.listen`, a `ChangeNotifier`, or a stream
`.listen`), and route the commands into their own selection + `NameResolver`.

```dart
CrossProbePanel(controller: myAppController)
```

### Labelling the send button with a tier badge

Originating a cross-probe is a priced capability in some products, and the
suite labels every gated control before it is pressed. The panel knows no
tiers, so it takes an optional `sendBadgeBuilder`
(`CrossProbeSendBadgeBuilder`: `(BuildContext, PeerIdentity) -> Widget?`) and
renders what it returns on the leading side of each row's send button:

```dart
CrossProbePanel(
  controller: myAppController,
  sendBadgeBuilder: (context, peer) =>
      const FeatureTierBadge(requiredTier: LicenseTier.pro),
)
```

Leave it out (or return null for a row) and the button renders alone, so a
product with no licence model keeps a fully usable panel. The badge labels the
button and does not gate it: the decision, and the explanation of a denial,
stay in the product's `onSendTo`. The badge widget is the product's choice;
`crux_cxp_ui` deliberately takes no `crux_license` dependency.

## Status

The four apps adopt it by: implementing a
`CrossProbePanelController`, swapping their bespoke cross-probe panel for
`CrossProbePanel`, and adding a toolbar toggle button that calls `onOpenPanel`.
WaveCrux's old modal `Dialog` presentation is retired in favour of this docked
panel.
