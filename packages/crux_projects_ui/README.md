# crux_projects_ui

Cross-suite multi-project chrome: the project switcher dialog and the
recent-projects panel, built on `crux_projects`' registry.

Extracted from SimCrux's shipped project switcher at the moment LintCrux
became the second consumer — the same
extract-at-the-second-consumer rule that produced `crux_updates`,
`crux_issue_reporter` and `crux_secrets`.

## What's here

| Widget | Purpose |
|---|---|
| `CruxProjectSwitcherDialog` | Ctrl/Cmd+P switcher: open + recent projects, filterable, keyboard-navigable |
| `CruxRecentProjectsPanel` | Recents list with Reopen / Forget, for the empty-workspace state |

## Wiring

```dart
ProviderScope(
  overrides: [
    // Required — the widgets throw without it.
    cruxProjectsUiStringsProvider.overrideWithValue(MyProductStrings(context)),

    // Optional — renders a tier badge beside each heading.
    cruxProjectsUiBadgeBuilderProvider.overrideWithValue(
      (context) => const MyTierBadge(requiredTier: LicenseTier.pro),
    ),

    // Optional — adds the "search across projects" footer entry.
    crossProjectSearchOpenerProvider.overrideWithValue(
      (context) => MyCrossProjectSearchDialog.show(context),
    ),
  ],
  child: const MyApp(),
)
```

Per crux-shared convention this package carries **no ARB**. Copy is
translated once, in the product that owns the glossary, and arrives
through a `CruxProjectsUiStrings` adapter.

## Design decisions

**Strings are unbound by default and throw.** A silent English fallback
would ship untranslated UI to every non-English user with nobody
noticing. The error message names the provider and says to override it.

**The badge is optional and defaults to none.** The multi-project
registry is a paid feature in every product that currently has one, but
that is a product fact, not a package fact.

**No search opener means no footer.** The switcher hides the
cross-project-search entry entirely rather than rendering a dead button —
a product without the feature should not advertise it.

**Tier gating is the host's job.** These widgets render; they do not
gate. The gate belongs in the opener that decides whether to mount them,
because that is also the thing that can show an upgrade dialog instead.

**Filter changes reset the keyboard cursor.** Keeping the index across a
filter change points it at a different project than the one the user was
looking at, and Enter would open the wrong thing.
