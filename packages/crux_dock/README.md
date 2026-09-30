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
