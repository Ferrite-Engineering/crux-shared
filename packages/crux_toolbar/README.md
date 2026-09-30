# crux_toolbar

The single application toolbar shared by every EDACrux product.

Before this package each of the four products hand-rolled its own strip. They
had drifted into three bar heights, two divider footprints, two background
roles, two border edges (one on the wrong edge entirely), and one product that
specified no height at all — so its toolbar changed size between the open-core
and Pro builds. Three of the four had no overflow affordance, so on a narrow
window the trailing buttons — including Settings, last in all three — simply
disappeared with nothing to indicate they existed.

## The shape

```
[ common ] │ [ app-specific ]                                    … ⋮
```

A left-hand block of the buttons that mean the same thing in all four
products, a divider, then that product's own. A user moving between the apps
finds Open, Save, Close, Search, Cross-Probe and Settings in the same place
every time.

## Usage

```dart
CruxToolbar<MyAction>(
  common: [
    CruxToolbarButtonItem(
      action: MyAction.openProject,
      icon: Icons.folder_open_outlined,
      tooltip: l10n.actionOpenProject,
    ),
    const CruxToolbarSeparatorItem(),
    CruxToolbarButtonItem(
      action: MyAction.openSearch,
      icon: Icons.search,
      tooltip: l10n.actionOpenSearch,
    ),
    CruxToolbarButtonItem(
      action: MyAction.crossProbe,
      icon: Icons.sensors_outlined,
      selectedIcon: Icons.sensors,
      isSelected: panelVisible,
      badgeCount: peerCount,          // answers "is anyone connected?"
      tooltip: l10n.toolbarToggleCrossProbe,
    ),
  ],
  specific: [ /* … */ ],
  isEnabled: (a) => isActionEnabled(a, ctx),   // the descriptor table
  onAction: dispatch,
  shortcutOf: (a) => bindings[a],              // for the live tooltip
  semanticsLabel: l10n.accessibilityToolbarRegion,
  metrics: isTouch ? CruxToolbarMetrics.touch : CruxToolbarMetrics.desktop,
  overflow: MyOverflowMenu(onAction: dispatch),
);
```

## What the package owns

- **Geometry** — `CruxToolbarMetrics`: 40 dp bar / 36 dp hit box / 18 dp glyph
  on desktop, 48 / 48 / 24 on touch. One density decision for the suite.
- **Overflow** — the strip scrolls horizontally, an overflow button stays
  pinned to the trailing edge, and a fade marks the cut. The slot is *always
  reserved* when `overflow` is supplied and only painted once the strip
  actually scrolls: showing and hiding the slot itself would change the
  available width, which changes whether the strip overflows, which changes
  the slot — an oscillation. A reserved slot costs one button of empty space
  at the far right of a left-packed row, which is invisible, and is stable.
- **Enablement** — every button's state comes from `isEnabled`, wired to the
  product's descriptor table, so the toolbar cannot drift from the menu bar
  and command palette.
- **Live tooltips** — `cruxToolbarTooltip` appends the user's *current*
  binding. Writing the accelerator into the label instead, as `"Zoom In (W)"`
  did in five ARB keys across five locales, makes the tooltip a lie the moment
  the user rebinds the action — which the keymap editor lets them do.
- **Keys** — every button carries `ValueKey(action)`, so conformance tests
  find it by action rather than by glyph.
- **The "on" tint** — a toggled-on button's glyph takes the active theme's
  `toolbar.iconActive` chrome token (`crux_theme`'s `CruxChromeColors`), and
  `primary` when the theme leaves it unset.
- **Accessibility** — the strip is one labelled `Semantics` region.

## Affordances

**`CruxToolbarSplitButton`** — a Photoshop-style grouped tool button. Tapping
fires the faced variant; long-press, right-click, or the corner triangle opens
the siblings, and the chosen one becomes the new face. This is what lets a
cluster of related commands (four export formats, fan-in/fan-out/clear) earn
one toolbar slot instead of none.

> The face opts out of the tap-triggered tooltip. `Tooltip` registers its own
> long-press recognizer, which sits deeper in the tree and wins the gesture
> arena, so it would otherwise swallow the menu gesture. Hover still shows the
> tooltip on desktop; long-press opens the menu on touch.

**`CruxRunStopButton`** — one control that morphs between Run and Cancel, with
a progress ring while running. Two products rendered Run and Cancel as two
permanently-live buttons side by side, so the toolbar never told the user
whether a run was in flight.

**Badges** — `badgeCount` on any button. The cross-probe button in particular
gave no indication whether any peer was connected; three products' descriptor
comments explicitly wrestle with "keep it enabled at zero peers so users can
find out why nothing is connected". A badge answers that without opening the
panel.
