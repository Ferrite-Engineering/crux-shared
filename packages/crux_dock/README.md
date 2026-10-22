# crux_dock

Cross-suite tabbed **dock** for the EDACrux suite.

A VSCode-style region container mounted inside a `CruxIdeLayout` region by
every product — WaveCrux, NetCrux, LintCrux, SimCrux. It replaces the per-app
"priority chain" (first-true-visibility-flag-wins) that used to decide a
region's content: every surface that can occupy the region is a
`CruxDockEntry`, the strip shows what is available, and the user picks.

- **Presence semantics.** Pinned entries (Transactions, Values, Inspector,
  Log) are always listed and carry no close affordance. On-demand entries
  (FSM, X-Trace, Activity, Diff, Cross-Probe) are host-included while their
  feature is active and carry an `×` whose `onClose` *deactivates the
  feature* — membership in the entry list *is* presence.
- **Auto-hiding strip.** A dock holding exactly one pinned entry renders a
  plain titled header instead of a one-tab tab bar; a second entry appearing
  turns the header into a strip.
- **Auto-reveal.** A newly appearing closable entry (the user just ran an
  analysis) fires `onAutoReveal` post-frame so the host can activate the tab
  and un-collapse the region. Never fired for the initial build.
- **Badges.** `badgeCount` renders a `Badge.count`, zero-suppressed.
- **Collapse / maximize / pop-out.** The action cluster hosts the region
  collapse (VSCode panel-close — the host hides the `CruxIdeLayout` region),
  an optional maximize toggle, and the multi-window pop-out affordance
  (rendered disabled until `kMultiWindowAvailable`, via `CruxDockPopOut`).

The package is provider-agnostic and carries no localizations: hosts assemble
the entry list from their own providers each build and pass localized labels
and tooltips in.

Dynamic tab groups (one dock tab per Stage panel) are a host-side loop over
the host's own collection — the dock needs no group concept.

## Inspector

`CruxInspector` is a dock tab's body that shows and edits the properties of
the current canvas selection. On the desktop, editing a canvas object's
properties is an inspector, not a modal dialog.

- **Bound to the selection.** The host passes its current selection (a small
  identity: an id or a sealed selection value) each build; null shows a
  `CruxPanelEmptyState`.
- **Scoped with the dock.** It is not a route, so it is built inside the
  provider scope the dock is mounted in (the editor tab's own container) and
  needs no container passed to it. Sections never open a route to edit a
  value.
- **Sections.** A list of `CruxInspectorSectionBuilder`s, the host's own
  first and its Pro seam after (`[...core, ...ref.watch(proSectionsProvider)]`,
  the seam defaulting to empty in open core); a builder returning null is
  skipped. `CruxInspectorSection` lays out `CruxFormRow`s and read-only
  `CruxInspectorValueRow`s in one label column, with a `trailing` slot for a
  tier badge; `CruxInspectorListSection` builds a long run of rows lazily.
- **Drafts.** A section that applies on Apply shows a `CruxInspectorApplyBar`
  and calls `CruxInspector.markDirty`. While it is dirty the inspector keeps
  the object on screen when the selection moves, says so (shown and
  announced), and follows the selection once the edits are applied or
  reverted. Enter in a single-line field applies.
- **Focus.** `CruxInspectorController.open()` (the double-click on the object,
  its "Properties" entry, its shortcut) reveals the tab and puts focus on the
  first control, or on the heading of a read-only object. Escape returns
  focus to the canvas through `onEscape`. One controller per editor tab.

## Exported on purpose

`tool/unused-exports.py` reports a symbol as *internal* when no other package and no product references it. These stay in the export namespace, for the reason given:

- **Named by an exported signature** (a host can receive or must name the type): `CruxDockPopOut` (in `CruxDock`).
- **Type of the payload a host callback receives**: `CruxDockDragData`.
- **Callback type named in an exported signature; a host passing a closure never writes it**: `CruxDockEntryBuilder`.
