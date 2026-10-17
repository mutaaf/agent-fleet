#!/bin/bash
# tests/review-gate.sh — the reviewer's verdict as a required check (ticket 0070).
#
# Drives templates/scripts/review-gate.sh against fixture review lists through a
# stubbed `gh` that applies the script's real --jq filter, and asserts:
#
#   AC#1  Agent PR with `FLEET-VERDICT: clean` from the reviewer on the CURRENT
#         head → pass. Marker matching is case-insensitive.
#   AC#2  No verdict on the head (no reviews, wrong commit, other user, no
#         marker, null body) → fail. Old-head verdicts never count.
#   AC#3  `FLEET-VERDICT: blocking` on the head → fail; the NEWEST verdict on
#         the head wins (blocking→clean passes, clean→blocking fails).
#   AC#4  Non-agent (human) branches → pass without calling gh.
#   AC#5  The workflow template triggers on pull_request AND pull_request_review,
#         runs the gate from the base commit (a PR can't edit its own gate), and
#         names the job `review-gate` (the required-check context).
#   AC#6  lib/review.sh re-grades by head commit and requires the marker; the
#         ship/eng prompts carry the REVIEW GATE rule; P-10 + CHANGELOG exist.
#
# Self-contained: stubs gh on PATH under an isolated HOME (2026-05-26 LESSON).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
GATE="$REPO_ROOT/templates/scripts/review-gate.sh"
TMP="$(mktemp -d -t fleet-review-gate-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

command -v jq >/dev/null || { echo "SKIP: jq not installed"; exit 0; }

# gh stub: `gh api <path> --jq <expr>` → apply <expr> to $FIXTURE; log calls.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
echo "$*" >> "$HOME/gh.calls"
expr=""; while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && { expr="$2"; shift; }; shift; done
jq -r "$expr" < "$FIXTURE"
STUB
chmod +x "$HOME/.local/bin/gh"

HEAD=aaaaaaa1111111
OLD=bbbbbbb2222222
review() { printf '{"user":{"login":"%s"},"commit_id":"%s","body":%s}' "$1" "$2" "$3"; }

# run_gate <name> <expected: pass|fail> <branch> <reviews-json-array>
run_gate() {
  local name="$1" want="$2" branch="$3" json="$4" got
  printf '%s' "$json" > "$TMP/fixture.json"
  if FIXTURE="$TMP/fixture.json" REPO=o/r PR=7 HEAD_SHA="$HEAD" BRANCH="$branch" REVIEWER=owner \
       bash "$GATE" >"$TMP/out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $name — expected $want, got $got"; cat "$TMP/out"; exit 1
  fi
}

# AC#1
run_gate "clean on head" pass feat/0001-x "[$(review owner $HEAD '"FLEET-VERDICT: clean\nLooks good."')]"
run_gate "marker case-insensitive" pass feat/0001-x "[$(review owner $HEAD '"fleet-verdict: CLEAN"')]"
run_gate "eng queue counts" pass eng/0002-y "[$(review owner $HEAD '"FLEET-VERDICT: clean"')]"
echo "ok: AC#1 clean verdict on the current head passes"

# AC#2
run_gate "no reviews" fail feat/0001-x "[]"
run_gate "clean only on old head" fail feat/0001-x "[$(review owner $OLD '"FLEET-VERDICT: clean"')]"
run_gate "clean from someone else" fail feat/0001-x "[$(review stranger $HEAD '"FLEET-VERDICT: clean"')]"
run_gate "no marker" fail feat/0001-x "[$(review owner $HEAD '"## Review summary\nAll good."')]"
run_gate "null body" fail feat/0001-x "[$(review owner $HEAD 'null')]"
run_gate "unknown verdict fails closed" fail feat/0001-x "[$(review owner $HEAD '"FLEET-VERDICT: maybe"')]"
echo "ok: AC#2 no verdict on the current head fails"

# AC#3
run_gate "blocking on head" fail chore/gtm-20261017 "[$(review owner $HEAD '"FLEET-VERDICT: blocking\nMissing test."')]"
run_gate "blocking then clean" pass feat/0001-x "[$(review owner $HEAD '"FLEET-VERDICT: blocking"'),$(review owner $HEAD '"FLEET-VERDICT: clean"')]"
run_gate "clean then blocking" fail feat/0001-x "[$(review owner $HEAD '"FLEET-VERDICT: clean"'),$(review owner $HEAD '"FLEET-VERDICT: blocking"')]"
run_gate "old-head clean + head blocking" fail feat/0001-x "[$(review owner $OLD '"FLEET-VERDICT: clean"'),$(review owner $HEAD '"FLEET-VERDICT: blocking"')]"
echo "ok: AC#3 blocking fails; newest verdict on the head wins"

# AC#4
rm -f "$HOME/gh.calls"
run_gate "human branch" pass mutaaf/fix-typo "[]"
[ ! -s "$HOME/gh.calls" ] || { echo "FAIL: AC#4 gate called gh for a human branch"; exit 1; }
echo "ok: AC#4 human branches pass without a lookup"

# AC#5
WF="$REPO_ROOT/templates/workflows/review-gate.yml"
grep -q '^  pull_request:' "$WF"           || { echo "FAIL: AC#5 no pull_request trigger"; exit 1; }
grep -q '^  pull_request_review:' "$WF"    || { echo "FAIL: AC#5 no pull_request_review trigger"; exit 1; }
grep -q 'ref: \${{ github.event.pull_request.base.sha }}' "$WF" || { echo "FAIL: AC#5 gate must run from the base commit"; exit 1; }
grep -q '^  review-gate:' "$WF"            || { echo "FAIL: AC#5 job must be named review-gate"; exit 1; }
grep -q 'bash scripts/review-gate.sh' "$WF" || { echo "FAIL: AC#5 workflow must run scripts/review-gate.sh"; exit 1; }
echo "ok: AC#5 workflow template triggers, base-commit checkout, job name"

# AC#6
R="$REPO_ROOT/lib/review.sh"
grep -q 'commit.oid == \\$head' "$R" || { echo "FAIL: AC#6 review.sh must select by head commit"; exit 1; }
grep -q 'test(\\"FLEET-VERDICT:\\"; \\"i\\")' "$R" || { echo "FAIL: AC#6 review.sh must require the marker"; exit 1; }
grep -q 'REVIEW GATE (ticket 0070)' "$REPO_ROOT/prompts/ship.prompt.md" || { echo "FAIL: AC#6 ship prompt lacks REVIEW GATE"; exit 1; }
grep -q 'REVIEW GATE rule' "$REPO_ROOT/prompts/eng.prompt.md" || { echo "FAIL: AC#6 eng prompt lacks REVIEW GATE"; exit 1; }
grep -q '^## P-10 ' "$REPO_ROOT/prompts/PRINCIPLES.md" || { echo "FAIL: AC#6 PRINCIPLES lacks P-10"; exit 1; }
grep -q 'ticket 0070' "$REPO_ROOT/prompts/CHANGELOG.md" || { echo "FAIL: AC#6 CHANGELOG lacks the 0070 entry"; exit 1; }
echo "ok: AC#6 reviewer, prompts, principle and changelog wired"

echo "ok: tests/review-gate.sh passed"
