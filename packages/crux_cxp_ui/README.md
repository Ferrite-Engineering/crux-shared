# crux_cxp_ui

Shared CXP cross-probe **UI and lifecycle** for the EDACrux suite — the
Flutter companion to the pure-Dart [`crux_cxp`](../crux_cxp) protocol package.

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

## The shared lifecycle

Between the protocol and a product sits one layer every product used to
write for itself: starting and stopping the server, discovery, the peer list,
unreachable peers and the saved settings. It is here, as root-container
Riverpod providers, and behaves the same in every product.

A product binds who it is and what it does, in its root `ProviderScope`:

```dart
const binding = CruxCxpProductBinding(
  productName: 'netcrux',          // wire name and peer-id prefix
  defaultPort: 54323,
  prefsPrefix: 'netcrux.',         // keeps the keys saved by earlier releases
  acceptedKinds: [ElementKind.net, ElementKind.port, ElementKind.instance],
);

Future<void> main() async {
  final cxp = await loadCruxCxpLaunchSettings(binding);
  runApp(ProviderScope(
    overrides: [
      cruxCxpProductBindingProvider.overrideWithValue(binding),
      cruxCxpLaunchSettingsProvider.overrideWithValue(cxp),
      cruxCxpRequestHandlerProvider.overrideWith((ref) => MyHandler(ref)),
    ],
    child: const MyApp(),
  ));
}
```

Then it reads, rather than owns:

| Provider | What it is |
|---|---|
| `cruxCxpSettingsProvider` | the four settings; each setter saves at once |
| `cruxCxpRuntimeProvider` | the running `CruxCxpRuntime`, or null when off |
| `cruxCxpPeersProvider` / `cruxCxpConnectedPeerCountProvider` | connected peers and the toolbar badge's count; empty when off |
| `cruxCxpUnreachablePeersProvider` | discovered but unreachable peers; cleared by every stop and restart |
| `cruxCxpEventLogProvider` | the panel's event log |
| `cruxCxpServerStatusProvider` | running, port, why not |

The rules, once: a launch with CXP off never starts the server or writes a
manifest; a valid new port restarts a running server on it at once and is
kept for the next start otherwise; the runtime acknowledges every request a
peer sends with the `CruxCxpHandlerResult` the product's `CruxCxpRequestHandler`
returns, and asks for attention (`cruxCxpAttentionRequesterProvider`) when one is
honoured and the setting is on.

## Sending

Every way of sending a cross-probe goes through one dispatcher and reads one
target list:

- `crossProbeMenuEntry(context, ref, selection: ...)`: the "Cross-probe to"
  submenu for any `CruxContextMenuRegion` / `CruxOverflowMenu`. One item per
  product in suite order (WaveCrux, NetCrux, LintCrux, SimCrux), a product's
  several windows as sub-items, and one disabled "(no peers running)" item
  with no peers.
- `runCrossProbeSelection(context, ref, selection: ..., anchor: ...)`: the
  Cross-probe Selection command. One target sends at once; several open the
  same list as a menu at the selection. The product binds it to
  Cmd/Ctrl+Shift+Enter and must not fire it while `cruxTextInputFocused()`.
- `CrossProbeToButton(productName: 'wavecrux', ...)`: a one-click button.
- `CruxCrossProbePanel`: the panel's per-peer send.

A product describes its selection as a `CrossProbeSelection` naming it in
every element kind it can (a violation is a rule, a scope and a source line);
`crossProbeElementFor` picks the kind the target shows, from
`kCrossProbeTargetKinds`, narrowed by the peer's `cxp.accepts:<kind>`
capabilities. Every send is an acknowledged `request_highlight` with one
timeout and ends as a `CrossProbeOutcome`, reported the same way everywhere
(`reportCrossProbeOutcome`): a failure is an error toast, a landed send is
announced. Cross-probing is free; `crossProbeGateProvider` is the seam a
pricing decision would use.

A send carries one element, so a kind a target can act on only beside other
elements (NetCrux's `timing_path` and `property`) comes after the kinds it can
act on alone in that target's row. A product running in several windows is a
submenu of them; a window that announced its open design with
`CruxCxpRuntime.setActiveDocument` reads "WaveCrux 2 (alu.vcd)". The
document is display text only.

All words come from `CruxCxpStrings` in the suite's locales.

## Status

`CrossProbePanel` and `CrossProbePanelController` remain for a host that
binds the panel itself. The four products move to the bound
`CruxCrossProbePanel` and `CruxCxpSettingsSection` and delete their own
lifecycle providers, panel controllers and cross-probe strings.
