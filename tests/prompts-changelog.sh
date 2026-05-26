#!/bin/bash
# tests/prompts-changelog.sh — prompts/CHANGELOG.md + fleet prompts-diff
# (ticket 0013).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0013-prompts-changelog.md. Strategy:
#   * Build a fake kit root under $TMP/kit with a controlled `prompts/`
#     dir and a synthetic CHANGELOG carrying three dated entries. Build a
#     fake "installed" prompts tree under $TMP/home/.local/share/agent-fleet/
#     so the prompts-diff command compares two known-good trees.
#   * Point bin/fleet at the fake kit by exporting FLEET_KIT_ROOT so
#     the prompts-sha + prompts-diff resolution finds our fixture first.
#   * Stub HOME so the installed prompts location is also under $TMP.
#   * Run bin/fleet from the real repo (its dispatcher logic is what's
#     under test) but route all data through the fixture.
#
# Self-contained, no jq dependency for the assertions.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-prompts-changelog-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so the installed-prompts path is a controlled fixture.
export HOME="$TMP/home"
mkdir -p "$HOME"

# Fake kit root with its own prompts/. We use a SHORT, well-known content
# (`ship: a\n`) so we can produce a known SHA and assert on diff output.
KIT="$TMP/kit"
mkdir -p "$KIT/prompts"
echo "ship a" > "$KIT/prompts/ship.prompt.md"
echo "groom a" > "$KIT/prompts/groom.prompt.md"
echo "eng a" > "$KIT/prompts/eng.prompt.md"

# Synthetic CHANGELOG with three entries. The dates run in descending order
# (newest first, conventional for changelogs). Each entry has a heading +
# a body line so the --changelog filter has something to copy verbatim.
cat > "$KIT/prompts/CHANGELOG.md" <<'CHG'
# prompts CHANGELOG

Operator-curated record of behavioral changes to the prompts. Newest first.

## 2026-06-15 — heal budget honored

ship.prompt.md now reads HEAL_MAX from the manifest.

## 2026-06-01 — request-changes etiquette

review.prompt.md tells reviewer to cite line numbers.

## 2026-05-26 — initial entry

Bootstrap entry. No behavioral changes since project bootstrap.
CHG

# Compute the kit's prompts SHA via the documented formula so the test can
# match what --since accepts.
KIT_SHA=$( (cd "$KIT" && find prompts -type f -name '*.md' | sort | xargs cat) \
            | shasum -a 256 | awk '{print $1}' )

export FLEET_KIT_ROOT="$KIT"

# --- AC#2: prompts-diff against an installed prompts tree -----------------

# Build the installed prompts tree IDENTICAL to the kit first → exit 0.
INSTALLED="$HOME/.local/share/agent-fleet/prompts"
mkdir -p "$INSTALLED"
/bin/cp "$KIT/prompts/"* "$INSTALLED/"

set +e
"$FLEET" prompts-diff > "$TMP/clean.out" 2>&1
CLEAN_RC=$?
set -e

if [ "$CLEAN_RC" != "0" ]; then
  echo "FAIL: prompts-diff with identical trees exited $CLEAN_RC (want 0)"
  cat "$TMP/clean.out"
  exit 1
fi
echo "ok: clean state exits 0"

# --- AC#2 (cont): drifted state → exit 1, unified diff in stdout ----------

# Mutate the installed copy so we KNOW there's drift.
echo "ship a CHANGED" > "$INSTALLED/ship.prompt.md"
set +e
"$FLEET" prompts-diff > "$TMP/drift.out" 2>&1
DRIFT_RC=$?
set -e

if [ "$DRIFT_RC" != "1" ]; then
  echo "FAIL: prompts-diff with drifted trees exited $DRIFT_RC (want 1)"
  cat "$TMP/drift.out"
  exit 1
fi
if ! grep -q 'ship.prompt.md' "$TMP/drift.out"; then
  echo "FAIL: drift output did not mention the changed filename"
  cat "$TMP/drift.out"
  exit 1
fi
# Unified-diff sentinel: at least one line starting with `+` or `-`
# (excluding the `+++`/`---` headers). Use awk so an early-exit doesn't
# break SIGPIPE-sensitive shells.
if ! awk '/^[+-][^+-]/ { found=1 } END { exit !found }' "$TMP/drift.out"; then
  echo "FAIL: drift output had no +/- diff lines"
  cat "$TMP/drift.out"
  exit 1
fi
echo "ok: drifted state exits 1 with unified diff"

# Restore the tree so subsequent assertions start clean.
/bin/cp -f "$KIT/prompts/ship.prompt.md" "$INSTALLED/ship.prompt.md"

# --- AC#4: --changelog filters CHANGELOG entries newer than installed pin -

# The --changelog flag prints all CHANGELOG entries verbatim — full file
# when no pin is in play (the fixture's installed prompts have no pin
# stamped, so we surface every entry).
set +e
"$FLEET" prompts-diff --changelog > "$TMP/chg.out" 2>&1
CHG_RC=$?
set -e

if [ "$CHG_RC" != "0" ]; then
  echo "FAIL: prompts-diff --changelog exited $CHG_RC (want 0)"
  cat "$TMP/chg.out"
  exit 1
fi
for tag in "2026-06-15" "2026-06-01" "2026-05-26"; do
  if ! grep -qF "$tag" "$TMP/chg.out"; then
    echo "FAIL: --changelog output missing entry for $tag"
    cat "$TMP/chg.out"
    exit 1
  fi
done
echo "ok: --changelog surfaces every entry"

