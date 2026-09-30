# crux_ide_layout

The cross-suite **dockable IDE-layout shell** for the EDACrux suite. One
`CruxIdeLayout` widget renders the four-region (`left | center | right` over
`center / bottom`) `panes` `IdeLayout` for all four Crux
products.

Before this package each app hand-wrote a near-identical `*IdeLayout` wrapper:
build an `IdeController` from its `PanelLayoutState`, `ref.listen` the provider
to re-apply vis.ibility, feed `onPaneStateChanged` / `onSizeChanged` back into
the notifier, and wrap it all in a `PaneTheme`. This package lifts that
boilerplate into one implementation; each app keeps only a thin adapter from
its own `PanelLayoutState` to two small interfaces.

## How it works

`CruxIdeLayout` is **provider-agnostic**. The host watches its own panel state
and supplies:

- an [`IdePanelLayout`](lib/src/ide_panel_layout.dart) — read side: `leftVisible`
  / `leftSize` (and right/bottom), with sizes as `PaneSize?` so the app picks
  pixel vs. fraction units;
- an [`IdePanelLayoutSink`](lib/src/ide_panel_layout.dart) — write side: where
  drag-to-collapse / drag-to-resize gestures are persisted;
- the four region builders, optional per-region min sizes, an optional
  `centerMinSize`, and an optional `CruxIdeLayoutTheme`.

The resizers follow the active theme's `splitter` (at rest) and
`splitter.hover` (hovered, dragged or focused) chrome tokens, read from
`crux_theme`'s `CruxChromeColors`, and otherwise `outlineVariant` and
`primary`. A colour passed in `CruxIdeLayoutTheme` outranks the theme, so
leave those null unless the product means to opt out of the user's choice.

On each rebuild the widget diffs the new visibility against what it last applied
and pushes only the deltas onto the controller, so a View-menu toggle, a
drag-to-collapse, and a device-class force-hide all converge through one path.

```dart
class _MyIdeLayout extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    return CruxIdeLayout(
      layout: _MyLayoutAdapter(state),     // implements IdePanelLayout
      sink: _MyLayoutSink(notifier),       // implements IdePanelLayoutSink
      leftBuilder: (ctx, _) => const HierarchyPane(),
      centerBuilder: (ctx, _) => const Canvas(),
      rightBuilder: (ctx, _) => const InspectorPane(),
      bottomBuilder: (ctx, _) => const DiagnosticsPane(),
    );
  }
}
```

## Per-app variation it absorbs

- **Pixels vs. fractions** — the adapter returns `PaneSize?`; consumers may
  return `PaneSize.pixel(...)` or `PaneSize.fraction(...)`.
- **Per-region min sizes** — passed as optional `leftMinSize` / `rightMinSize` /
  `bottomMinSize`.
- **Center floor** — `centerMinSize` re-declares the center pane with a minimum
  (WaveCrux pins 120dp).
- **Global vs. per-tab state** — the host decides what `panelLayoutProvider`
  scope the adapter reads; WaveCrux mounts one `CruxIdeLayout` per tab.
- **Device-class force-hide** — WaveCrux's adapter returns
  `preference && !isPhone`, keeping that policy in the app, not the shared
  widget.
- **No drag-resize persistence** — an app can leave the sink's
  size setters as no-ops.

## Dependencies

`flutter`, `panes`. No Riverpod dependency — the host drives rebuilds.
