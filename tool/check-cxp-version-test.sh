#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Tests for tool/check-cxp-version.sh, run by CI before the guard itself.
#
#   tool/check-cxp-version-test.sh
#
# Builds a throwaway repository with a `packages/crux_cxp` in it and replays
# the history that got six library changes past the guard: a green commit, a
# library change with no version bump whose CI run was cancelled, then an
# unrelated push whose base already contains the change. `gh` is a stub on
# PATH that answers the "last green push run" query from $FAKE_GH_SHA (or
# fails when it is `fail`); git is real.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-cxp-version.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${FAKE_GH_SHA:-}" == "fail" ]] && exit 1
echo "${FAKE_GH_SHA:-}"
STUB
chmod +x "$work/bin/gh"

repo="$work/repo"
pkg="$repo/packages/crux_cxp"
mkdir -p "$pkg/lib"
g() { git -C "$repo" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null -c commit.gpgsign=false "$@"; }
g init -q
printf 'name: crux_cxp\nversion: 0.7.0\n' > "$pkg/pubspec.yaml"
printf '# Changelog\n\n## 0.7.0\n' > "$pkg/CHANGELOG.md"
echo 'int a() => 1;' > "$pkg/lib/a.dart"
echo 'readme' > "$repo/README.md"
g add -A
g commit -q -m green
green="$(g rev-parse HEAD)"

echo 'int a() => 2;' > "$pkg/lib/a.dart"
g commit -q -am "library change, no bump; its CI run was cancelled"
unbumped="$(g rev-parse HEAD)"

echo 'readme 2' > "$repo/README.md"
g commit -q -am "unrelated push; its base already contains the change"

g checkout -q -b elsewhere "$green"
echo 'elsewhere' > "$repo/README.md"
g commit -q -am "a commit that is not an ancestor of main"
stray="$(g rev-parse HEAD)"
g checkout -q -

failures=0
# expect <exit code> <description> <FAKE_GH_SHA> <guard args...>
expect() {
  local want="$1" what="$2" fake="$3"
  shift 3
  local out got
  out="$(cd "$repo" && PATH="$work/bin:$PATH" FAKE_GH_SHA="$fake" bash "$SCRIPT" "$@" 2>&1)"
  got=$?
  if [[ "$got" == "$want" ]]; then
    echo "ok    $what (exit $got)"
  else
    echo "FAIL  $what: expected exit $want, got $got"
    echo "$out" | sed 's/^/      /'
    failures=$((failures + 1))
  fi
}

# The hole, as it was: checked against the push's own base, the unbumped
# change is invisible.
expect 0 "a push-base diff alone misses the change" "" "$unbumped"

# The fix: against the last green push run, it is seen and refused.
expect 1 "since the last green, the unbumped change fails" "$green" \
  --since-last-green o/r "$unbumped"

# Degrades to the push base, loudly, when the last green cannot be used.
expect 0 "an unreachable API falls back to the push base" fail \
  --since-last-green o/r "$unbumped"
expect 0 "no green run yet falls back to the push base" "" \
  --since-last-green o/r "$unbumped"
expect 0 "a non-ancestor green falls back to the push base" "$stray" \
  --since-last-green o/r "$unbumped"
expect 0 "an all-zero fallback with no green skips" "" \
  --since-last-green o/r 0000000000000000000000000000000000000000

# A bump without its changelog section still fails; with it, passes.
sed -i.bak 's/^version: 0.7.0$/version: 0.7.1/' "$pkg/pubspec.yaml"
rm -f "$pkg/pubspec.yaml.bak"
g commit -q -am "bump, no changelog"
expect 1 "a bump without a changelog section fails" "$green" \
  --since-last-green o/r "$unbumped"
printf '\n## 0.7.1\n' >> "$pkg/CHANGELOG.md"
g commit -q -am "changelog"
expect 0 "a bump with its changelog section passes" "$green" \
  --since-last-green o/r "$unbumped"

if [[ $failures -ne 0 ]]; then
  echo "$failures check-cxp-version test(s) failed"
  exit 1
fi
echo "all check-cxp-version tests passed"
