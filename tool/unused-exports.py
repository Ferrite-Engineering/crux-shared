#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Which exported symbols does no consumer use?

    tool/unused-exports.py                    # report, consumers found beside this repo
    tool/unused-exports.py --root DIR         # look for consumers under DIR instead
    tool/unused-exports.py --consumer DIR     # add a consumer checkout (repeatable)
    tool/unused-exports.py --package crux_x   # only this package's barrels
    tool/unused-exports.py --json             # machine-readable
    tool/unused-exports.py --check            # exit 1 when anything is unused

## Why this exists

`lib_reachability_test.dart` proves every file under `lib/` is reachable from
its package's barrels. It cannot say whether anything outside the package
uses what those barrels export, because the answer lives in other
repositories. A provider can be exported, golden-tracked, documented as the
mechanism, tested — and read by nothing. That has happened here more than
once, and each time a human found it by grepping.

This does the grep, for every top-level symbol in every `api/*.api.txt`
golden (the generated record of each barrel's export namespace), across:

  * every other package in this repository — a sibling package is a consumer;
  * every consumer checkout under the products root (`$CRUX_PRODUCTS_ROOT`, or
    the directory holding this repository): any directory that vendors this
    repository as a `crux-shared/` submodule, directly or one level down. That
    signature finds the four open cores, the checkouts that wrap them, and any
    other application or shared repository built on these packages, without
    this file having to name one;
  * any `--consumer` directory given explicitly.

Vendored copies of this repository (`crux-shared/` inside a consumer) are
skipped, as are `.dart_tool/` and `build/`.

## What the verdicts mean

  used       referenced by production code outside the declaring package
  test-only  referenced outside the declaring package only under `test/`,
             `integration_test/` or `test_driver/` — alive for a harness, dead
             for a user
  internal   referenced by no consumer, but by another `lib/` file of its own
             package: exported needlessly. Narrowing it is an API change and
             follows the deprecation policy; nothing is dead
  unused     referenced by no consumer and by no other file of its own
             package's `lib/`. The candidates for deletion — each still needs
             a human to confirm the declaring file does not use it itself

## What it cannot see, so read the list rather than acting on it blind

  * It matches identifiers, not resolved elements. Two symbols with one name
    make both look used; a symbol only mentioned in a comment does not count
    (comments are stripped), but one named inside a string literal does.
  * Top-level names only. A class that is used while half its members are not
    reports as used.
  * A name, not a use. A type a consumer only ever receives — built by a
    factory it calls, never written out — reads as `test-only` or `internal`
    while the product runs it on every launch (`CruxLicensePanel`, mounted
    through `cruxLicenseSettingsCategory`, is one).
  * An extension, or an operator, is used without its name being written, so
    `extension` symbols are always reported as used.
  * A symbol public on purpose for a consumer that does not exist yet — the
    `crux_cxp` surface a third-party tool will build against — is `unused`
    here and correct anyway.

It is a report, not a gate. It is not wired into CI: the consumers are other
repositories, the `consumers` workflow checks out only one open core per job,
and a verdict that depends on which checkouts happened to be present is not
one to fail a build on.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
API = os.path.join(REPO, "api")
PACKAGES = os.path.join(REPO, "packages")

SKIP_DIRS = {".dart_tool", "build", ".git", "node_modules", "crux-shared"}
TEST_DIRS = {"test", "integration_test", "test_driver"}

# No `$`: inside a string it starts an interpolation, and `'$name'` must read
# as a use of `name`. No exported symbol here spells one.
_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_INTERPOLATION = re.compile(r"\$\{([^}]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)")
_MODIFIERS = r"(?:(?:abstract|sealed|final|interface|base|mixin)\s+)*"
_TYPE_DECL = re.compile(
    rf"^{_MODIFIERS}(class|mixin|enum|typedef|extension(?:\s+type)?)\s+"
    r"([A-Za-z_$][A-Za-z0-9_$]*)"
)
_GETTER = re.compile(r"^get\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+->")
_SETTER = re.compile(r"^set\s+([A-Za-z_$][A-Za-z0-9_$]*)=")
_FUNCTION = re.compile(r"^([A-Za-z_$][A-Za-z0-9_$]*)(?:<[^(]*>)?\(")
_EXPORT = re.compile(r"^\s*export\s[^;]*;", re.M)


# ── the exported symbols ───────────────────────────────────────────────────


def barrel_owners() -> dict[str, str]:
    """{golden stem: package} — every top-level lib/*.dart is a barrel."""
    owners: dict[str, str] = {}
    for pkg in sorted(os.listdir(PACKAGES)):
        lib = os.path.join(PACKAGES, pkg, "lib")
        if not os.path.isdir(lib):
            continue
        for f in os.listdir(lib):
            if f.endswith(".dart"):
                owners[f[: -len(".dart")]] = pkg
    return owners


def exported_symbols(golden: str) -> list[tuple[str, str]]:
    """[(name, kind)] for each top-level line of one golden."""
    out: list[tuple[str, str]] = []
    for line in open(golden, encoding="utf-8"):
        if not line.strip() or line.startswith(("#", " ")):
            continue
        line = line.rstrip("\n")
        if m := _TYPE_DECL.match(line):
            kind = m.group(1).split()[0]
            out.append((m.group(2), kind))
        elif m := _GETTER.match(line) or _SETTER.match(line):
            out.append((m.group(1), "variable"))
        elif m := _FUNCTION.match(line):
            out.append((m.group(1), "function"))
        else:
            raise SystemExit(
                f"{os.path.relpath(golden, REPO)}: cannot read top-level line "
                f"{line!r} — has the golden format changed?"
            )
    return out


# ── the references ─────────────────────────────────────────────────────────


def strip_comments(src: str, strings: bool = True) -> str:
    """Source with comments blanked. String literals are kept, or, when
    [strings] is false, reduced to the expressions they interpolate — so a
    provider's own `name: 'fooProvider'` is not a use of it, and `'$foo'`
    still is."""
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j == -1 else j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            i = j
            out.append(" ")
            continue
        c = src[i]
        if c in "'\"":
            quote = src[i : i + 3] if src.startswith(c * 3, i) else c
            raw = i > 0 and src[i - 1] == "r"
            j = i + len(quote)
            while j < n and not src.startswith(quote, j):
                j += 2 if (src[j] == "\\" and not raw) else 1
            j = min(n, j + len(quote))
            if strings:
                out.append(src[i:j])
            elif not raw:
                out.append(
                    " "
                    + " ".join(
                        a or b for a, b in _INTERPOLATION.findall(src[i:j])
                    )
                    + " "
                )
            else:
                out.append(" ")
            i = j
            continue
        out.append(c)
        i += 1
    return "".join(out)


def dart_files(root: str):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if f.endswith(".dart"):
                yield os.path.join(d, f)


def is_test_path(path: str, root: str) -> bool:
    return any(part in TEST_DIRS for part in os.path.relpath(path, root).split(os.sep))


def index_identifiers(
    root: str,
    index: dict[str, dict[str, set[str]]],
    owner: str,
    lib_files: dict[str, set[str]] | None = None,
):
    """Record, per identifier, which owners reference it and in what role —
    and, when [lib_files] is given, which of the owner's `lib/` files do."""
    lib = os.path.join(root, "lib") + os.sep
    for path in dart_files(root):
        role = "test" if is_test_path(path, root) else "prod"
        try:
            src = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        code = strip_comments(src)
        for ident in set(_IDENT.findall(code)):
            index.setdefault(ident, {}).setdefault(owner, set()).add(role)
        if lib_files is not None and path.startswith(lib):
            # A re-export names a symbol without using it.
            for ident in set(_IDENT.findall(_EXPORT.sub(" ", code))):
                lib_files.setdefault(ident, set()).add(path)


def find_consumers(products_root: str) -> list[str]:
    """Every directory under [products_root] that vendors this repository."""
    found = []
    for name in sorted(os.listdir(products_root)):
        d = os.path.join(products_root, name)
        if not os.path.isdir(d) or os.path.samefile(d, REPO):
            continue
        vendored = os.path.isdir(os.path.join(d, "crux-shared", "packages")) or any(
            os.path.isdir(os.path.join(d, child, "crux-shared", "packages"))
            for child in os.listdir(d)
            if os.path.isdir(os.path.join(d, child))
        )
        if vendored:
            found.append(d)
    return found


def used_in_own_file(path: str, name: str, kind: str) -> bool:
    """Whether [name] is used in [path], the one `lib/` file that names it,
    beyond being declared there.

    Counts code occurrences — comments and string literals removed — and
    subtracts the declaration: one for anything, plus each constructor
    declaration for a class. A self-reference such as `other is Name` in an
    `==` counts as a use, which errs towards `internal` and away from calling
    something dead that is not.
    """
    code = strip_comments(open(path, encoding="utf-8").read(), strings=False)
    word = re.escape(name)
    total = len(re.findall(rf"(?<![\w]){word}(?![\w])", code))
    declared = 1
    if kind == "class":
        declared += len(
            re.findall(
                rf"^\s*(?:const\s+|factory\s+|external\s+)*{word}"
                r"(?:\.[A-Za-z_$][\w$]*)?\s*\(",
                code,
                re.M,
            )
        )
    if kind == "variable":
        # A getter and setter pair declares the name twice.
        declared += len(re.findall(rf"\bset\s+{word}\b", code))
    return total > declared


# ── the report ─────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--root", default=os.environ.get("CRUX_PRODUCTS_ROOT"))
    ap.add_argument("--consumer", action="append", default=[])
    ap.add_argument("--package", action="append", default=[])
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    products_root = os.path.abspath(args.root or os.path.join(REPO, ".."))
    consumers = find_consumers(products_root) + [
        os.path.abspath(c) for c in args.consumer
    ]
    if not consumers:
        print(
            f"no consumer checkout found under {products_root} — every export "
            f"would read as unused. Pass --root or --consumer.",
            file=sys.stderr,
        )
        return 2

    index: dict[str, dict[str, set[str]]] = {}
    own_lib: dict[str, dict[str, set[str]]] = {}
    for pkg in sorted(os.listdir(PACKAGES)):
        if os.path.isdir(os.path.join(PACKAGES, pkg)):
            index_identifiers(
                os.path.join(PACKAGES, pkg),
                index,
                f"pkg:{pkg}",
                own_lib.setdefault(pkg, {}),
            )
    for c in consumers:
        index_identifiers(c, index, f"consumer:{os.path.basename(c)}")

    owners = barrel_owners()
    results: list[dict[str, object]] = []
    for golden in sorted(os.listdir(API)):
        if not golden.endswith(".api.txt"):
            continue
        stem = golden[: -len(".api.txt")]
        pkg = owners.get(stem)
        if pkg is None:
            raise SystemExit(f"api/{golden}: no package has lib/{stem}.dart")
        if args.package and pkg not in args.package:
            continue
        for name, kind in exported_symbols(os.path.join(API, golden)):
            refs = {
                who: roles
                for who, roles in index.get(name, {}).items()
                if who != f"pkg:{pkg}"
            }
            roles = set().union(*refs.values()) if refs else set()
            own_files = own_lib[pkg].get(name, set())
            if kind == "extension" or "prod" in roles:
                verdict = "used"
            elif roles:
                verdict = "test-only"
            elif len(own_files) > 1 or (
                len(own_files) == 1
                and used_in_own_file(next(iter(own_files)), name, kind)
            ):
                verdict = "internal"
            else:
                verdict = "unused"
            results.append(
                {
                    "package": pkg,
                    "barrel": f"{stem}.dart",
                    "symbol": name,
                    "kind": kind,
                    "verdict": verdict,
                    "referenced_by": sorted(refs),
                }
            )

    # A symbol exported by two barrels of one package is one symbol.
    seen: set[tuple[str, str]] = set()
    unique = []
    for r in results:
        key = (str(r["package"]), str(r["symbol"]))
        if key not in seen:
            seen.add(key)
            unique.append(r)

    if args.json:
        json.dump(
            {
                "consumers": [os.path.basename(c) for c in consumers],
                "symbols": unique,
            },
            sys.stdout,
            indent=2,
        )
        print()
    else:
        print("consumers: " + ", ".join(os.path.basename(c) for c in consumers))
        for verdict in ("unused", "test-only", "internal"):
            rows = [r for r in unique if r["verdict"] == verdict]
            print(f"\n{verdict}: {len(rows)}")
            for r in rows:
                where = (
                    f"  (tests in {', '.join(r['referenced_by'])})"
                    if verdict == "test-only"
                    else ""
                )
                print(f"  {r['package']}: {r['symbol']} [{r['kind']}]{where}")
        used = sum(1 for r in unique if r["verdict"] == "used")
        print(f"\nused: {used} of {len(unique)} exported top-level symbols")

    unused = sum(1 for r in unique if r["verdict"] == "unused")
    return 1 if args.check and unused else 0


if __name__ == "__main__":
    sys.exit(main())
