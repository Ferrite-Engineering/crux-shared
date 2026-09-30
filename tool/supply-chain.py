#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Emit a CycloneDX SBOM for a Dart/Flutter package and gate its licences.

A suite-wide audit found nine CI configurations, no SBOM, no CVE check, and
no licence-compatibility gate anywhere. For four repositories
about to be open-sourced that is the gap that turns a licence
incompatibility into a public one — the flip is the moment it stops being
recoverable by editing a pubspec.

Usage:
    tool/supply-chain.py --sbom build/sbom.json
    tool/supply-chain.py --check-licences            # exits 1 on a violation
    tool/supply-chain.py --check-licences --tier open-core
    tool/supply-chain.py --check-advisories          # queries osv.dev

## The advisory check sends package names off the machine

`--check-advisories` posts the resolved package/version list to
`api.osv.dev`. Every name in it is a public pub.dev package, so nothing
proprietary leaves the repository — but it is a network call to a third
party, it is opt-in rather than part of `--check-licences`, and it fails
soft: an unreachable OSV is reported and does not fail the build, because
a supply-chain gate that goes red when somebody else's service is down is
a gate people route around.

## What "compatible" means here, and why the answer differs per repo

The four open-core repositories will be published under a permissive
licence. A copyleft dependency in a *distributed* closure would force that
licence to change, which is why the gate exists — but the closure that
matters is narrower than "everything pub resolved":

* **Dev dependencies are not distributed.** `build_runner` and its analyzer
  stack never ship in a binary. A GPL build tool is a licensing question
  about the developer's machine, not about the artifact, so dev-kind
  packages are reported and not gated.
* **The Pro overlays are proprietary anyway.** A copyleft dependency there
  is a genuine problem for a different reason (distribution obligations on
  a closed binary), so `--tier pro` keeps the gate but says so differently.

## Classification is textual, and deliberately conservative

pub.dev carries no machine-readable licence field, so the licence has to be
read out of the package's LICENSE file. That is a heuristic, and the failure
mode chosen here is **loud rather than quiet**: a package whose licence
cannot be identified is reported as `UNKNOWN` and fails the gate, rather
than being assumed permissive. An unknown licence in a closure about to be
published is exactly the thing somebody has to look at.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

# Licence families, most specific pattern first. Order matters: the AGPL text
# contains the string "GNU General Public License", so AGPL must be tested
# before GPL or every AGPL package would be reported as GPL.
_LICENCE_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("AGPL-3.0", re.compile(r"GNU AFFERO GENERAL PUBLIC LICENSE", re.I)),
    ("LGPL", re.compile(r"GNU LESSER GENERAL PUBLIC LICENSE", re.I)),
    ("GPL-3.0", re.compile(r"GNU GENERAL PUBLIC LICENSE\s+Version 3", re.I)),
    ("GPL-2.0", re.compile(r"GNU GENERAL PUBLIC LICENSE\s+Version 2", re.I)),
    ("MPL-2.0", re.compile(r"Mozilla Public License Version 2\.0", re.I)),
    ("Apache-2.0", re.compile(r"Apache License\s+Version 2\.0", re.I)),
    ("BSD-3-Clause", re.compile(r"Neither the name of .{0,80}nor the names", re.I | re.S)),
    ("BSD-2-Clause", re.compile(r"Redistribution and use in source and binary", re.I)),
    ("MIT", re.compile(r"Permission is hereby granted, free of charge", re.I)),
    # The Dart and Flutter ecosystem ships a bare copyright + BSD-3 body
    # without the licence's own title line, which every pattern above misses.
    ("BSD-3-Clause", re.compile(r"Copyright.{0,120}(Dart|Flutter) project authors", re.I | re.S)),
    ("Zlib", re.compile(r"This software is provided 'as-is'", re.I)),
    ("Unlicense", re.compile(r"This is free and unencumbered software", re.I)),
]

# Licences that would force a permissive open-core repo to change its own
# terms if a distributed dependency carried them.
_COPYLEFT = frozenset({"AGPL-3.0", "GPL-3.0", "GPL-2.0", "LGPL"})

# Weak copyleft: file-level obligations only. Not a blocker, but somebody
# should know it is there before the flip, so it is surfaced separately
# rather than folded into either bucket.
_WEAK_COPYLEFT = frozenset({"MPL-2.0"})


def _pub_cache() -> str:
    if os.environ.get("PUB_CACHE"):
        return os.environ["PUB_CACHE"]
    if os.name == "nt":
        return os.path.join(os.environ.get("LOCALAPPDATA", ""), "Pub", "Cache")
    return os.path.join(os.path.expanduser("~"), ".pub-cache")


