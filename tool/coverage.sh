#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Per-package coverage gate for the crux-shared workspace.
#
# Every repository in the suite gates coverage. The four open-core repos run
# tool/coverage.sh against a single lib/ and a single floor. crux-shared cannot:
# it is a melos workspace of many packages, and `flutter test --coverage` at
# the root produces no lcov at all. The choice is a melos-driven aggregate or a
# gate per package, and this is the second.
#
# ## This gates per package, and the measurement is why
#
# Measured 2026-08-18, the spread across the workspace is 45.2% to 100%:
#
#     crux_netlist      45.2      crux_projects_ui  66.1      crux_secrets  67.7
#     crux_toolbar      70.0      crux_io           72.1      ...
#     crux_status_bar  100.0      crux_app_info    100.0      crux_heatmap 100.0
#
# An aggregate would land near 90% and would be true. It would also mean
# `crux_netlist` at 45.2% is invisible — one package can lose half its coverage
# and the number every other package carries absorbs it. That is the failure
# this gate exists to prevent, so an aggregate is the wrong instrument here even
# though it is the one every other repo in the suite uses.
#
# One global floor is equally wrong in the other direction: set at 45 to admit
# crux_netlist it gates nothing, and set anywhere useful it fails on day one.
#
# So each package ratchets against **itself**. FLOORS below is seeded from the
# measured figure minus two points, the same convention the product gates use.
# Raise an entry when its package improves. Never lower one — a package whose
# coverage fell is the signal, and editing the floor to match is deleting it.
#
# ## Every package is listed, and the script checks that it is
#
# The loop below only visits packages named in FLOORS, so a package added to
# `packages/` without a floor used to be silently ungated — six were. A full
# run now fails first if the FLOORS keys and the `packages/` directories
# disagree in either direction. A package with no executable lines at all (an
# interface and an enum) is listed as `none`; it is still run, and fails the
# moment it grows code without a floor.
#
# Usage:
#   tool/coverage.sh                 # gate every package
#   tool/coverage.sh crux_netlist    # gate one package
set -uo pipefail

# package:floor, seeded 2026-08-18 from measured minus two points.
#
# crux_netlist was seeded low, at 43, and that was not a failure: it had ZERO
# tests before the gate was written and 23 after, and 45.2% is where that
# landed, recorded honestly rather than flattered by an aggregate. It was the
# first package raised: once its hierarchy navigation and model equality were
# tested against hostile documents it measured 98.9%, and its floor is now
# measured minus two like the rest.
#
# crux_a11y, crux_audit, crux_policy, crux_signing and crux_sqlite were added
# later and seeded the same way, from measured minus two points.
# crux_shortcut_action is `none`: two declarations, zero executable lines.
#
# crux_projects was re-seeded (measured minus two) when the persistent
# registry left the package for the Pro overlays' private shared code. Nothing
# retained lost a line of coverage; the file that left was the best-covered
# one, so the package's ratio moved with the denominator. Re-seeding after a
# removal is not the lowering the rule above forbids — that rule is about a
# figure that fell with the code held constant.
FLOORS="
crux_a11y:94
crux_about_dialog:95
crux_app_info:98
crux_async:98
crux_audit:98
crux_command_palette:92
crux_cxp:85
crux_cxp_ui:90
crux_dock:95
crux_eula:83
crux_file_watcher:82
crux_heatmap:98
crux_ide_layout:94
crux_io:70
crux_issue_reporter:87
crux_keybindings:95
crux_license:94
crux_linux_integration:81
crux_menu_bar:94
crux_netlist:96
crux_policy:94
crux_project:87
crux_projects:84
crux_projects_ui:89
crux_secrets:94
crux_settings:97
crux_settings_ui:97
crux_shortcut_action:none
crux_signing:98
crux_sqlite:91
crux_stats_strip:90
crux_status_bar:98
crux_telemetry:92
crux_theme:92
crux_toolbar:71
crux_updates:96
crux_window_chrome:78
crux_workspace:87
crux_yosys:88
"

only="${1:-}"
failed=0
checked=0
empty=0

