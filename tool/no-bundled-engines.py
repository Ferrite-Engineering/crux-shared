#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Refuse to let an engine binary enter a distributed build.

    tool/no-bundled-engines.py --check [REPO...]

The Crux products drive external EDA engines -- Yosys, GHDL, Verilator,
Verible, Slang, Svlint, Icarus Verilog, cocotb -- by spawning them as separate
operating-system processes. Nothing is linked, and **no engine binary is
distributed**. That is what keeps Apache-2.0 product code cleanly separated
from GHDL's and Icarus's GPL-2.0 terms: there is no copyleft binary in the
distribution, so there is no obligation to convey or offer its source.

The risk this guard exists for is that the *infrastructure* for bundling
already exists -- a `tool/bundled_engines.yaml` manifest, a fetch workflow,
and a `<PRODUCT>_BUNDLED_BIN_DIR` resolution path. Switching it on is a small
edit, and a small edit is exactly how a licence analysis gets invalidated
without anyone revisiting it. Declaring an engine binary as a Flutter asset
would ship it inside the application bundle.

So: bundling must remain a deliberate act. If this guard fails, the correct
response is NOT to relax it. It is to work through the distribution
obligations for the specific engine being bundled -- for GPL engines, hosting
or offering the corresponding source of the exact binary shipped, per release
-- and only then to change this file with that analysis recorded.

Precedent for the shape of this check: NetCrux shipped 0.1.0 with a vendored
elkjs and no copy of the EPL Agreement, because the text landed one day after
the binary was built and nothing checked. `bundled_license_assets_test.dart`
was written so that could not recur. This is the same idea, pointed at the
obligation that is expensive rather than merely embarrassing.
"""
import os
import re
import subprocess
import sys

# Executable/library names that would indicate a bundled engine.
ENGINE_NAMES = (
    'yosys', 'ghdl', 'verilator', 'verible', 'slang', 'svlint',
    'iverilog', 'vvp', 'cocotb', 'ghdl-yosys-plugin',
)

# Extensions that carry machine code.
BINARY_EXT = ('.so', '.dylib', '.dll', '.a', '.lib', '.exe', '')

# Asset lines in pubspec.yaml that would place a file inside the app bundle.
ASSET_LINE = re.compile(r'^\s*-\s+(\S+)\s*$')


def tracked(repo):
    out = subprocess.run(['git', '-C', repo, 'ls-files'],
                         capture_output=True, text=True, check=True).stdout
    return [l for l in out.splitlines() if l.strip()]


def looks_like_engine_binary(path):
    base = os.path.basename(path).lower()
    stem, ext = os.path.splitext(base)
    if ext not in BINARY_EXT:
        return False
    for name in ENGINE_NAMES:
        if stem == name or stem.startswith(name + '-') or stem.startswith(name + '_'):
            return True
    return False


def declared_assets(repo):
    """Asset paths declared in pubspec.yaml's flutter: assets: block."""
    p = os.path.join(repo, 'pubspec.yaml')
    if not os.path.exists(p):
        return []
    assets, in_assets = [], False
    for line in open(p, encoding='utf-8'):
        if re.match(r'^\s*assets:\s*$', line):
            in_assets = True
            continue
        if in_assets:
            m = ASSET_LINE.match(line)
            if m:
                assets.append(m.group(1))
                continue
            if line.strip() and not line.startswith((' ', '\t')):
                in_assets = False
            elif line.strip() and not line.lstrip().startswith('#'):
                in_assets = False
    return assets


def check(repo):
    name = os.path.basename(os.path.abspath(repo))
    problems = []

    for rel in tracked(repo):
        if looks_like_engine_binary(rel):
            problems.append(f'engine binary committed to the repo: {rel}')

    for asset in declared_assets(repo):
        low = asset.lower()
        if any(n in low for n in ENGINE_NAMES):
            problems.append(
                f'pubspec.yaml declares an engine path as a Flutter asset, '
                f'which ships it inside the application bundle: {asset}')
        if any(low.rstrip('/').endswith(e) for e in ('.so', '.dylib', '.dll', '.exe')):
            problems.append(
                f'pubspec.yaml declares a native binary as a Flutter asset: {asset}')

    if problems:
        print(f'{name}: {len(problems)} problem(s)', file=sys.stderr)
        for p in problems:
            print(f'    {p}', file=sys.stderr)
        return 1
    print(f'{name}: no engine binary is committed or declared as an asset')
    return 0


def main():
    repos = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not repos:
        repos = [os.path.dirname(os.path.dirname(os.path.abspath(__file__)))]
    failed = sum(check(r) for r in repos)
    if failed:
        print('\nBundling an engine changes the distribution obligations, and for '
              'the GPL engines (GHDL, Icarus Verilog) means conveying or offering '
              'the corresponding source of the exact binary shipped. Do not relax '
              'this guard to make a build pass.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