def _deps(package_dir: str) -> dict:
    """The resolved dependency graph, via the tool that owns the answer."""
    for exe in ("flutter", "dart"):
        try:
            out = subprocess.run(
                [exe, "pub", "deps", "--json"],
                cwd=package_dir,
                capture_output=True,
                text=True,
                check=False,
            )
        except FileNotFoundError:
            continue
        # `flutter pub deps` prints progress lines before the JSON on some
        # versions, so start at the first brace rather than trusting stdout.
        brace = out.stdout.find("{")
        if out.returncode == 0 and brace >= 0:
            try:
                return json.loads(out.stdout[brace:])
            except json.JSONDecodeError:
                continue
    raise SystemExit(
        "could not read `pub deps --json` — run this from a package "
        "directory with dependencies already resolved (`flutter pub get`)."
    )


def _licence_text(name: str, version: str) -> str | None:
    base = os.path.join(_pub_cache(), "hosted", "pub.dev", f"{name}-{version}")
    for candidate in ("LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"):
        path = os.path.join(base, candidate)
        if os.path.isfile(path):
            with open(path, encoding="utf-8", errors="replace") as handle:
                return handle.read()
    return None


def _classify(text: str | None) -> str:
    if text is None:
        return "UNKNOWN"
    for name, pattern in _LICENCE_PATTERNS:
        if pattern.search(text):
            return name
    return "UNKNOWN"


def _components(package_dir: str) -> list[dict]:
    graph = _deps(package_dir)
    rows = []
    for pkg in graph.get("packages", []):
        kind = pkg.get("kind", "transitive")
        if kind == "root":
            continue
        name, version = pkg["name"], pkg.get("version", "")
        # Path and SDK dependencies are first-party or the SDK itself; they
        # carry no third-party obligation and have no pub-cache entry.
        source = pkg.get("source", "hosted")
        if source != "hosted":
            licence = "FIRST-PARTY" if source == "path" else "SDK"
        else:
            licence = _classify(_licence_text(name, version))
        rows.append(
            {
                "name": name,
                "version": version,
                "kind": kind,
                "source": source,
                "licence": licence,
            }
        )
    return sorted(rows, key=lambda r: r["name"])


def _sbom(package_dir: str, rows: list[dict], root: str) -> dict:
    return {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "version": 1,
        "metadata": {
            # No serialNumber: it would change on every run and make the
            # artifact undiffable, which is the main thing anyone wants from
            # a committed or archived SBOM.
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "component": {"type": "application", "name": root, "bom-ref": root},
            "tools": [{"vendor": "Ferrite Engineering", "name": "crux-supply-chain"}],
        },
        "components": [
            {
                "type": "library",
                "bom-ref": f"pkg:pub/{r['name']}@{r['version']}",
                "name": r["name"],
                "version": r["version"],
                "purl": f"pkg:pub/{r['name']}@{r['version']}",
                "scope": "excluded" if r["kind"] == "dev" else "required",
                "licenses": (
                    [{"license": {"id": r["licence"]}}]
                    if r["licence"] not in ("UNKNOWN", "FIRST-PARTY", "SDK")
                    else []
                ),
                "properties": [
                    {"name": "crux:kind", "value": r["kind"]},
                    {"name": "crux:licence", "value": r["licence"]},
                ],
            }
            for r in rows
        ],
    }


def _check(rows: list[dict], tier: str) -> int:
    distributed = [r for r in rows if r["kind"] != "dev" and r["source"] == "hosted"]
    blocking = [r for r in distributed if r["licence"] in _COPYLEFT]
    unknown = [r for r in distributed if r["licence"] == "UNKNOWN"]
    weak = [r for r in distributed if r["licence"] in _WEAK_COPYLEFT]

    print(f"{len(rows)} packages resolved, {len(distributed)} distributed.")
    if weak:
        print("\nWeak copyleft (file-level obligations, not a blocker):")
        for r in weak:
            print(f"  {r['name']} {r['version']}  {r['licence']}")

    if not blocking and not unknown:
        print("\nNo copyleft or unidentified licence in the distributed closure.")
        return 0

    if blocking:
        print("\nCOPYLEFT IN THE DISTRIBUTED CLOSURE:")
        for r in blocking:
            print(f"  {r['name']} {r['version']}  {r['licence']}  ({r['kind']})")
        if tier == "open-core":
            print(
                "\nThis repository is published under a permissive licence. A "
                "copyleft dependency that ships in the binary would force that "
                "to change, and after the open-core flip that is not something "
                "a pubspec edit takes back."
            )
        else:
            print(
                "\nThis is a proprietary overlay. A copyleft dependency here "
                "carries distribution obligations on a closed binary — a "
                "different problem from the open-core one, and not a smaller "
                "one."
            )

    if unknown:
        print("\nUNIDENTIFIED LICENCE:")
        for r in unknown:
            print(f"  {r['name']} {r['version']}  ({r['kind']})")
        print(
            "\npub.dev carries no machine-readable licence field, so these are "
            "read out of each package's LICENSE file. An unidentified one fails "
            "rather than passing quietly: assuming permissive is how a copyleft "
            "dependency gets into a published closure. Identify it, then add its "
            "pattern to _LICENCE_PATTERNS if the text is simply unfamiliar."
        )
    return 1


