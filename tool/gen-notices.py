#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Generate NOTICES from pubspec.lock and the local pub cache.

    tool/gen-notices.py            # print a classification summary
    tool/gen-notices.py --write    # rewrite NOTICES
    tool/gen-notices.py --check    # exit 1 if NOTICES is stale or any
                                   # package cannot be classified

Why this is generated rather than hand-maintained: the attribution list is
the resolved dependency closure, which moves whenever pubspec.lock moves.
A hand-written NOTICES silently drifts from what is actually redistributed,
and the drift is invisible until someone audits it — which, for an Apache-2.0
release, is exactly when it is most expensive to be wrong.

The classifier reads each hosted package's own LICENSE out of the pub cache
and matches the text. It never guesses from package metadata: a pubspec
`license:` field is a claim, the shipped LICENSE file is the artifact.
Anything it cannot classify is reported as UNKNOWN and fails --check, because
an unclassified dependency in a public release is a legal question, not a
formatting one.
"""
import os
import re
import sys
import textwrap

CACHE = os.path.expanduser('~/.pub-cache/hosted/pub.dev')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCK = os.path.join(ROOT, 'pubspec.lock')
OUT = os.path.join(ROOT, 'NOTICES')
W = 74

# Ordered most-specific first: BSD-3 contains the BSD-2 text plus the
# "neither the name" clause, so testing BSD-2 first would swallow every BSD-3.
PATTERNS = [
    ('BSD-3-Clause', r'Redistribution and use in source and binary forms.*?Neither the name'),
    ('BSD-2-Clause', r'Redistribution and use in source and binary forms'),
    ('Apache-2.0', r'Apache License\s*Version 2\.0'),
    ('MIT', r'Permission is hereby granted, free of charge'),
    ('MPL-2.0', r'Mozilla Public License'),
    ('ISC', r'Permission to use, copy, modify, and(/or)? distribute'),
    ('Zlib', r'altered source versions must be plainly marked'),
]


def parse_lock(path):
    """Minimal pubspec.lock reader: name -> {version, source, ...}."""
    pkgs, name, cur, inpkgs = {}, None, {}, False
    for line in open(path, encoding='utf-8'):
        if line.startswith('packages:'):
            inpkgs = True
            continue
        if inpkgs and re.match(r'^[a-z]', line):
            break
        m = re.match(r'^  ([A-Za-z0-9_]+):\s*$', line)
        if m:
            if name:
                pkgs[name] = cur
            name, cur = m.group(1), {}
            continue
        m = re.match(r'^    (\w+): "?([^"\n]*)"?', line)
        if m and name:
            cur[m.group(1)] = m.group(2).strip()
    if name:
        pkgs[name] = cur
    return pkgs


def licence_text(name, version):
    d = os.path.join(CACHE, f'{name}-{version}')
    for candidate in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING'):
        p = os.path.join(d, candidate)
        if os.path.exists(p):
            return open(p, encoding='utf-8', errors='replace').read().strip()
    return ''


def classify(text):
    flat = re.sub(r'\s+', ' ', text)
    for spdx, pattern in PATTERNS:
        if re.search(pattern, flat, re.I | re.S):
            return spdx
    return 'UNKNOWN'


def copyright_of(text):
    for line in text.splitlines():
        if re.search(r'copyright', line, re.I) and len(line.strip()) > 12:
            return line.strip()
    return ''


def collect():
    rows = []
    for name, meta in sorted(parse_lock(LOCK).items()):
        version, source = meta.get('version', '?'), meta.get('source', '?')
        if source != 'hosted':
            rows.append((name, version, 'SDK', ''))
            continue
        text = licence_text(name, version)
        if not text:
            rows.append((name, version, 'UNKNOWN', ''))
            continue
        rows.append((name, version, classify(text), copyright_of(text)))
    return rows


def render(rows):
    def is_dart(c):
        return 'Dart project authors' in c

    def is_flutter(c):
        return 'Flutter Authors' in c or 'Flutter project authors' in c

    bsd3 = [r for r in rows if r[2] == 'BSD-3-Clause']
    groups = [
        ('Dart packages by the Dart project authors (BSD-3-Clause)',
         [r for r in bsd3 if is_dart(r[3])]),
        ('Flutter-team-authored Dart packages (BSD-3-Clause)',
         [r for r in bsd3 if is_flutter(r[3])]),
        ('Other BSD-3-Clause Dart packages',
         [r for r in bsd3 if not is_dart(r[3]) and not is_flutter(r[3])]),
        ('BSD-2-Clause Dart packages', [r for r in rows if r[2] == 'BSD-2-Clause']),
        ('MIT-licensed Dart packages', [r for r in rows if r[2] == 'MIT']),
        ('Apache-2.0-licensed Dart packages', [r for r in rows if r[2] == 'Apache-2.0']),
        ('MPL-2.0-licensed Dart packages', [r for r in rows if r[2] == 'MPL-2.0']),
        ('ISC-licensed Dart packages', [r for r in rows if r[2] == 'ISC']),
    ]

    bar = '-' * W
    out = []
    add = out.append
    add('crux-shared third-party attributions')
    add('=' * 36)
    add('')
    add(textwrap.fill(
        'crux-shared is licensed under the Apache License, Version 2.0 (see '
        'LICENSE). This file lists third-party software that ships in or with '
        'crux-shared source and binary distributions, together with the '
        'license terms under which each component is redistributed.', W))
    add('')
    add('Notes:')
    for note in [
        'crux-shared is a library workspace, not an application. Its packages '
        'are consumed as path dependencies by the four open-core products, '
        'each of which carries its own NOTICES covering what that product '
        'ships. This file covers the resolved closure of this workspace.',
        'Flutter SDK and Dart SDK packages provided by the Flutter toolchain '
        'are listed by name but not enumerated individually; they are '
        'governed by the Flutter and Dart project licenses.',
        'Versions are the RESOLVED versions from pubspec.lock, not the '
        'constraints in each package pubspec.yaml.',
        'Some entries are development-only (melos, very_good_analysis, test, '
        'fake_async, coverage and their closure). They are listed because '
        'they appear in the workspace lock; they are not redistributed in '
        'any product binary.',
        'This file is GENERATED. Run tool/gen-notices.py --write after any '
        'change that moves pubspec.lock. Do not hand-edit.',
    ]:
        add(textwrap.fill('- ' + note, W, subsequent_indent='  '))
        add('')

    n = 0
    for title, items in groups:
        if not items:
            continue
        n += 1
        add('')
        add(bar)
        add(f'{n}. {title}')
        add(bar)
        add('')
        add('Components and versions:')
        for name, version, _, _ in sorted(items):
            add(f'  - {name:<42} {version}')
        add('')
        add('License text (as distributed with these packages):')
        add('')
        rep = sorted(items)[0]
        for line in licence_text(rep[0], rep[1]).splitlines():
            add(('    ' + line).rstrip())

    sdk = sorted(r for r in rows if r[2] == 'SDK')
    if sdk:
        n += 1
        add('')
        add(bar)
        add(f'{n}. Flutter and Dart SDK packages')
        add(bar)
        add('')
        for name, _, _, _ in sdk:
            add(f'  - {name}')
        add('')
        add(textwrap.fill(
            'Provided by the Flutter SDK. Governed by the Flutter and Dart '
            'project licenses (BSD-3-Clause); see https://flutter.dev/ and '
            'https://dart.dev/.', W, initial_indent='  ',
            subsequent_indent='  '))

    n += 1
    add('')
    add(bar)
    add(f'{n}. Refresh procedure')
    add(bar)
    add('')
    add(textwrap.fill(
        'Regenerate after any dependency change that moves pubspec.lock:', W))
    add('')
    add('    python3 tool/gen-notices.py --write')
    add('')
    add(textwrap.fill(
        'The generator reads pubspec.lock, resolves each hosted package\'s '
        'license from the local pub cache, classifies it by matching the '
        'license text, and fails on any package it cannot classify or cannot '
        'find. A package that reaches UNKNOWN must be resolved by hand before '
        'release — it is a legal question, not a formatting one.', W))
    add('')
    return '\n'.join(out) + '\n'


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else '--summary'
    rows = collect()
    unknown = [r for r in rows if r[2] == 'UNKNOWN']

    if mode == '--summary':
        by = {}
        for name, version, spdx, _ in rows:
            by.setdefault(spdx, []).append(f'{name} {version}')
        for spdx in sorted(by):
            print(f'{spdx:16} {len(by[spdx])}')
        if unknown:
            print('\nUNKNOWN:', ', '.join(f'{r[0]}-{r[1]}' for r in unknown))
        return 0

    if unknown:
        print('[notices] cannot classify:', file=sys.stderr)
        for name, version, _, _ in unknown:
            print(f'  {name}-{version}', file=sys.stderr)
        print('[notices] resolve these by hand before release.', file=sys.stderr)
        return 1

    body = render(rows)
    if mode == '--write':
        open(OUT, 'w', encoding='utf-8').write(body)
        print(f'[notices] wrote NOTICES: {len(rows)} packages, '
              f'{len(body.splitlines())} lines')
        return 0
    if mode == '--check':
        current = open(OUT, encoding='utf-8').read() if os.path.exists(OUT) else ''
        if current != body:
            print('[notices] NOTICES is stale — run tool/gen-notices.py --write',
                  file=sys.stderr)
            return 1
        print(f'[notices] NOTICES is current ({len(rows)} packages)')
        return 0

    print(__doc__, file=sys.stderr)
    return 64


if __name__ == '__main__':
    sys.exit(main())
