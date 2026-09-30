# ADR 0005 — Pro implementations leave crux-shared, and the private Pro-tier shared repository exists

**Status:** Accepted (2026-09-20)
**Scope:** Cross-suite — where a shared package goes when it *is* the paid
capability rather than a seam over it, and the sequencing of the lifts out of
the four Pro overlays into a shared private home.
**Related:** ADR 0002, which set the test this record applies and deferred
the private repository "until a second genuine candidate appears".

## Context

ADR 0002 ruled that tier is a property of the consumer, not of the code, and
gave a three-part test for whether a package belongs here: it does not if
open-sourcing it would hand over a paid capability, or if it would need a tier
check to behave correctly; it does if it is a mechanism whose *inputs* are
what the customer pays for. It also said the drift it was worried about —
a package that is the paid capability sitting here because only Pro code
happened to call it — would not be caught by any guard, and "stays a review
question". This is that review.

Two packages predate the ADR and had never been put to its test:

- `crux_projects` shipped `JsonFileProjectRegistry` behind a second entry
  point, `crux_projects_io.dart`: the persistent multi-project registry —
  many open projects, pins that survive close-all, an MRU list of recents
  that survives a restart, atomic-write persistence to `workspace.json`.
- `crux_projects_ui` ships the project switcher dialog and the recent-projects
  panel over that registry.

Both are consumed by LintCrux Pro and SimCrux Pro and by no open-core code
(one open-core *test* in LintCrux constructed the registry to exercise its
tab-to-registry sync; it now uses a test double). LintCrux's public feature
page sells the registry in as many words: *the persistent multi-project
registry — pin, close-all-but-pinned, recents that survive a restart — and
the navigation layer over it: a project switcher*.

Applied per package, the test comes out differently for the two:

| | `JsonFileProjectRegistry` | `crux_projects_ui` |
|---|---|---|
| Open-sourcing hands over a paid capability | **Yes.** It is the sold feature, clause for clause. | No. A dialog and a list; with the open-core `NoopProjectRegistry` behind them they show one project and no recents. |
| Needs a tier check to behave | No | No — "tier gating is the host's job" is in its README. |
| Mechanism whose paid inputs stay with the overlays | No. The inputs are project paths. | **Yes.** It renders whatever the registry holds; the registry is what is paid for. |

`crux_projects_ui` is the `crux_heatmap` case exactly: the grid did not know
what it was plotting, and the dialog does not know what it is listing. The
registry is the trend-store case: the thing itself. That the two are
described in one sentence on a pricing page does not make them one unit for
this test; the test is applied to the code, and the code splits cleanly.

ADR 0002 deferred a private shared Pro-tier repository until a second genuine
candidate appeared. Four now exist, measured in the overlays:

| Candidate | Overlays | Approx. lines | Note |
|---|---|---|---|
| Licence store, service, panel strings and overrides | all four | ~1,800 | The four copies differ only in product nouns (8 to 12 diff lines per pair). Cheapest lift. |
| Shared team database (Postgres client, schema handshake, migrations, settings) | LintCrux, SimCrux | ~2,700 | `team_database_migrations.dart` has **forked** (287 vs 210 lines, 102 identical) under a byte-identical schema handshake. |
| Collaboration transport, discovery, settings and the AES-GCM session cipher | WaveCrux, NetCrux | ~900 | The cipher differs by one constant, the HKDF `info` string. A crypto fix is currently applied twice by hand. |
| The persistent project registry | LintCrux, SimCrux | ~650 lib / ~730 test | The one that moves *out of* this repository rather than up from the overlays. |

The cipher settles where such a repository can be. AES-GCM can never come
here: `no_bundled_encryption_test.dart` refuses it, and it would end open
core's freedom from non-exempt encryption and the store declaration that
rests on it. The suite's export-control position already names a private,
Pro-only, never-published shared repository as a home that leaves the
position unchanged — the obligations attach to what is published and to
which *products* ship a cipher, and a private repository consumed by the same
two overlays changes neither. So the private repository is the only shared
home the collaboration code can ever have, and the arithmetic ADR 0002 asked
for has reversed: four candidates, one of which has forked and one of which
is the most security-sensitive code in the suite.

Timing is the last part of the context. Carving a package out of a private
repository is a two-day move. Carving it out of a public one, after the flip,
is a deletion from published history, four submodule re-pins, and the
deprecation cycle this repository's policy commits to in writing. Everything
else can slip past the flip; this cannot.

## Decision

