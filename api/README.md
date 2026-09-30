# Public API goldens

Each `<barrel>.api.txt` in this directory is a generated, deterministic
rendering of one library's **export namespace** — precisely the set of symbols a
consuming product can reach through `package:<package>/<barrel>.dart`, with
signatures.

Most packages have exactly one barrel, so most goldens are named after the
package. A package may also expose **secondary barrels** — further top-level
`lib/*.dart` entry points that let a constrained host import a subset without
the dependency the main barrel drags in. Each gets its own golden:

| Golden | Why the entry point exists |
|---|---|
| `crux_license_core.api.txt` | Keeps `dart:ui` out of a **headless** AOT kernel, so `dart build cli` in the products' Pro CLIs compiles. |
| `crux_sqlite_guards.api.txt`, `crux_sqlite_test_support.api.txt` | Test-only tooling kept out of the runtime barrel every store opens through. |

These files are not documentation and are not read at runtime. They exist to
make one specific event visible: *somebody changed the substrate that eight
repos depend on.*

## Why

Every consumer declares a bare `path:` dependency into its `crux-shared` git
submodule, with no version constraint. There is therefore no version solver, no
semver gate, and no build-time signal at all between a change here and four
products breaking. Before these goldens existed, removing a public symbol
produced exactly the same green CI as renaming a private one.

A golden diff does not mean "you did something wrong". It means "this change
leaves the repo and lands in four products — look at it deliberately".

## Commands

```bash
tool/api-snapshot.sh --check    # what CI runs; fails if any golden is stale
tool/api-snapshot.sh --write    # regenerate after an intentional API change
```

`--write` is the only supported way to update these files; they are generated
and hand-edits will be overwritten. Commit the regenerated goldens **in the same
commit as the code change that caused them**, so the diff reviewer sees the API
delta next to its cause.

## Reading a diff

| Diff shape | Meaning |
|---|---|
| A line disappears | **Breaking.** Some product may reference it. Should have been deprecated first — see the deprecation policy in `CLAUDE.md`. |
| A line changes shape (parameter added/removed/renamed, type changed, `required` added) | **Breaking**, even when the symbol name is unchanged. |
| A line appears | New public surface. Justify it: is it needed by a second product today, or is it speculative? Unreferenced exports accumulated to ~57 before anyone counted; `python3 tool/unused-exports.py` counts them now, against every consumer checkout it can find. |
| Only ordering changes | Should not happen — output is sorted. File a bug against the generator. |

## Scope and limits

- The snapshot covers the barrel's export namespace only. It deliberately does
  **not** cover `lib/src/**` internals, which are free to change.
- It records signatures, not behavior. A method whose body changes meaning
  while keeping its signature produces no diff. That is the `consumers` CI
  job's problem, not this one's.
- Doc comments, annotations and default parameter *values* are not recorded.
  A default value change is source-compatible but behaviorally breaking, and
  this guard will not see it.
- Every package must expose a `lib/<package>.dart` main barrel. A package with
  a `lib/` and no main barrel is a hard error, not a skip — otherwise a package
  could silently escape API tracking. Every *other* top-level `lib/*.dart` file
  is snapshotted as a secondary barrel for the same reason: a consumer can
  import it, so it is public API. Anything a package genuinely wants unexported
  belongs under `lib/src/`.

## If the consumer job cannot authenticate

`.github/workflows/consumers.yml` has a `consumers` job that checks out each product
repo and analyzes it against the crux-shared commit under test. All four product
repos are private, so the job authenticates with `SUBMODULE_PAT`, the
organization-level fine-grained read-only PAT that the product workflows already
use in the opposite direction (to fetch crux-shared as a submodule). It is an
org secret with `ALL` repository visibility, so it is readable here.

If the checkout step fails with a 404, the PAT's **resource scope** does not
include the product repositories — visibility and scope are separate settings on
a fine-grained PAT. Widen the scope to include `wavecrux`, `netcrux`, `lintcrux`
and `simcrux`. **Do not delete or disable the job**: the whole point of this
item is that a job which never runs is indistinguishable from a job that passes.

The local equivalent, which needs no token, is `tool/check-consumers.sh` — run
it before bumping a product's submodule pin.
