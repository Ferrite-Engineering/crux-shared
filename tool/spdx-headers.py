#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Insert and verify per-file SPDX headers across a Crux source tree.

    tool/spdx-headers.py --check [REPO...]   # exit 1 if any file lacks one
    tool/spdx-headers.py --write [REPO...]   # insert where missing
    tool/spdx-headers.py --list  [REPO...]   # show what is in scope

With no REPO argument it operates on the repository containing this script.
The four product repos consume it through their `crux-shared` submodule:

    python3 crux-shared/tool/spdx-headers.py --check .

Scope: first-party source only, taken from `git ls-files` so that anything
untracked or ignored is out of scope by construction. Generated files are
excluded — a header there would be erased by the next `build_runner` run and
the check would flap. Vendored third-party trees are excluded because their
copyright is not ours to assert; that is the one exclusion where being wrong
is a licensing error rather than a tidiness one.

The header is two lines, matching the LICENSE copyright holder exactly:

    // Copyright 2026 Ferrite Engineering LLC
    // SPDX-License-Identifier: Apache-2.0

Idempotent: a file that already carries an SPDX-License-Identifier is left
untouched, including one with a different holder — that is a vendored-file
signal worth a human look, not something to overwrite.
"""
import os
import re
import subprocess
import sys

HOLDER = 'Copyright 2026 Ferrite Engineering LLC'
SPDX = 'SPDX-License-Identifier: Apache-2.0'

# extension -> comment leader
LEADERS = {
    '.dart': '//', '.rs': '//', '.kt': '//', '.swift': '//',
    '.cpp': '//', '.cc': '//', '.h': '//', '.hpp': '//',
    '.sh': '#', '.py': '#', '.bash': '#',
}

# Directories whose contents are first-party source we assert copyright over.
SOURCE_DIRS = ('lib/', 'bin/', 'tool/', 'test/', 'integration_test/',
               'native/', 'scripts/', 'packages/')

# Generated: rewritten by a generator, so a header cannot survive there.
GENERATED = re.compile(
    r'('
    r'\.(g|freezed|mocks|config|gen)\.dart$'
    r'|/generated/|/generated_plugin_registrant\.dart$'
    r'|\.pb\.dart$|\.pbenum\.dart$|\.pbjson\.dart$|\.pbserver\.dart$'
    r')')

# Vendored: third-party code living in our tree. Their copyright, not ours.
VENDORED = re.compile(
    r'(^|/)(third_party|vendor|vendored|\.dart_tool|build|node_modules)/')


def tracked(repo):
    out = subprocess.run(['git', '-C', repo, 'ls-files'],
                         capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line.strip()]


def in_scope(path):
    if VENDORED.search(path) or GENERATED.search(path):
        return False
    if os.path.splitext(path)[1] not in LEADERS:
        return False
    return path.startswith(SOURCE_DIRS) or '/' in path and any(
        f'/{d}' in f'/{path}' for d in SOURCE_DIRS)


def has_header(text):
    # Only look at the top of the file; an SPDX id inside a string literal or
    # a licence-parsing test further down must not count as a header.
    return SPDX in '\n'.join(text.splitlines()[:10])


def insert(text, leader):
    lines = text.split('\n')
    header = [f'{leader} {HOLDER}', f'{leader} {SPDX}', '']
    at = 0
    # A shebang must stay on line 1. Insert after it, and after an existing
    # blank line if there is one, so we never collapse the author's spacing.
    if lines and lines[0].startswith('#!'):
        at = 2 if len(lines) > 1 and lines[1].strip() == '' else 1
    return '\n'.join(lines[:at] + header + lines[at:])


def run(repo, mode):
    files = [f for f in tracked(repo) if in_scope(f)]
    missing = []
    for rel in files:
        p = os.path.join(repo, rel)
        try:
            text = open(p, encoding='utf-8').read()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        if has_header(text):
            continue
        missing.append(rel)
        if mode == '--write':
            leader = LEADERS[os.path.splitext(rel)[1]]
            open(p, 'w', encoding='utf-8').write(insert(text, leader))
    return files, missing


def main():
    args = sys.argv[1:]
    mode = next((a for a in args if a.startswith('--')), '--check')
    repos = [a for a in args if not a.startswith('--')] or \
        [os.path.dirname(os.path.dirname(os.path.abspath(__file__)))]

    total = failed = 0
    for repo in repos:
        name = os.path.basename(os.path.abspath(repo))
        files, missing = run(repo, mode)
        total += len(files)
        if mode == '--list':
            print(f'{name}: {len(files)} files in scope')
            continue
        if mode == '--write':
            print(f'{name}: {len(missing)} header(s) inserted, '
                  f'{len(files)} in scope')
            continue
        if missing:
            failed += len(missing)
            print(f'{name}: {len(missing)} of {len(files)} files lack an '
                  f'SPDX header', file=sys.stderr)
            for rel in missing[:20]:
                print(f'    {rel}', file=sys.stderr)
            if len(missing) > 20:
                print(f'    ... and {len(missing) - 20} more', file=sys.stderr)
        else:
            print(f'{name}: all {len(files)} source files carry an SPDX header')

    if mode == '--check' and failed:
        print(f'\nRun: python3 {sys.argv[0]} --write', file=sys.stderr)
        return 1
    if mode == '--list':
        print(f'TOTAL: {total}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