1. **The registry leaves; the chrome stays.** `JsonFileProjectRegistry` and
   the `crux_projects_io.dart` entry point are removed from `crux_projects`
   (0.3.0) and live in the private Pro-tier shared repository as their own
   package. `crux_projects_ui` stays here under ADR 0002's third prong. The
   open contract — `ProjectDescriptor`, `ProjectWorkspace`, `ProjectRegistry`,
   `NoopProjectRegistry`, the Riverpod seam, `perProjectScope` — is unchanged
   to the line; the goldens prove it.

2. **The test is applied to the code, per package, not to the sentence on the
   pricing page.** A package may split along the test, and "these two are
   sold together" is not an argument for moving both.

3. **The private Pro-tier shared repository exists**, created with the
   registry as its first package. Its rules, all of which are the mirror
   image of this repository's:
   - It depends on crux-shared. Nothing in crux-shared depends on it, and
     nothing in crux-shared may name it: it is a closed repository, and the
     private-references guard rejects its name along with the overlays'.
   - A Pro overlay consumes it as a **second submodule**, beside the
     open-core one. An open-core product never depends on it and must stay
     buildable without it.
   - A package belongs there when it fails ADR 0002's test — when it *is* the
     paid capability — and is shared by more than one overlay. A package that
     passes the test belongs here, whoever calls it. There is one private
     repository, not one per tier: tier is a licensing attribute enforced by
     `crux_license` at runtime, not a distribution boundary.
   - It carries its own CI, API goldens and coverage floors in this
     repository's shape, and an **exact-set** encryption guard: empty today,
     and `cryptography` alone once the collaboration lift lands, so that a
     second cipher or a swap is still a visible change.

4. **The remaining lifts are sequenced, not started here.** In this order:
   - **Licence plumbing** first — parametrise by `CruxProduct`, four
     consumers, nouns only. The cheapest lift and the proof of the wiring.
   - **Team database** second, and only **after** the two migration lists are
     reconciled. Forked schema migrations behind a byte-identical handshake
     is a data-loss shape; the lift must not be the thing that discovers
     which fork a customer's database is on. Reconcile, prove both products
     open both, then lift.
   - **Collaboration** last, after 1.0 ships, as already sequenced in the
     suite's plans: the transport, discovery and settings first, and the
     cipher with the HKDF `info` string promoted to a constructor argument so
     domain separation is explicit. The export-control facts table names the
     cipher's file paths and is updated in the same change.

5. **One-step removal, recorded as the exception it is.** The deprecation
   policy requires deprecate → migrate → remove. `JsonFileProjectRegistry`
   was removed in one step because it had no open-core consumer and every
   consumer it did have moved in the same coordinated change. The next
   removal of a symbol an open core imports goes through the three steps.

## Consequences

- crux-shared no longer contains a Pro implementation. Every tier-sensitive
  capability here is a seam again, and the published tree at the flip is the
  seam set plus mechanisms.
- **The removed file remains in this repository's history under Apache 2.0.**
  The move protects the published tree and the deprecation contract, not the
  history. Rewriting history before the flip is a separate decision with its
  own cost (every product's submodule pin), and this record does not take it.
- `crux_projects` no longer depends on `crux_io`; the registry was its only
  caller. Its web-safety guard now holds every `lib/*.dart` entry point to
  the no-`dart:io` rule rather than one named barrel.
- The purity guard names the registry noun with its two seams
  (`ProjectRegistry`, `NoopProjectRegistry`) so that a persistent registry
  landing here again fails CI rather than waiting for the next review. It
  would have failed on the file this record removes, which is the property
  ADR 0002 said no guard had.
- LintCrux Pro and SimCrux Pro gain a second submodule and a
  `dependency_overrides` block pinning `crux_projects` (and its
  dependencies) to the open-core submodule's copy. The override is not
  optional: the private repository's packages declare `crux_projects` by a
  path relative to *their* crux-shared submodule, the overlay declares it by
  a path into the open core's, and pub refuses two path descriptions of one
  name unless one is declared authoritative.
- The one-repo-per-tier alternative is closed, not deferred. Both would be
  private, consumed by the same overlays and compiled into the same
  binaries, and a repo-per-tier layout turns a pricing change into a repo
  migration.

## Notes

How to apply this to the next candidate: ask whether an open-core fork that
had the package could ship the sold feature with a provider override and no
further work. If yes, the package is the feature and belongs in the private
repository. If the fork would still be missing the thing the customer pays
for — the store, the history, the policy file, the licence — the package is a
mechanism and belongs here, whoever calls it today.
