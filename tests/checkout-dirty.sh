#!/bin/bash
# tests/checkout-dirty.sh — fleet_checkout recovers a checkout left dirty on a branch.
#
# A run that dies mid-ticket leaves the persistent checkout on its feature
# branch with tracked files modified (build steps regenerate them). Before the
# fix, `git checkout main` refused ("would be overwritten") and every later run
# aborted at checkout, silently, for weeks. fleet_checkout must land on a clean
# main at origin/main regardless.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMP="$(mktemp -d -t fleet-checkout-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --global init.defaultBranch main
git config --global user.email t@example.com
git config --global user.name test

# origin: main has gen.txt = "main"; feat has gen.txt = "feat"
git init -q "$TMP/seed"
( cd "$TMP/seed"
  echo main > gen.txt; git add gen.txt; git commit -qm main
  git checkout -qb feat; echo feat > gen.txt; git commit -qam feat; git checkout -q main )
git clone -q --bare "$TMP/seed" "$TMP/origin.git"

source "$REPO_ROOT/lib/common.sh"
SLUG=checkouttest
CACHE_DIR="$TMP/cache"
REPO_URL="file://$TMP/origin.git"
GIT_AUTHOR_EMAIL=agent@example.com
GIT_AUTHOR_NAME=agent

fleet_checkout checkout >/dev/null
cd "$CACHE_DIR/checkout"
# simulate a run that died on its branch with a regenerated tracked file
git fetch -q origin feat:feat && git checkout -q feat
echo regenerated > gen.txt
echo stray > untracked.txt
cd "$TMP"

fleet_checkout checkout >/dev/null
cd "$CACHE_DIR/checkout"
fail=0
[ "$(git branch --show-current)" = "main" ] || { echo "FAIL: not on main"; fail=1; }
[ "$(cat gen.txt)" = "main" ] || { echo "FAIL: gen.txt not reset to main"; fail=1; }
[ -z "$(git status --porcelain)" ] || { echo "FAIL: tree not clean"; git status --short; fail=1; }
[ "$fail" = 0 ] && echo "PASS: fleet_checkout recovers a dirty branch checkout"
exit $fail
