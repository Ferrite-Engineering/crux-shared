# ADR 0002 — A package with only Pro consumers still belongs in crux-shared

**Status:** Accepted (2026-08-18)
**Scope:** Cross-suite — the placement rule for any future shared package whose
only callers are Pro overlays.
**Related:** a suite-wide audit's finding of duplicated trend-tracking code
across the Pro overlays.

## Context

`crux_heatmap` is consumed by LintCrux Pro and SimCrux Pro and by nothing in
open core. The audit that prompted its extraction proposed a different home for
it: a new private shared repository for Pro-tier code, standing beside crux-shared with
the same CI shape, to hold Pro-tier shared code.

The motivating property is real and worth protecting. crux-shared was audited
for open-core purity and came back clean: every tier-sensitive capability in it
is a *seam* — an interface plus a no-op default — rather than an implementation.
Nothing there would leak a paid capability if the repo were open-sourced
tomorrow. A rule that let Pro implementations accumulate in crux-shared would
destroy that property quietly, one package at a time.

The timing argument was also sound: today the split between crux-shared and the
four overlays is clean, and a second shared layer is far cheaper to introduce
now than to carve out of four public repositories after the open-core flip.

What did not hold up was the premise that there was enough to put in it. The
audit reported ~1,680 lines of duplicated trend-tracking UI across the two Pro
overlays. Measured per file pair, after stripping comments and normalising the
product nouns:

| Pair | Genuinely shared |
|---|---|
| calendar heatmap grid | **69%** |
| alerts banner | 44% |
| calendar heatmap screen | 37% |
| per-X trend chart screen | 35% |
| retention settings section | 22% |

One file was a fork. The rest is two products solving a similar problem with
similar Flutter idioms — which reads as duplication in a line count and as
ordinary parallel code when the files are put side by side.

## Decision

**Tier is a property of the consumer, not of the code.** A package belongs in
crux-shared when its content is tier-neutral, regardless of which repositories
happen to call it. A package belongs in a Pro-tier repository when its content
*is* the paid capability.

For `crux_heatmap` the test is easy to apply: it lays out a date grid and wires
taps and tooltips. It does not know what it is plotting, because the host
resolves each cell's colour and tooltip. Nothing about it is worth money. What
is worth money is the trend store feeding it — the per-run history, the
retention policy, the aggregation — and that stays in the overlays, where the
tier gate already lives.

The concrete rule, applied to any candidate:

- If open-sourcing the package would hand a competitor a paid capability, it is
  not a crux-shared package.
- If the package would need a tier check, a licence read, or a feature gate to
  behave correctly, it is not a crux-shared package.
- If the package is a mechanism and the *inputs* are what the customer pays
  for, it is a crux-shared package, and having only Pro callers today does not
  change that.

**A private shared Pro-tier repository is deferred, not rejected.** It should be created when a
second genuine candidate appears — one that fails the test above and is shared
by more than one overlay. The likeliest one is the trend *stores* themselves,
which were never examined, because the audit scoped itself to UI.

## Consequences

- A reader of crux-shared will find packages with no open-core caller. That is
  expected and is not evidence of a placement error. The purity guard
  (`crux_workspace/test/static/open_core_purity_test.dart`) tests for leaked
  capability, which is the property that actually matters, rather than for
  who calls what.
- The cost of *not* creating the repo now is bounded and does not grow: the
  same repo is no harder to stand up for the second candidate than it would
  have been for the first. The cost of creating it now is a permanent
  maintenance surface — melos, CI, API goldens, Consumer jobs — carrying about
  a hundred lines.
- A package that starts tier-neutral and later grows a tier-sensitive
  capability must move rather than acquire a gate. The purity guard will catch
  the gate; nothing will catch the drift before it, so it stays a review
  question.
