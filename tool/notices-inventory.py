#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Keep a complete package inventory inside a product's hand-written NOTICES.

    tool/notices-inventory.py --check <repo>   # exit 1 if the inventory is stale
    tool/notices-inventory.py --write <repo>   # rewrite the inventory block

## Why this exists rather than a generator

`gen-notices.py` generates the whole of crux-shared's NOTICES, which works
because that file is nothing but a dependency list. The four products' NOTICES
are not: they carry the elaboration engines invoked as subprocesses, vendored
JavaScript under EPL-2.0, the QuickJS binaries inside `flutter_js`, and a
register of open items that names what has *not* been independently verified.
None of that is derivable from a lock file, and a generator pointed at these
files would delete it.

So this tool owns one block and nothing else. Everything outside the markers
is hand-written and stays that way.

## What the block contains, and why it is everything

Every package in the resolved lock, not only the ones believed to ship. The
narrower list is more faithful to Apache-2.0 §4(d), and it was considered --
but `pub deps` marks only *direct* dev dependencies as `dev`; the transitive
closure of a dev dependency comes back indistinguishable from a shipped one.
A rule that cannot be computed is a rule that drifts, and a missing
attribution is the failure that matters here. So the inventory is complete and
says plainly that some entries are development-only.

The narrative sections above it remain the place where a package gets
explained. This is the backstop that catches the one nobody wrote up --
`window_manager` shipped in NetCrux for months without an entry.
"""
import importlib.util
import os
import re
import sys

BEGIN = '-- BEGIN GENERATED INVENTORY --'
END = '-- END GENERATED INVENTORY --'
TAIL = 'End of NOTICES.'
W = 74


def _gen_notices():
    """The classifier, borrowed rather than copied.

    `gen-notices.py` already reads a lock file and matches licence text out of
    the pub cache, and two implementations of that would disagree on the day
    it mattered. The module name has a dash, so it cannot be imported by name.
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        'gen-notices.py')
    spec = importlib.util.spec_from_file_location('gen_notices', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rows_for(repo):
    gn = _gen_notices()
    gn.LOCK = os.path.join(repo, 'pubspec.lock')
    if not os.path.exists(gn.LOCK):
        raise SystemExit(f'no pubspec.lock in {repo}')
    return gn.collect()


def render(rows, number):
    bar = '-' * W
    out = [BEGIN, '', bar, f'{number}. Complete resolved inventory', bar, '']
    out.append('Every package in pubspec.lock, with the licence its own')
    out.append('LICENSE file matches. Generated: do not hand-edit inside the')
    out.append('markers, and do not use it to replace the narrative sections')
    out.append('above -- a package that needs explaining still needs an entry')
    out.append('there.')
    out.append('')
    out.append('Some entries are development-only and are never redistributed')
    out.append('in a product binary. They are listed anyway: `pub deps` marks')
    out.append('only direct dev dependencies as such, so the shipped subset')
    out.append('cannot be computed exactly, and over-listing is the safe side')
    out.append('of an attribution question.')
    out.append('')
    by = {}
    for _, _, spdx, _ in rows:
        by[spdx] = by.get(spdx, 0) + 1
    out.append('  ' + ',  '.join(f'{k} {v}' for k, v in sorted(by.items())))
    out.append('')
    for name, version, spdx, _ in sorted(rows):
        out.append(f'  {name:<44} {version:<16} {spdx}')
    out.append('')
    out.append(END)
    return '\n'.join(out)


def next_section_number(text):
    """One past the highest numbered section already in the file."""
    numbers = [int(m) for m in re.findall(r'^(\d+)\.\s+\S', text, re.M)]
    return (max(numbers) + 1) if numbers else 1


def apply(text, block):
    if BEGIN in text and END in text:
        head, rest = text.split(BEGIN, 1)
        _, tail = rest.split(END, 1)
        return head + block + tail
    if TAIL in text:
        head, tail = text.rsplit(TAIL, 1)
        return head + block + '\n\n' + TAIL + tail
    return text.rstrip('\n') + '\n\n' + block + '\n'


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('--check', '--write'):
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        print('usage: notices-inventory.py --check|--write <repo>',
              file=sys.stderr)
        return 2
    mode, repo = sys.argv[1], sys.argv[2]
    notices = os.path.join(repo, 'NOTICES')
    if not os.path.exists(notices):
        print(f'{repo}: no NOTICES file', file=sys.stderr)
        return 1

    current = open(notices, encoding='utf-8').read()
    rows = rows_for(repo)
    unknown = [r for r in rows if r[2] == 'UNKNOWN']
    if unknown:
        print(f'{repo}: cannot classify, resolve by hand before release:',
              file=sys.stderr)
        for name, version, _, _ in unknown:
            print(f'    {name}-{version}', file=sys.stderr)
        return 1

    # A rewrite keeps the number the block already has, so regenerating never
    # renumbers a file somebody may have cited.
    existing = re.search(rf'{re.escape(BEGIN)}.*?^(\d+)\.\s', current,
                         re.S | re.M)
    number = int(existing.group(1)) if existing else next_section_number(current)
    updated = apply(current, render(rows, number))

    if mode == '--write':
        open(notices, 'w', encoding='utf-8').write(updated)
        print(f'{repo}: inventory §{number} written, {len(rows)} packages')
        return 0
    if updated != current:
        print(f'{repo}: NOTICES inventory is stale — run '
              f'python3 crux-shared/tool/notices-inventory.py --write {repo}',
              file=sys.stderr)
        return 1
    print(f'{repo}: NOTICES inventory is current ({len(rows)} packages)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
