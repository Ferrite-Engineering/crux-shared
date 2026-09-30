#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the `crux-policy` administrator CLI.
#
# The ONE build of it: `.github/workflows/release-crux-policy.yml` calls this
# script rather than repeating the command, and `ci.yml` runs it on every push,
# so a release can never be the first time the binary was compiled — and a
# local build is the same build the release makes.
#
# Why `dart build cli` and not `dart compile exe`: `dart compile` refuses to
# run when any package in the resolution declares a native build hook, and
# resolution here is the whole workspace, which contains Flutter plugins this
# package never touches. `dart build cli` is the supported replacement.
#
# What it emits is ONE self-contained executable: the bundle's `lib/` is empty,
# because this package is pure Dart with no native assets and is guarded to
# stay that way. The file `dart build cli` writes is named after the entry
# point (`crux_policy`); every page and example types `crux-policy`, so the
# script also leaves a copy under that name, which is what ships.
#
# Usage:
#   tool/build_cli.sh [output-dir] [extra `dart build cli` flags...]
#
#   tool/build_cli.sh                                    # host platform
#   tool/build_cli.sh build/cli/linux-arm64 \
#     --target-os linux --target-arch arm64              # cross-compile
#
# Cross-compiling to Linux works from any host. macOS and Windows targets
# must be built on their own OS: `dart build cli` refuses
# `--target-os macos --target-arch x64` from an arm64 Mac outright.
#
# The shippable file is:
#   <output-dir>/crux-policy        (crux-policy.exe for a Windows build)
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-build/cli}"
shift || true

echo "==> dart build cli -t bin/crux_policy.dart -o ${OUT_DIR} $*"
dart build cli -t bin/crux_policy.dart -o "${OUT_DIR}" "$@"

# A Windows executable, whether this is a Windows host or a Windows target.
EXE=""
if [[ -f "${OUT_DIR}/bundle/bin/crux_policy.exe" ]]; then
  EXE=".exe"
fi
BUILT="${OUT_DIR}/bundle/bin/crux_policy${EXE}"
SHIPPED="${OUT_DIR}/crux-policy${EXE}"

if [[ ! -f "${BUILT}" ]]; then
  echo "error: expected executable at ${BUILT}" >&2
  exit 1
fi

# Self-contained is a property, not an assumption: a native asset appearing in
# lib/ would mean the single file we ship no longer runs on its own.
if [[ -d "${OUT_DIR}/bundle/lib" ]] && [[ -n "$(ls -A "${OUT_DIR}/bundle/lib")" ]]; then
  echo "error: ${OUT_DIR}/bundle/lib is not empty — crux-policy would need it beside the binary:" >&2
  ls -l "${OUT_DIR}/bundle/lib" >&2
  exit 1
fi

cp "${BUILT}" "${SHIPPED}"
chmod +x "${SHIPPED}"

# Smoke-test a native build, always. Skipped ONLY when a target was named on
# the command line — deciding by "does it run" would let a broken native
# binary skip its own test. A cross-compiled binary is exercised by the
# release workflow, under emulation.
if [[ " $* " == *" --target-os "* || " $* " == *" --target-arch "* ]]; then
  echo "==> cross-compiled (--target-*) — smoke test left to the caller"
else
  echo "==> smoke test"
  "${SHIPPED}" --version
  "${SHIPPED}" --help > /dev/null
fi

echo "==> built ${SHIPPED}"
