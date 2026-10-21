#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Keep only a synthesized design's top module and rewrite the Yosys share
directory prefix in its source spans.

    python3 -I trim_design.py <in.json> <out.json> <share-prefix>

Every `src` attribute of the top module, its cells and its nets is split on
`|`; each span whose file starts with <share-prefix> has that prefix
replaced by `<yosys-share>`; the spans are joined again. Nothing else
changes. Splitting first is the point: one rewrite over the whole attribute
string would also swallow the user span before the `|`.
"""
import json
import sys

src_in, src_out, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src_in, encoding="utf-8") as f:
    design = json.load(f)

top = [n for n, m in design["modules"].items()
       if m.get("attributes", {}).get("top", "0").strip("0")]
assert len(top) == 1, top
module = design["modules"][top[0]]


def scrub(attrs):
    src = attrs.get("src")
    if src is None:
        return
    parts = []
    for span in src.split("|"):
        if span.startswith(prefix):
            span = "<yosys-share>" + span[len(prefix):]
        parts.append(span)
    attrs["src"] = "|".join(parts)


scrub(module.get("attributes", {}))
for cell in module.get("cells", {}).values():
    scrub(cell.get("attributes", {}))
for net in module.get("netnames", {}).values():
    scrub(net.get("attributes", {}))

out = {"creator": design["creator"], "modules": {top[0]: module}}
with open(src_out, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