# FLOORS and packages/ must name the same set, in both directions. A full run
# checks this before measuring anything; a one-package run is a local
# convenience and skips it.
if [[ -z "$only" ]]; then
  listed="$(sed -n 's/^\([A-Za-z0-9_]*\):.*$/\1/p' <<< "$FLOORS" | LC_ALL=C sort)"
  present="$(for d in packages/*/; do
    [[ -f "$d/pubspec.yaml" ]] && basename "$d"
  done | LC_ALL=C sort)"
  unlisted="$(LC_ALL=C comm -13 <(echo "$listed") <(echo "$present"))"
  phantom="$(LC_ALL=C comm -23 <(echo "$listed") <(echo "$present"))"
  for pkg in $unlisted; do
    echo "::error::$pkg is in packages/ but not in FLOORS — measure it and seed a floor (measured minus two), or 'none' if it has no executable lines"
  done
  for pkg in $phantom; do
    echo "::error::FLOORS names $pkg, which is not a directory in packages/"
  done
  if [[ -n "$unlisted$phantom" ]]; then
    echo "::error::FLOORS and packages/ disagree — an unlisted package is never gated"
    exit 1
  fi
fi

while IFS=: read -r pkg floor; do
  [[ -z "$pkg" ]] && continue
  [[ -n "$only" && "$pkg" != "$only" ]] && continue
  dir="packages/$pkg"
  if [[ ! -d "$dir/test" ]]; then
    # A listed package with no test/ directory is a package this gate cannot
    # measure. It used to be noted in the summary line and skipped, with the
    # run still green; the melos test script skipped it the same way, so a
    # package that lost its tests dropped out of both gates at once.
    echo "::error::$pkg has no test/ directory — the gate cannot measure it"
    failed=1
    continue
  fi

  # A stale lcov.info from an earlier run must not stand in for this one.
  rm -f "$dir/coverage/lcov.info"
  ( cd "$dir" && flutter test --coverage >/dev/null 2>&1 )
  if [[ ! -f "$dir/coverage/lcov.info" ]]; then
    # A package listed here that stops producing coverage is a hole in the
    # gate, not a package to skip quietly.
    echo "::error::$pkg produced no lcov.info — the gate cannot see it"
    failed=1
    continue
  fi

  if [[ "$floor" == "none" ]]; then
    # Listed as having nothing to cover. Hold it to that: the first executable
    # line it gains needs a real floor.
    lines="$(grep -h '^LF:' "$dir/coverage/lcov.info" | awk -F: '{ s += $2 } END { print s + 0 }')"
    if [[ "$lines" -gt 0 ]]; then
      echo "::error::$pkg is listed as 'none' but now has $lines executable lines — seed a floor"
      failed=1
    else
      empty=$((empty + 1))
      printf '  %-24s %7s  (no executable lines)\n' "$pkg" "-"
    fi
    continue
  fi

  # `--ignore-errors empty`: lcov 2.5 exits non-zero on "function coverage
  # enabled but no corresponding coverpoints found", which is benign for Dart
  # line coverage. The product script documents the same trap.
  pct="$(lcov --summary "$dir/coverage/lcov.info" --ignore-errors empty 2>/dev/null \
        | grep -iE 'lines' | grep -oE '[0-9]+(\.[0-9]+)?%' | head -1 | tr -d '%')"
  if [[ -z "$pct" ]]; then
    echo "::error::$pkg — could not parse a coverage percentage"
    failed=1
    continue
  fi

  checked=$((checked + 1))
  if awk -v p="$pct" -v m="$floor" 'BEGIN { exit !((p + 0) >= (m + 0)) }'; then
    printf '  %-24s %6s%%  (floor %s)\n' "$pkg" "$pct" "$floor"
  else
    printf '  %-24s %6s%%  (floor %s)  BELOW FLOOR\n' "$pkg" "$pct" "$floor"
    echo "::error::$pkg coverage ${pct}% is below its floor ${floor}%"
    failed=1
  fi
done <<< "$FLOORS"

echo "──────────────────────────────────────────────"
echo "$checked packages gated, $empty with no executable lines"

if [[ $failed -ne 0 ]]; then
  echo "::error::one or more packages fell below their floor"
  exit 1
fi
echo "every package is at or above its floor"
