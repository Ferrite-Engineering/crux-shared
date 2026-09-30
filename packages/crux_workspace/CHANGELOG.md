## Unreleased

- `ViewerTabBar` follows the theme's `tabBar.background` (the strip),
  `tabBar.selected` (the active tab) and `tabBar.label` (every tab title)
  chrome tokens, read from `crux_theme`'s `CruxChromeColors`; the defaults
  are unchanged. Depends on `crux_theme`.

## 0.10.0

- **New: `CruxSuitePeers` — the "More from EDACrux" section, and
  `CruxSuiteProduct`.** `CruxSuiteFooter` says a suite exists; this says what
  is in it, in the only terms that move anyone: what each other tool does for
  the user of *this* one. A user who has never heard of the other three has no
  reason to care that they are "a suite", and every reason to care that
  something can lint the RTL whose waveform they are staring at. Rows are
  rendered here; the words are not — what NetCrux does for a WaveCrux user is
  not what it does for a SimCrux user, so each product supplies its own three
  localized blurbs and one `onOpenPeer` callback. As with the footer, the
  package holds no URL and no `url_launcher`.
- `EmptyCanvasState.peers` is the slot it hangs from, below
  `primaryActions` and above `footer`. A slot of its own rather than
  something each host stacks into `footer`: the gap above the block, and the
  tighter gap between it and the line beneath — which restates in one quiet
  sentence what the rows just said at length, so it reads as their footnote
  rather than a fifth section — are then decided once here instead of four
  times.
- Each peer row is one focusable `isLink` node rather than a tappable
  paragraph, so a keyboard or screen-reader user can follow it.
- `CruxSuiteProduct` is deliberately not `crux_license`'s `CruxProduct`: a
  welcome screen needs a brand colour and a landing-path slug, not an
  entitlement code, and `crux_workspace` must not take a licensing dependency
  to get a display name. `crux_license` is a **dev** dependency so one test can
  hold the two enumerations to the same four products in the same order.

## 0.9.0

- **New: `CruxSuiteFooter`, and an `EmptyCanvasState.footer` slot to hang it
  from.** Four products ship four separately-installable applications, and a
  user who arrived at one of them had nothing on screen saying the other three
  exist. The footer is the one implementation of that line, so its wording,
  type scale and link affordance cannot drift four ways. The whole row — not
  just the underlined domain — is the tap target and one focusable `isLink`
  semantics node: a tappable `TextSpan` inside a paragraph takes no keyboard
  focus and has no node of its own, so a keyboard or screen-reader user could
  read such a line but never follow it. The package takes a localized label
  and an `onTap` and holds no URL and no `url_launcher`: the destination is
  per-product, and the package is depended on by hosts with no plugin
  registrant.
- `EmptyCanvasState.footer` renders last, below `primaryActions`, and is
  ignored when `children` is supplied (that caller composes its own body).
  Initial focus still goes to the first primary action, so a screen reader
  does not open the window by announcing an advertisement.

## 0.8.0

- `EmptyCanvasState` is a named region (`semanticLabel`, defaulting to
  `title`) with the title as a heading, and focuses its first primary action
  when nothing else holds focus (`claimInitialFocus`, default true). Before,
  nothing claimed focus at launch, so a desktop screen reader read only the
  window's class name. The card is no longer a semantics container, and the
  version line is full-strength `onSurfaceVariant` (the 70% tint measured
  3.88:1 at 11 px).
- `ViewerTabBar` tab chips are one node each: a button named after the tab,
  with its selected state and the tab's path as the description. They were
  announced as an unnamed-role "grouping" with the path as a competing name.


## 0.7.0

- **New: `WorkspaceNotifier.mutate` — the protected, scope-preserving mutation
  primitive for product subclasses.** Previously the only mutation entry point
  a subclass could reach was `replaceWith`, which is a *wholesale document
  replacement*: it evicts **every** per-tab and per-pane `ProviderContainer`
  before installing the next document. Products routed incremental edits (a
  new tab, a pane split, a window-geometry `extras` write) through it because
  nothing else was public, and that tore down the containers of tabs still on
  screen. The host's per-tab `UncontrolledProviderScope` then rebuilt with a
  fresh container under a widget subtree whose keys had kept the old elements
  alive, and any nested `ProviderScope` inside threw `ProviderScope was
  rebuilt with a different ProviderScope ancestor` (WaveCrux hit this on every
  window resize, because window geometry is persisted into the workspace
  document). `mutate` installs the new state, reconciles scopes against it
  (evicting only ids the new document dropped), and schedules the debounced
  save. `replaceWith` keeps its unconditional-eviction semantics for genuine
  document replacement (workspace open, reset) and now documents the
  distinction.

## 0.6.0

- **Fix: opening a project the user already has open now focuses that tab
  instead of stacking a duplicate.** `WorkspaceNotifier.openTab` gained a
  `dedupe` flag (default on) that consults the new
  `WorkspaceCodec.identityOf(payload)` seam, plus a `tabWithSameIdentityAs`
  query. Every command-line open path in the suite called `openTab`
  unconditionally, so relaunching with the same positional argument added one
  tab per launch, without bound. `identityOf` defaults to `null` — dedupe is
  inert until a product's codec opts in, so this cannot change behaviour
  behind a product that has not.
- Identity for a path-shaped payload is `canonicalPathKey` from
  `package:crux_io`, not the raw string: a raw string does not survive a
  relative launch argument, a `..` segment, a trailing separator, a symlink
  (`/tmp` -> `/private/tmp` on macOS), or a case-insensitive volume, and each
  of those failures presents as a duplicate tab.
