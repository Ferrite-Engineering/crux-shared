#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Regenerates the MCP definition snapshots of the suite's servers, which
# packages/crux_mcp/test/suite/suite_budget_test.dart holds to their ceilings:
# 2,000 characters a tool, 4,000 a server with its instructions, and 16,000
# for every server together.
#
#   tool/mcp-suite-snapshot.sh [--out DIR] [--args NAME "ARGS"]...
#                              [--redact NAME WORD]... NAME=BINARY...
#
# NAME=BINARY   a server: the snapshot is <DIR>/<NAME>.json (lower case
#               letters, digits, - and _). The snapshot names the server and
#               holds its definitions only: no path, no version.
# --args        the arguments that start BINARY's MCP server, before --root
#               (space-separated; default "mcp").
# --redact      replace WORD in NAME's snapshot, in any letter case, with as
#               many x characters: the counts stay exact.
# --out         default packages/crux_mcp/test/suite/snapshots
#
# Each binary is started with --root at an empty temporary directory and CI
# set, asked initialize and tools/list, and closed; nothing else runs. Check
# the result with
#
#   (cd packages/crux_mcp && dart test test/suite/)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$REPO_ROOT/packages/crux_mcp"
out="$PKG/test/suite/snapshots"
# Parallel arrays rather than associative ones: macOS ships bash 3.2.
names=()
binaries=()
option_names=()
option_kinds=()
option_values=()

usage() {
  sed -n '5,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# The value given to option $2 (args or redact) for server $1, or $3.
option_for() {
  local i
  for ((i = ${#option_names[@]} - 1; i >= 0; i--)); do
    if [[ "${option_names[$i]}" == "$1" && "${option_kinds[$i]}" == "$2" ]]; then
      printf '%s' "${option_values[$i]}"
      return
    fi
  done
  printf '%s' "$3"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --out) out="$2"; shift 2 ;;
    --args|--redact)
      if [[ $# -lt 3 ]]; then
        echo "error: $1 takes a server name and a value" >&2
        exit 2
      fi
      option_names+=("$2")
      option_kinds+=("${1#--}")
      option_values+=("$3")
      shift 3
      ;;
    *=*)
      name="${1%%=*}"
      binary="${1#*=}"
      if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        echo "error: server name '$name': lower case letters, digits, - and _" >&2
        exit 2
      fi
      if [[ ! -x "$binary" ]]; then
        echo "error: $name: '$binary' is not an executable" >&2
        exit 2
      fi
      names+=("$name")
      binaries+=("$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")")
      shift
      ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ${#names[@]} -eq 0 ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$out"
out="$(cd "$out" && pwd)"

spec=()
for ((i = 0; i < ${#names[@]}; i++)); do
  name="${names[$i]}"
  spec+=("$name" "${binaries[$i]}" "$(option_for "$name" args mcp)")
  word="$(option_for "$name" redact '')"
  if [[ -n "$word" ]]; then
    spec+=(--redact "$word")
  fi
done

cd "$PKG"
dart run test/suite/snapshot_main.dart "$out" "${spec[@]}"