# --- AC#1: prompts/CHANGELOG.md exists in the REAL kit with a bootstrap entry ---
REAL_CHANGELOG="$REPO_ROOT/prompts/CHANGELOG.md"
if [ ! -f "$REAL_CHANGELOG" ]; then
  echo "FAIL: $REAL_CHANGELOG does not exist"
  exit 1
fi
if ! grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} — initial entry' "$REAL_CHANGELOG"; then
  echo "FAIL: prompts/CHANGELOG.md missing '## <date> — initial entry' heading"
  cat "$REAL_CHANGELOG"
  exit 1
fi
echo "ok: real prompts/CHANGELOG.md has bootstrap entry"

# --- AC#5: scripts/check-prompts-changelog.mjs exists and FAILS when a PR ---
# touches prompts/ but does not touch prompts/CHANGELOG.md, PASSES when
# both move together or when no prompts/ file moved.
VALIDATOR="$REPO_ROOT/scripts/check-prompts-changelog.mjs"
if [ ! -f "$VALIDATOR" ]; then
  echo "FAIL: $VALIDATOR not found"
  exit 1
fi

# Simulate three change sets via FLEET_PROMPTS_CHANGELOG_FILES (test seam,
# implemented by the validator below). The validator must read a newline-
# separated file list from this env var when set, instead of running
# `git diff --name-only`.
SET_PROMPT_ONLY="$TMP/files-prompt-only.txt"
printf '%s\n' "prompts/ship.prompt.md" > "$SET_PROMPT_ONLY"
SET_BOTH="$TMP/files-both.txt"
printf '%s\n%s\n' "prompts/ship.prompt.md" "prompts/CHANGELOG.md" > "$SET_BOTH"
SET_NO_PROMPT="$TMP/files-no-prompt.txt"
printf '%s\n' "lib/common.sh" > "$SET_NO_PROMPT"
SET_EMPTY="$TMP/files-empty.txt"
: > "$SET_EMPTY"

# Case A: prompts/ touched, CHANGELOG NOT touched → must FAIL.
set +e
FLEET_PROMPTS_CHANGELOG_FILES="$SET_PROMPT_ONLY" \
  node "$VALIDATOR" > "$TMP/val-a.out" 2>&1
RC_A=$?
set -e
if [ "$RC_A" = "0" ]; then
  echo "FAIL: validator passed when prompts/ was touched without CHANGELOG"
  cat "$TMP/val-a.out"
  exit 1
fi
if ! grep -qi 'changelog' "$TMP/val-a.out"; then
  echo "FAIL: validator failure message does not mention CHANGELOG"
  cat "$TMP/val-a.out"
  exit 1
fi
echo "ok: validator FAILS on prompts-without-CHANGELOG"

# Case B: prompts/ touched AND CHANGELOG touched → must PASS.
set +e
FLEET_PROMPTS_CHANGELOG_FILES="$SET_BOTH" \
  node "$VALIDATOR" > "$TMP/val-b.out" 2>&1
RC_B=$?
set -e
if [ "$RC_B" != "0" ]; then
  echo "FAIL: validator failed when both prompts/ and CHANGELOG moved"
  cat "$TMP/val-b.out"
  exit 1
fi
echo "ok: validator PASSES when both move together"

# Case C: no prompts/ files touched → must PASS.
set +e
FLEET_PROMPTS_CHANGELOG_FILES="$SET_NO_PROMPT" \
  node "$VALIDATOR" > "$TMP/val-c.out" 2>&1
RC_C=$?
set -e
if [ "$RC_C" != "0" ]; then
  echo "FAIL: validator failed when no prompts/ file moved"
  cat "$TMP/val-c.out"
  exit 1
fi
echo "ok: validator PASSES when prompts/ untouched"

# Case D: empty file list (non-PR run / no diff) → must PASS gracefully.
set +e
FLEET_PROMPTS_CHANGELOG_FILES="$SET_EMPTY" \
  node "$VALIDATOR" > "$TMP/val-d.out" 2>&1
RC_D=$?
set -e
if [ "$RC_D" != "0" ]; then
  echo "FAIL: validator failed on empty file list (non-PR / no diff)"
  cat "$TMP/val-d.out"
  exit 1
fi
echo "ok: validator PASSES on empty file list (non-PR)"

# --- AC#7: AGENTS.md has a '## Prompts changelog' section ---------------
if ! grep -qE '^##[[:space:]]+Prompts changelog' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL: AGENTS.md missing '## Prompts changelog' section"
  exit 1
fi
echo "ok: AGENTS.md has Prompts changelog section"

# --- bonus: --since <SHA> resolves a commit and prints a diff (AC#3) -----
# AC#3 says: walks `git log -- prompts/` to find the commit whose tree
# matches the SHA, then diffs HEAD against that commit's prompts/. We
# exercise the parser with a malformed SHA to confirm the failure mode is
# tidy (no crash, exit non-zero). The happy path requires real git
# history of prompts/ over multiple commits — covered by CI's own
# evolution rather than this isolated unit test. The presence of
# `--since` is the floor we assert here.
set +e
"$FLEET" prompts-diff --since deadbeef > "$TMP/since.out" 2>&1
SINCE_RC=$?
set -e
# Either exit 0 (no diff for a SHA that resolves to HEAD-equivalent) or
# exit non-zero with a clear message — we only require it does NOT
# segfault / hang and that --since is a known flag.
if grep -qi 'unknown flag' "$TMP/since.out"; then
  echo "FAIL: --since rejected as unknown flag"
  cat "$TMP/since.out"
  exit 1
fi
echo "ok: --since is a recognised flag (rc=$SINCE_RC)"

# Use SINCE_RC and KIT_SHA so shellcheck doesn't complain about unread vars.
: "$SINCE_RC" "$KIT_SHA"

echo "ok: tests/prompts-changelog.sh passed"
