#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

#
# Analyze the four open-core products against the crux-shared WORKING TREE.
#
#   tool/check-consumers.sh                 # all four products
#   tool/check-consumers.sh wavecrux        # one product
#
# Why this exists
# ---------------
# Every consumer declares bare `path:` dependencies into its `crux-shared`
# submodule, with no version constraint. The submodule SHA is therefore the
# entire compatibility contract, and nothing on a developer's machine notices
# when a change here removes or re-signatures a symbol that eight repos use.
# This script is the local form of the `consumers` job in
# `.github/workflows/consumers.yml`. Run it before bumping a product's submodule pin.
#
# How it works
# ------------
# It does NOT touch any product's git state — no submodule update, no checkout.
# It writes a temporary `pubspec_overrides.yaml` in the product root that
# redirects every `crux_*` path dependency at this working tree, runs the
# product's normal prepare-and-analyze sequence, then removes the override file.
# The override is removed on exit even if analysis fails or you interrupt it.
#
# Requirements: each product's open-core checkout has been `flutter pub
# get`-able before, and sits under a products root — `$CRUX_PRODUCTS_ROOT` when
# set, otherwise the directory that holds crux-shared. Two places are tried, in
# this order:
#
#   <root>/<product>      a plain clone beside crux-shared
#   <root>/*/<product>    an open core one directory down, e.g. a checkout
#                         that holds the open core as a submodule
#
# A product found in neither, or found in more than one directory one level
# down, is reported and fails the run.
set -uo pipefail

# `pwd -W` where it exists (Git Bash / MSYS on Windows) yields a NATIVE path,
# `C:/Users/...`, instead of the MSYS form `/c/Users/...`. That matters here and
# only here: these values are written verbatim into pubspec_overrides.yaml as
# `path:` entries, and `pub` is a native Windows binary that cannot resolve the
# MSYS form. Left as plain `pwd`, every product fails with "depends on crux_x
# from path which doesn't exist" while the package is sitting right there — so
# the one gate that catches a breaking crux-shared change before the pin bump
# could never run on Windows at all. Plain `pwd` everywhere else.
_abs_native() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

SHARED_ROOT="$(_abs_native "$(dirname "${BASH_SOURCE[0]}")/..")"
PROJECTS_ROOT="$(_abs_native "${CRUX_PRODUCTS_ROOT:-$SHARED_ROOT/..}")"

ALL_PRODUCTS=(wavecrux netcrux lintcrux simcrux)
if [[ $# -gt 0 ]]; then
  PRODUCTS=("$@")
else
  PRODUCTS=("${ALL_PRODUCTS[@]}")
fi

# Product-specific preparation beyond pub get / build_runner / gen-l10n.
# Mirrors the per-product steps in each product's own .github/workflows/ci.yml.
extra_prep() {
  case "$1" in
    wavecrux)
      dart run tool/generate_web_fixture_bundle.dart
      dart pub get --directory tool/wavecrux_ctl
      ;;
    *) : ;;
  esac
}

OVERRIDE_FILE=''
cleanup() {
  if [[ -n "$OVERRIDE_FILE" && -f "$OVERRIDE_FILE" ]]; then
    rm -f "$OVERRIDE_FILE"
    echo "    (removed temporary $OVERRIDE_FILE)"
  fi
}
trap cleanup EXIT INT TERM

write_overrides() {
  local product_dir="$1"
  OVERRIDE_FILE="$product_dir/pubspec_overrides.yaml"

  if [[ -f "$OVERRIDE_FILE" ]]; then
    echo "!! $OVERRIDE_FILE already exists — refusing to clobber it."
    echo "   Move it aside and re-run."
    OVERRIDE_FILE=''
    return 1
  fi

  {
    echo "# TEMPORARY — written by crux-shared/tool/check-consumers.sh."
    echo "# Redirects the crux_* path deps at the crux-shared working tree."
    echo "# If this file survived a crash, delete it."
    echo "dependency_overrides:"
    for pkg_dir in "$SHARED_ROOT"/packages/*/; do
      local pkg
      pkg="$(basename "$pkg_dir")"
      # Only override packages this product actually depends on; overriding a
      # package the product does not use is harmless but noisy in pub output.
      if grep -q "crux-shared/packages/$pkg\b" "$product_dir/pubspec.yaml"; then
        echo "  $pkg:"
        echo "    path: $pkg_dir"
      fi
    done
  } > "$OVERRIDE_FILE"
}

# The product's open-core checkout, in the first place that holds one (see the
# header), or nothing. One level down must be unambiguous: two candidates there
# would make the result depend on glob order.
find_product_dir() {
  local product="$1" candidate
  if [[ -f "$PROJECTS_ROOT/$product/pubspec.yaml" ]]; then
    echo "$PROJECTS_ROOT/$product"
    return 0
  fi
  local found=()
  for candidate in "$PROJECTS_ROOT"/*/"$product"; do
    [[ -f "$candidate/pubspec.yaml" ]] && found+=("$candidate")
  done
  if [[ ${#found[@]} -eq 1 ]]; then
    echo "${found[0]}"
    return 0
  fi
  if [[ ${#found[@]} -gt 1 ]]; then
    echo "!! $product is ambiguous one level under $PROJECTS_ROOT: ${found[*]}" >&2
  fi
  return 1
}

overall=0
for product in "${PRODUCTS[@]}"; do
  echo ""
  echo "══════════════════════════════════════════════════════════════════════"
  if ! product_dir="$(find_product_dir "$product")"; then
    echo "  $product"
    echo "══════════════════════════════════════════════════════════════════════"
    echo "!! not found at $PROJECTS_ROOT/$product or one directory below it"
    echo "   — skipped (clone it, set CRUX_PRODUCTS_ROOT, or pass an explicit"
    echo "   product list)"
    overall=1
    continue
  fi
  echo "  $product   ($product_dir)"
  echo "══════════════════════════════════════════════════════════════════════"

  if ! write_overrides "$product_dir"; then
    overall=1
    continue
  fi

  (
    cd "$product_dir" || exit 1
    set -e
    echo "--> flutter pub get"
    flutter pub get
    # Not every product uses codegen -- SimCrux declares no build_runner
    # dev dependency, and `dart run build_runner` there fails with "Could not
    # find package `build_runner`", which reads as a consumer breakage when it
    # is only a missing optional step. Gate on the declaration, not on hope.
    if grep -qE '^  build_runner:' pubspec.yaml; then
      echo "--> build_runner"
      dart run build_runner build --delete-conflicting-outputs
    else
      echo "--> build_runner (skipped: not a dev dependency)"
    fi
    echo "--> gen-l10n"
    flutter gen-l10n
    extra_prep "$product"
    echo "--> flutter analyze"
    flutter analyze --fatal-infos --fatal-warnings
  )
  status=$?

  cleanup
  OVERRIDE_FILE=''

  # Restore the product's own resolution so the developer's tree is not left
  # resolved against the working copy of crux-shared.
  (cd "$product_dir" && flutter pub get >/dev/null 2>&1) || true

  if [[ $status -ne 0 ]]; then
    echo "✗ $product FAILED against the crux-shared working tree"
    overall=1
  else
    echo "✓ $product analyzes clean against the crux-shared working tree"
  fi
done

echo ""
if [[ $overall -eq 0 ]]; then
  echo "All checked consumers analyze clean against this crux-shared tree."
else
  echo "At least one consumer failed. A path: dep has no version constraint —"
  echo "the submodule SHA is the whole contract — so this is the only signal"
  echo "you get before the pin bump breaks a product's CI."
fi
exit $overall