- **Fix: a launch-time restore gate.** `WorkspaceNotifier.shouldRestoreOnLaunch`
  (default `true`) is awaited *before* `WorkspaceService.load`, so a product
  with a "restore tabs on launch" preference can decline the rehydration
  rather than load and then close what it just loaded. Declining leaves the
  document on disk untouched, so flipping the preference back on restores the
  session.
- No breaking change: both additions are opt-in and the default behaviour of
  an un-migrated product is unchanged.

## 0.5.0

- Fix: `WorkspaceNotifier.closeTab` now picks the new active tab by the removed
  tab's **pane-local** position, not its position in the flat tab list. In
  split-pane mode the two diverge, so the previous global index selected the
  wrong sibling (or the pane's last tab) as the new active tab.
- Change: `WorkspaceService.loadFromPath` (and `WorkspaceNotifier.loadFrom`)
  now throw a typed `WorkspaceLoadException` on a missing, malformed, or
  unsupported-version named document instead of returning `Workspace.empty()`.
  Returning empty let the notifier evict the live session's scopes and
  auto-save the empty document over the managed `workspace.json` — silent
  destruction of a good session. The user-chosen file is never moved aside.
- `WorkspaceService` corruption recovery for the auto-managed document:
  an unreadable `workspace.json` is quarantined to
  `workspace.json.corrupt-<timestamp>` and reported via `takeRecovery()`
  (`WorkspaceRecovery`) so the host can surface a launch-time notice, rather
  than being silently overwritten on the next save.
- `PaneBorderBuilder` receives `isSplit`, and `WorkspaceService` gained
  `clearAllSidecars()` for hermetic test boots.

## 0.4.2

- Fix: Flutter Web no longer hangs on file open. `_resolveDirectory` now
  short-circuits to `null` on web (path_provider has no web implementation),
  and `_log` swallows any error from its `stderr` fallback so a logging
  failure can never escape — previously web's `dart:io` stub threw
  `UnsupportedError` from `stderr`, an `Error` (not an `Exception`) that
  slipped past the `on Exception` recovery and rejected `load()`/`save()`,
  leaving the host's workspace provider in an error state.

## 0.4.1

- Fix: `WorkspaceNotifier.moveTabToPane` now prunes the source pane when the
  move empties it (and it is not the sole pane), mirroring `closeTab`'s
  empty-pane collapse. Previously, dragging the last tab out of a pane left a
  phantom empty pane behind. When the source pane survives but the moved tab
  was its active tab, the first surviving sibling becomes the active tab.

## 0.2.0

- `WorkspaceNotifier<P>` — generic `AsyncNotifier` base every Crux product
  extends to drive workspace mutations (openTab / closeTab / reorderTab /
  moveTabToPane, setActiveTab / setActivePane / focusOtherPane / splitPaneRight
  / closePane, updateTabPayload / updateTabDisplayName, resetWorkspace /
  replaceWith, saveAs / loadFrom). Tracks in-flight saves so `flushPendingSave`
  reliably observes the post-save filesystem state.
- `WorkspaceLifecycleObserver<P>` — opt-in widget that flushes the workspace
  on `AppLifecycleState.paused` / `detached` via a `WidgetsBindingObserver`.
- `EmptyCanvasState` — centered "nothing is open" content-slot widget rendered
  by `PaneHost` when the workspace has zero tabs. Caller supplies the title,
  optional subtitle, recent-files / recent-workspaces sections, and primary-
  action row.
- `ViewerTabBar<P>` — horizontal tab bar filtered by `paneId`. Chips, drag
  handle (LongPressDraggable for in-bar reorder and cross-pane move), close
  button, right-click / long-press context menu (Close Tab / Close Other Tabs
  / Close Tabs to the Right / Move to New Window, plus product-supplied
  extras via `contextMenuItems`), and an optional trailing "+" new-tab button
  that hides when no `defaultPayloadBuilder` is supplied.
- `ViewerTabBarStrings` — interface for localized chip and menu strings, with
  `ViewerTabBarStringsEn` as the English default. Products subclass to wire
  their own ARB-generated localizations; in-package ARB localization is a
  deferred follow-on.
- `PaneHost<P>` — root layout widget that hosts one or two panes side-by-side
  per `workspace.panes.length`, with active-pane indicator and tap-anywhere-
  to-focus dispatch. Renders `emptyCanvasContent` when the workspace has zero
  tabs. `enableSplitPane: false` suppresses the second pane (host products
  use this to gate split-pane on device class).
- Multi-window hooks: the `Move to New Window` menu item is included in
  ViewerTabBar's context menu but renders disabled while
  `kMultiWindowAvailable` is `false`.

## 0.1.0

- Initial release. Foundation extraction from WaveCrux open-core.
- `TabId`, `PaneId` value types.
- Generic `Workspace<P>`, `WorkspaceTab<P>`, `WorkspacePane` domain types.
- `WorkspaceCodec<P>` per-product per-tab payload codec interface.
- `WorkspaceService<P>` atomic-write workspace.json persistence with sidecar support.
- `tabIdProvider`, `paneIdProvider` per-container sentinel leaf providers.
- `TabContainerManager`, `PaneContainerManager` per-tab and per-pane `ProviderContainer` lifecycle managers.
- Multi-window placeholders: `kMultiWindowAvailable`, `TabDetachingDelegate`, `PanelPopOutDelegate`, Noop implementations, providers.
