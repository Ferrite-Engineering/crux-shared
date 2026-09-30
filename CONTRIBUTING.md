# Contributing to crux-shared

`crux-shared` is the shared infrastructure layer of the EDACrux suite: the
cross-product Dart packages that WaveCrux, NetCrux, LintCrux and SimCrux all
build on. It is licensed under the Apache License, Version 2.0 (see
[`LICENSE`](LICENSE)).

**This is a library workspace, not an application.** Nothing here runs on its
own — every package is consumed as a path dependency by the four open-core
products. That shapes what a good contribution looks like, so please read the
scope rule before opening a pull request.

## Scope — what belongs here

> Only suite-wide EDA infrastructure lives here: code that **more than one
> product actually uses.**

Anything specific to a single product's domain model — waveform rendering,
netlist graphs, lint rule engines, test orchestration — belongs in that
product's own repository. The test is **consumption, not vocabulary**:
`crux_yosys` names HDL languages because Yosys elaboration is shared tooling
two products invoke, not because it models any one product's domain.

Packages here are **extracted, not authored greenfield**. Almost everything
was lifted from a shipping product once a second product needed it. A package
extracted on a single consumer freezes an API that is still moving, so a new
package proposal should name the second consumer.

## Filing issues

Use this repository's issue tracker for defects in the shared packages
themselves. If the symptom appears in a product, file it against that
product — the maintainers will move it here if the cause turns out to be
shared code.

## Submitting pull requests

1. Fork and branch from `main`.
2. Make the change in the smallest number of packages that can carry it.
3. Run the quality gates below — all of them.
4. Sign the CLA if you have not already (see below) — once per
   contributor, not per pull request.
5. Open the pull request against `main`.

## Quality gates

This workspace is managed with [Melos](https://melos.invertase.dev/). Melos is
not on `PATH` by default after a `dart pub global activate`; either add
`~/.pub-cache/bin` to your `PATH` or invoke it through `dart run melos`.

```bash
melos bootstrap          # resolve every package in the workspace

melos run format-check   # dart format --set-exit-if-changed, every package
melos run analyze        # dart analyze --fatal-infos --fatal-warnings
melos run test           # dart test / flutter test per package
```

Three further gates guard contracts that ordinary tests do not:

```bash
tool/api-snapshot.sh --check   # public API drift against the goldens in api/
tool/gen-notices.py --check    # third-party attributions match pubspec.lock
tool/check-consumers.sh        # all four products still analyze against this tree
```

`check-consumers.sh` is the one people forget. Every consumer declares bare
`path:` dependencies into its own `crux-shared` submodule with no version
constraint, so **the submodule SHA is the entire compatibility contract**.
Nothing on your machine notices when a change here removes or re-signatures a
symbol that eight repositories use. Run it before proposing any change to a
public API.

If you intentionally change a public API, regenerate the goldens in the same
commit as the code:

```bash
tool/api-snapshot.sh --write
```

## Coding conventions

- **Prefer pure Dart.** A Flutter dependency is allowed when a Flutter-only
  API is genuinely required, and the package table in `README.md` records
  which packages are which. Several packages are guarded by tests that walk
  the dependency closure and fail on an accidental Flutter edge.
- **Keep single-product vocabulary out of shared code.** A shared package that
  names one product's domain noun is a product package in the wrong repository.
- **Every package's `README.md` row in the root table stays in step with
  `ls packages/`.** The inventory is checked.
- **No dates in code comments.** They rot; git carries the history.
- New third-party dependencies change the attribution surface — run
  `tool/gen-notices.py --write` and commit the result alongside.

## Contributor License Agreement (CLA)

crux-shared requires a signed **Contributor License Agreement** before your
first contribution can be merged. It is a one-time step per contributor, not
per pull request.

The CLA does two things. It confirms you have the right to submit what you
are submitting — that you wrote it, or are permitted to contribute it — and
it grants Ferrite Engineering the licence to distribute your contribution.
**That includes distributing it under commercial licences**, in the paid
editions built on this open core, not only under the Apache 2.0 terms this
repository ships under. That is the difference between this and a Developer
Certificate of Origin, and it is the reason we ask for a signature rather
than a sign-off line. You keep the copyright in your contribution and may
use it however else you like.

It is modelled on the Apache Software Foundation's CLAs, so if you have
signed one of those the shape will be familiar. It is a single form covering
both individual and entity contributors — there is no separate corporate
version. Read it at [`CLA.md`](CLA.md).

### How to sign

Read [`CLA.md`](CLA.md), then write to
[support@ferriteengineering.com](mailto:support@ferriteengineering.com)
with `CLA` in the subject line and we will send you the signing
instructions. If you are contributing as part of your employment, say so
and name the employer: work done on company time usually belongs to the
company, and the CLA's employer clause asks you to confirm you have their
permission to contribute it.

We intend to move this into the pull request itself, so that accepting is a
click rather than an email. Until that is in place, it is email.

Open the pull request whenever you like — the CLA only gates the merge, and
nobody wants you to do the work twice. We will tell you if it is outstanding.

The name you sign under must be your real legal name. A pull request author
and a signatory who cannot be matched to each other is one we cannot merge.

### Licence of submitted code

Your contribution is distributed under the **Apache License 2.0**, the same
licence as the rest of this repository. You retain copyright; the CLA grants
the rights needed to use, modify and redistribute the work.

## Questions

Open a discussion in this repository. For questions about a specific product,
use that product's repository instead.
