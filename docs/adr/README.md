# Architecture decision records

Cross-suite conventions that are worth writing down because somebody will
otherwise re-litigate them — filename shapes, persistence formats, protocol
choices, layering rules that span more than one product repo.

An ADR belongs here (rather than in a product repo) when the decision binds
**more than one** Crux product. A decision that only affects WaveCrux's
waveform renderer is a WaveCrux concern.

## Index

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-project-config-filename-convention.md) | Project config filename convention — per-project config files use a named-file pattern, never a pure dotfile name | Accepted; table superseded by 0004 | 2026-05-26 |
| [0002](0002-pro-only-consumers-of-shared-packages.md) | A package with only Pro consumers still belongs in crux-shared — tier is a property of the consumer, not of the code; a private shared Pro-tier repository is deferred until a second genuine candidate appears | Accepted | 2026-08-18 |
| [0003](0003-semantics-orphan-discipline.md) | Sliders in routes go through `CruxSlider`, a `MenuAnchor`-hosted `Tooltip` gets a semantics boundary, and every dialog carries an orphan-guard test — the desktop accessibility bridge rejects any update with an unclaimed node and freezes | Accepted | 2026-09-13 |
| [0004](0004-crux-project-manifest-is-a-named-file.md) | The suite design manifest is `<design>.crux-project`, not a bare `.crux-project` — pickers hide dotfiles; one manifest per directory, several are refused by name; the legacy name is read for one release with a deprecation warning | Accepted | 2026-09-15 |
| [0005](0005-pro-implementations-leave-crux-shared.md) | Pro implementations leave crux-shared — ADR 0002's test applied per package: the persistent project registry *is* the paid capability and moves out, the switcher chrome is a mechanism and stays; the private Pro-tier shared repository now exists, one for all tiers, consumed by the overlays as a second submodule, with the licence, team-database and collaboration lifts sequenced behind it | Accepted | 2026-09-20 |

## Writing a new one

Copy the shape of ADR 0001: **Context** (what forced the decision, with the
concrete friction that motivated it), **Decision** (stated as a rule somebody
can apply without reading the rest), **Consequences** (including what breaks and
who has to change), and optionally **Notes** for how to apply the rule to
future cases.

Conventions:

- Filename `NNNN-kebab-case-title.md`, numbered sequentially.
- Header block: `**Status:**` (Proposed / Accepted / Superseded by NNNN),
  `**Scope:**`, and `**Supersedes:**` where applicable.
- **Name the products.** These records exist to be actionable. An ADR that says
  "one pre-release product" instead of "SimCrux" cannot be used by the person
  who needs it. This repo's own product names are not a secret from anybody who
  has the repo; genuine secrets (keys, endpoints, credentials) do not belong in
  a design document in the first place.
- Never edit an accepted ADR to change the decision. Write a new one and mark
  the old one superseded — the value of the record is that it preserves what was
  believed at the time.
- Add the row to the index above in the same commit.
