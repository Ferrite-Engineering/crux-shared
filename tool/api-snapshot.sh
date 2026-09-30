#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

#
# Public-API golden snapshots for every crux-shared package.
#
#   tool/api-snapshot.sh --check    # fail if any package's public API drifted
#   tool/api-snapshot.sh --write    # regenerate the goldens under api/
#
# The goldens under api/*.api.txt are the reviewable record of the substrate
# eight repos depend on. --check runs in CI; --write is the single command a
# developer runs after an intentional API change, committing the diff alongside
# the code change.
#
# Requires the workspace to be bootstrapped (`melos bootstrap`) so the packages
# resolve; the tool itself resolves its own dependencies on first run.
set -euo pipefail

MODE="${1:---check}"
if [[ "$MODE" != "--check" && "$MODE" != "--write" ]]; then
  echo "usage: tool/api-snapshot.sh [--check|--write]" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="$REPO_ROOT/tool/api_snapshot"

if [[ ! -f "$TOOL_DIR/.dart_tool/package_config.json" ]]; then
  echo "==> Resolving api_snapshot tool dependencies"
  (cd "$TOOL_DIR" && dart pub get)
fi

(cd "$TOOL_DIR" && dart run bin/api_snapshot.dart "$MODE")