def _advisories(rows: list[dict]) -> int:
    """Report known advisories against the distributed closure.

    Dart ships no advisory database of its own, so this asks OSV, which
    covers the Pub ecosystem. Dev dependencies are queried too — a
    compromised build tool is a supply-chain problem even though it never
    ships — but they are reported separately, because the response to one is
    "bump it when convenient" and the response to a distributed one is not.
    """
    import urllib.error
    import urllib.request

    hosted = [r for r in rows if r["source"] == "hosted"]
    queries = [
        {"package": {"name": r["name"], "ecosystem": "Pub"}, "version": r["version"]}
        for r in hosted
    ]
    request = urllib.request.Request(
        "https://api.osv.dev/v1/querybatch",
        data=json.dumps({"queries": queries}).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            results = json.load(response).get("results", [])
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as err:
        # Soft failure on purpose. See the module docstring: a gate that goes
        # red because osv.dev is down teaches people to skip it.
        print(f"advisory check skipped — osv.dev unreachable ({err})")
        return 0

    distributed, dev = [], []
    for row, result in zip(hosted, results):
        ids = [v["id"] for v in result.get("vulns", [])]
        if not ids:
            continue
        (dev if row["kind"] == "dev" else distributed).append((row, ids))

    if dev:
        print("\nAdvisories in build-time-only dependencies:")
        for row, ids in dev:
            print(f"  {row['name']} {row['version']}  {', '.join(ids)}")

    if not distributed:
        # Count every non-dev hosted package, not `len(hosted) - len(dev)` —
        # `dev` holds only the dev packages that *have* an advisory, so that
        # subtraction reports a different total from the licence gate for the
        # same closure, and two numbers that disagree make a security report
        # look wrong even when it is right.
        shipped = sum(1 for r in hosted if r["kind"] != "dev")
        print(f"\nNo advisories against the {shipped} distributed packages.")
        return 0

    print("\nADVISORIES IN THE DISTRIBUTED CLOSURE:")
    for row, ids in distributed:
        print(f"  {row['name']} {row['version']}  {', '.join(ids)}")
        for advisory in ids:
            print(f"      https://osv.dev/vulnerability/{advisory}")
    print(
        "\nThese ship in the binary. Bump the dependency, or — if the advisory "
        "does not apply to how this code calls the package — record why in the "
        "commit that pins it, so the next person does not re-derive it."
    )
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sbom", metavar="PATH", help="write a CycloneDX SBOM")
    parser.add_argument("--check-licences", action="store_true")
    parser.add_argument("--check-advisories", action="store_true")
    parser.add_argument("--tier", choices=("open-core", "pro"), default="open-core")
    parser.add_argument("--package-dir", default=".")
    args = parser.parse_args()

    if not (args.sbom or args.check_licences or args.check_advisories):
        parser.error(
            "nothing to do: pass --sbom, --check-licences and/or "
            "--check-advisories"
        )

    rows = _components(args.package_dir)

    if args.sbom:
        root = os.path.basename(os.path.abspath(args.package_dir))
        directory = os.path.dirname(os.path.abspath(args.sbom))
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(args.sbom, "w", encoding="utf-8") as handle:
            json.dump(_sbom(args.package_dir, rows, root), handle, indent=2)
            handle.write("\n")
        print(f"wrote {args.sbom} ({len(rows)} components)")

    status = 0
    if args.check_licences:
        status |= _check(rows, args.tier)
    if args.check_advisories:
        status |= _advisories(rows)
    return status


if __name__ == "__main__":
    sys.exit(main())
