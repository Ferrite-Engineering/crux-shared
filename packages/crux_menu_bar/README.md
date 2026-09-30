# crux_menu_bar

The single desktop menu bar shared by every EDACrux product.

Before this package each of the four products carried its own copy of
`DesktopMenuBar`. The copies drifted: only one had separators, only one had a
declarative item order, two had no enable/disable state at all, and Settings
ended up in a different menu depending on which app you opened. This package
owns everything that should be identical, and leaves each product only what is
genuinely its own.

## What the product supplies

```dart
DesktopMenuBar(onAction: dispatch, child: body);
// →
CruxDesktopMenuBar<MyAction>(
  layout: kMenuLayout,                       // order + grouping
  appActions: const CruxAppMenuActions(
    about: MyAction.openAbout,
    checkForUpdates: MyAction.checkForUpdates,
    settings: MyAction.openSettings,
    quit: MyAction.quit,
  ),
  categoryLabel: (c) => c.label(l10n),
  categoryAcceleratorLabel: (c) => c.acceleratorLabel(l10n),
  windowMenuLabel: l10n.menuWindow,
  labelOf: (a) => a.label(l10n) + tierLabelSuffix(a.requiredTier, l10n),
  shortcutOf: (a) => bindings[a],
  isVisible: (a) => isActionVisibleIn(a, ActionSurface.menu, ctx),
  isEnabled: (a) => isActionEnabled(a, ctx),
  onAction: onAction,
  logo: const MyIconImage(size: 18),
  child: child,
);
```

## What the package owns

- **Order and grouping** — `CruxMenuLayout` maps each `ActionCategory` to a
  list of groups; a separator is drawn between consecutive non-empty groups.
  Empty groups collapse with no dangling separator; an all-empty category
  renders no menu.
- **Platform placement** — macOS gets
  `About | Check for Updates | Settings | Services/Hide/… | Quit` in the system
  application menu plus a standard **Window** menu before Help. Windows/Linux
  fold Settings and Quit into the bottom of File and keep About and Check for
  Updates in Help.
- **The native key-equivalent guard** — `nativeMenuShortcut` refuses to publish
  an unmodified accelerator to the macOS menu unless it is a function key,
  because `NSMenuItem` key equivalents are matched ahead of the focused text
  field. `displayMenuShortcut` keeps showing them on Windows/Linux, where the
  accelerator label binds nothing.
- **The window chrome** — on Windows/Linux the frameless title bar and its
  caption buttons are drawn here. Hosts must not gate the widget on window
  size; doing so removes the user's only way to close the window.

## Drift guard

`cruxMenuLayoutActions(layout)` returns every action the layout names. Each
product asserts that this set, unioned with `appActions.desktopFolded`, equals
exactly the set its descriptor table marks menu-visible — so a newly
menu-visible action fails the test until it is given a home in the layout.
