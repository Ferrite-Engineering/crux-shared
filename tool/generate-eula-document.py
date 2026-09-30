#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Regenerate `crux_eula`'s embedded EULA text from the agreement's markdown.

The agreement the applications present must be the text counsel finalised, not
a paraphrase of it. This script lowers that markdown into
`lib/src/eula_document.dart`, so the package carries no runtime asset and no
per-product asset declaration.

    python3 tool/generate-eula-document.py <path/to/eula-final.md>

The published agreement is at https://edacrux.app/eula; the markdown it is
rendered from is held with Ferrite's other executed documents, and its path is
passed in rather than hardcoded here.

Run it whenever counsel returns a new version, then raise `kCruxEulaVersion` in
the same commit: the acceptance store keys on that string, so a bumped version
is what re-prompts every installation under EULA section 2.3.
"""
import re
import sys
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / \
    'packages/crux_eula/lib/src/eula_document.dart'


def blocks(md: str):
    """Yield (is_heading, text) for each block of the agreement body."""
    body = md.split('\n---\n', 1)[1] if '\n---\n' in md else md
    for raw in body.strip().split('\n'):
        line = raw.strip()
        if not line:
            continue
        if line.startswith('#'):
            yield True, re.sub(r'^#+\s*', '', line)
        else:
            # Strip bold markers; the renderer styles headings, not spans.
            yield False, re.sub(r'\*\*(.+?)\*\*', r'\1', line)


def dart_string(s: str) -> str:
    return s.replace('\\', r'\\').replace("'", r"\'").replace('$', r'\$')


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip())
    md = pathlib.Path(sys.argv[1]).read_text()

    m = re.search(r'Effective Date:\s*([^·\n]+?)\s*·\s*Version\s*([0-9.]+)', md)
    if not m:
        sys.exit('could not read the effective date and version out of the markdown')
    effective, version = m.group(1).strip(), m.group(2).strip()

    rows = [
        f"  CruxEulaBlock(isHeading: {'true' if h else 'false'}, "
        f"text: '{dart_string(t)}'),"
        for h, t in blocks(md)
    ]

    OUT.write_text(f'''// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// GENERATED FILE — DO NOT EDIT BY HAND.
//
// The lint waivers below are properties of the source text, not of this
// generator: a legal document has paragraphs longer than 80 columns and
// apostrophes inside them, and reflowing or re-quoting either one would be
// editing the agreement to suit a style rule.
// ignore_for_file: lines_longer_than_80_chars, avoid_escaping_inner_quotes
// Regenerate with `tool/generate-eula-document.py`, passing the markdown the
// agreement is maintained in. Editing this file directly puts the agreement the
// applications present out of step with the one counsel finalised — which is
// the single failure this generator exists to prevent. The published text is at
// https://edacrux.app/eula.

import 'package:meta/meta.dart';

/// One block of the agreement: a section heading, or a paragraph under one.
///
/// The document is carried as blocks rather than as one string so the dialog
/// can style headings without parsing prose at build time, and so a test can
/// assert the presence of a numbered section rather than a substring.
@immutable
class CruxEulaBlock {{
  /// Creates a block.
  const CruxEulaBlock({{required this.isHeading, required this.text}});

  /// Whether this block is a section heading.
  final bool isHeading;

  /// The block's text, with markdown emphasis removed.
  final String text;
}}

/// The version of the agreement compiled into this build.
///
/// **This is the acceptance key.** `CruxEulaAcceptanceStore` persists the
/// version the user accepted rather than a boolean, because EULA section 2.3
/// requires active re-acceptance when the agreement changes substantively and
/// a boolean cannot express "accepted an older one". Raising this constant is
/// therefore what re-prompts every installation; never raise it for a
/// typographical fix.
const String kCruxEulaVersion = '{version}';

/// The effective date printed in the dialog's header, as counsel set it.
const String kCruxEulaEffectiveDate = '{effective}';

/// The agreement itself, in document order.
const List<CruxEulaBlock> kCruxEulaDocument = <CruxEulaBlock>[
{chr(10).join(rows)}
];
''')
    print(f'{OUT.relative_to(OUT.parents[3])}: version {version}, '
          f'effective {effective}, {len(rows)} blocks')


if __name__ == '__main__':
    main()
