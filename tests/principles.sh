#!/bin/bash
# tests/principles.sh — PRINCIPLES.md doctrine file + downstream wiring
# (ticket 0018).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0018-prompts-principles.md. Strategy: pure-grep / pure-file
# assertions against the repo working tree, plus one round-trip through
# `bin/fleet prompts-sha` to prove PRINCIPLES.md is part of the prompts
# SHA input (AC#7). No mktemp fixture for the grep work; the SHA test
# uses an isolated $HOME only because bin/fleet itself wants one.
#
# Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
PRINCIPLES="$REPO_ROOT/prompts/PRINCIPLES.md"

# --- AC#1: file exists, has at least 6 numbered P-N principles, < 150 lines ---
if [ ! -f "$PRINCIPLES" ]; then
  echo "FAIL: $PRINCIPLES does not exist"
  exit 1
fi

LINES=$(wc -l < "$PRINCIPLES" | tr -d ' ')
if [ "$LINES" -ge 150 ]; then
  echo "FAIL: prompts/PRINCIPLES.md is $LINES lines (must be < 150)"
  exit 1
fi
echo "ok: prompts/PRINCIPLES.md exists ($LINES lines)"

# --- AC#2: grep-able by P-N id, count >= 6 -------------------------------
PN_COUNT=$(grep -cE '^## P-[0-9]+\b' "$PRINCIPLES" || true)
if [ "$PN_COUNT" -lt 6 ]; then
  echo "FAIL: expected >= 6 '## P-N' headings, found $PN_COUNT"
  grep -nE '^## P-[0-9]+\b' "$PRINCIPLES" || true
  exit 1
fi
echo "ok: $PN_COUNT '## P-N' headings"

# --- AC#3: required principle keyword phrases (case-insensitive) ---------
# Map each principle slot to a distinguishing keyword phrase the prose
# MUST contain. The implementing agent may add more principles; these
# six are non-negotiable.
check_keyword() {
  local id="$1" pattern="$2"
  if ! grep -qiE "$pattern" "$PRINCIPLES"; then
    echo "FAIL: $id keyword pattern not found in PRINCIPLES.md: $pattern"
    exit 1
  fi
}
check_keyword "P-1" 'smallest viable change'
check_keyword "P-2" 'tests?[- ]first'
check_keyword "P-3" 'heal .* before shipping'
check_keyword "P-4" 'top groomed'
check_keyword "P-5" 'operator confidence'
check_keyword "P-6" 'telemetry .* source of truth'
echo "ok: all six required principle keyword phrases present"

# --- AC#4: PHASE 0 directive in ship, groom, eng prompts -----------------
PHASE0_DIRECTIVE='Read prompts/PRINCIPLES.md before doing anything else'
for f in ship.prompt.md groom.prompt.md eng.prompt.md; do
  path="$REPO_ROOT/prompts/$f"
  if [ ! -f "$path" ]; then
    echo "FAIL: $path missing"
    exit 1
  fi
  if ! grep -qF "$PHASE0_DIRECTIVE" "$path"; then
    echo "FAIL: $path missing PHASE 0 directive: $PHASE0_DIRECTIVE"
    exit 1
  fi
  if ! grep -qE 'cite the principle id \(P-N\)' "$path"; then
    echo "FAIL: $path missing 'cite the principle id (P-N)' clause"
    exit 1
  fi
done
echo "ok: PHASE 0 PRINCIPLES.md directive in ship/groom/eng prompts"

# --- AC#5: lib/review.sh rubric references PRINCIPLES.md ------------------
if ! grep -q 'PRINCIPLES.md' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: lib/review.sh missing PRINCIPLES.md reference"
  exit 1
fi
if ! grep -qE 'P-[A-Z]|P-N|P-[0-9]' "$REPO_ROOT/lib/review.sh"; then
  echo "FAIL: lib/review.sh missing P-N citation guidance"
  exit 1
fi
echo "ok: lib/review.sh cites PRINCIPLES.md in its rubric"

# --- AC#6: AGENTS.md cross-references prompts/PRINCIPLES.md ---------------
if ! grep -q 'prompts/PRINCIPLES.md' "$REPO_ROOT/AGENTS.md"; then
  echo "FAIL: AGENTS.md does not reference prompts/PRINCIPLES.md"
  exit 1
fi
echo "ok: AGENTS.md cross-references prompts/PRINCIPLES.md"

# --- AC#7: prompts-sha includes PRINCIPLES.md (changes when it changes) ---
# Isolate HOME so bin/fleet's stub-friendly environment doesn't trip on the
# host's real config.
TMP="$(mktemp -d -t fleet-principles-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

SHA_BEFORE=$("$FLEET" prompts-sha)
if ! [[ "$SHA_BEFORE" =~ ^[0-9a-f]{64}$ ]]; then
  echo "FAIL: prompts-sha did not return a 64-hex SHA: $SHA_BEFORE"
  exit 1
fi

# Append a no-op comment line and assert the SHA shifts. Restore afterwards
# so the working tree is unchanged when the test exits successfully.
# Use a byte-exact backup copy (cp), not a $(cat) round-trip, because shells
# strip trailing newlines from command substitutions and we DO NOT want to
# silently mutate the file under test.
BACKUP="$TMP/PRINCIPLES.md.bak"
cp "$PRINCIPLES" "$BACKUP"
restore() { cp "$BACKUP" "$PRINCIPLES"; }
# Replace the EXIT trap so cleanup tmp + restore both happen.
trap 'restore; rm -rf "$TMP"' EXIT

printf '\n<!-- principles-sha-roundtrip %s -->\n' "$(date -u +%s)" >> "$PRINCIPLES"
SHA_AFTER=$("$FLEET" prompts-sha)
restore

if [ "$SHA_BEFORE" = "$SHA_AFTER" ]; then
  echo "FAIL: prompts-sha unchanged after editing PRINCIPLES.md"
  echo "  before: $SHA_BEFORE"
  echo "  after:  $SHA_AFTER"
  exit 1
fi
echo "ok: prompts-sha changes when PRINCIPLES.md changes"

# --- AC#8: pure-grep — implicit. If we got here without any mktemp-backed
# fixtures (other than the prompts-sha isolation of HOME), the test is
# pure-grep over file content. Document the invariant explicitly.
echo "ok: tests/principles.sh covered all acceptance boxes via file-content assertions"
echo "ok: tests/principles.sh passed"
