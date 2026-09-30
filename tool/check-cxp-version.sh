#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

#
# Semver discipline guard for `crux_cxp` only.
#
#   tool/check-cxp-version.sh <base-ref>
#   tool/check-cxp-version.sh --since-last-green <owner/repo> <fallback-base>
#
# Repo policy (CLAUDE.md § "Versioning contract"): for every other package the
# submodule SHA is the compatibility contract and `version:` is informational.
# `crux_cxp` is the exception — it is slated to be published to pub.dev at the
# open-core flip, at which point its `version:` becomes a real
# constraint that real solvers resolve against. Discipline has to exist before
# the first publish, not after.
#
# The guard: if `packages/crux_cxp/lib/**` changed relative to <base-ref>, then
# `packages/crux_cxp/pubspec.yaml`'s `version:` must have changed too, and the
# CHANGELOG must carry a section for the new version.
#
# It deliberately does NOT try to classify the change as major/minor/patch —
# that is a judgement call, and a guard that guesses wrong trains people to
# ignore it. It only enforces that the version moved and was written down.
#
# ## Which base, on `main`
#
# A push to `main` must NOT be checked against the push's own base
# (`github.event.before`) alone. ci.yml cancels a superseded push run, so when
# pushes arrive faster than CI finishes, the run that would have seen a
# `crux_cxp/lib` change is cancelled, and the next run's base already contains
# it: the guard never looks at that commit, and main goes green. Six library
# changes went through exactly that way without a version bump. A red guard is
# "cured" the same way, by any later push that does not touch the library.
#
# So `--since-last-green` diffs against the last commit whose ci.yml run on
# `main` succeeded **for a push**. Push runs are the only ones that execute
# this guard, so every commit after that SHA is one the guard has not yet
# passed. Dispatched and scheduled runs skip the guard, and counting their
# green would certify commits it never saw. If the query fails, finds nothing,
# or names a commit that is not an ancestor of HEAD (a rewritten history), it
# falls back to <fallback-base> and says so; an all-zero fallback (a branch's
# first push) with no green run to use skips the guard.
set -uo pipefail

PKG="packages/crux_cxp"

# Indirection so the branching logic can be exercised with a stubbed `git`
# and `gh`; tool/check-cxp-version-test.sh does both.
git_cmd() { git "$@"; }
gh_cmd() { gh "$@"; }

# The head SHA of the last successful push run of ci.yml on main, or nothing.
last_green_push_sha() {
  gh_cmd api "repos/$1/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=1" \
    --jq '.workflow_runs[0].head_sha // ""' 2>/dev/null || true
}

if [[ "${1:-}" == "--since-last-green" ]]; then
  repo="${2:?--since-last-green needs <owner/repo>}"
  fallback="${3:?--since-last-green needs <fallback-base>}"
  green="$(last_green_push_sha "$repo")"
  if [[ -n "$green" ]] && git_cmd merge-base --is-ancestor "$green" HEAD 2>/dev/null; then
    echo "Base: $green, the last commit whose CI push run on main passed."
    BASE_REF="$green"
  else
    if [[ -z "$green" ]]; then
      echo "No successful CI push run on main found; falling back to $fallback."
    else
      echo "Last green $green is not an ancestor of HEAD; falling back to $fallback."
    fi
    if [[ "$fallback" =~ ^0+$ ]]; then
      echo "No base commit for this push — guard skipped."
      exit 0
    fi
    BASE_REF="$fallback"
  fi
else
  BASE_REF="${1:-origin/main}"
fi

changed_lib="$(git_cmd diff --name-only "$BASE_REF"...HEAD -- "$PKG/lib" 2>/dev/null)"
if [[ -z "$changed_lib" ]]; then
  echo "crux_cxp/lib unchanged since $BASE_REF — version guard not applicable."
  exit 0
fi

echo "crux_cxp/lib changed since $BASE_REF:"
echo "$changed_lib" | sed 's/^/    /'

base_version="$(git_cmd show "$BASE_REF:$PKG/pubspec.yaml" 2>/dev/null \
  | grep -m1 '^version:' | awk '{print $2}')"
head_version="$(grep -m1 '^version:' "$PKG/pubspec.yaml" | awk '{print $2}')"

if [[ -z "$head_version" ]]; then
  echo "ERROR: $PKG/pubspec.yaml has no version: field."
  exit 1
fi

if [[ "$base_version" == "$head_version" ]]; then
  cat <<EOF

ERROR: crux_cxp's library sources changed but its version is still
       $head_version.

crux_cxp is the one package in this workspace with real semver obligations —
it is published to pub.dev at the open-core flip, where the version string
stops being decorative and starts being solved against. Bump
$PKG/pubspec.yaml and add the matching section to
$PKG/CHANGELOG.md.

Note the package version tracks the DART API, independently of
cxpProtocolVersion, which tracks the wire format. See the "Versioning policy"
section at the top of $PKG/CHANGELOG.md.
EOF
  exit 1
fi

if ! grep -q "^## ${head_version}\b" "$PKG/CHANGELOG.md"; then
  echo ""
  echo "ERROR: version moved to $head_version but $PKG/CHANGELOG.md has no"
  echo "       '## $head_version' section. A published package's changelog is"
  echo "       part of its public interface."
  exit 1
fi

echo "OK: crux_cxp $base_version -> $head_version, changelog section present."
exit 0
