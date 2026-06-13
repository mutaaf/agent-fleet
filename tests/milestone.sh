#!/bin/bash
# tests/milestone.sh — `bin/fleet milestone` streak-milestone celebration
# and streak-break recovery framing test.
#
# Ticket 0049. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0049-fleet-milestone-streak-celebrate-and-recover.md.
# `milestone` is a PURE READER of events.jsonl that composes one block
# per detected threshold-crossing / new-longest / streak-break event in
# a trailing 24h window.
#
# Shape mirrors tests/streak.sh (the closest prior pure-reader sibling
# from ticket 0042) and tests/recap (ticket 0048).
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-05-28 every printf of a slug name uses `printf -- '%s'`.
# Per LESSONS 2026-05-30 every help-text grep uses `grep -qF -- "$kw"`.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-06-11 the "yesterday" override is computed in the
# shell via BSD date with the full `T00:00:00Z` time component pinned —
# never `-j -f '%Y-%m-%d'` of a bare date.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/milestone"

TMP="$(mktemp -d -t fleet-milestone-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "today" at 2026-06-13T12:00:00Z. Yesterday is 24h before.
# Compute both via BSD `date -u -j -f '%Y-%m-%dT%H:%M:%SZ'` (LESSONS
# 2026-06-11 — never bare YYYY-MM-DD).
NOW_ISO="2026-06-13T12:00:00Z"
YESTERDAY_ISO="2026-06-12T12:00:00Z"
NOW_EPOCH="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$NOW_ISO" '+%s' 2>/dev/null \
              || date -u -d "$NOW_ISO" '+%s' 2>/dev/null)"
YESTERDAY_EPOCH="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$YESTERDAY_ISO" '+%s' 2>/dev/null \
                    || date -u -d "$YESTERDAY_ISO" '+%s' 2>/dev/null)"
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"
export FLEET_NOW_OVERRIDE_YESTERDAY="$YESTERDAY_EPOCH"

# Discovery root for synthetic manifests.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Seed a manifest for one slug (optionally with extra exported lines).
mk_manifest() {  # $1 = slug, $2 = extra lines (optional)
  local slug="$1" extra="${2:-}"
  mkdir -p "$FIXTURE_ROOT/$slug"
  {
    cat <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CFG
    if [ -n "$extra" ]; then printf -- '%s\n' "$extra"; fi
  } > "$FIXTURE_ROOT/$slug/agents.config.sh"
}

# Per-day emit helpers (lifted from tests/streak.sh shape).
emit_run_completed() {  # $1 = slug, $2 = YYYY-MM-DD, $3 = exit
  printf '{"ts":"%sT12:00:00Z","slug":"%s","phase":"ship","type":"run_completed","exit":"%s","duration_ms":"42"}\n' \
    "$2" "$1" "$3"
}
emit_ship_paused() {  # $1 = slug, $2 = YYYY-MM-DD
  printf '{"ts":"%sT09:00:00Z","slug":"%s","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"100"}\n' \
    "$2" "$1"
}
emit_budget_block() {  # $1 = slug, $2 = YYYY-MM-DD
  printf '{"ts":"%sT08:00:00Z","slug":"%s","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$2" "$1"
}
emit_lesson_draft() {  # $1 = slug, $2 = YYYY-MM-DD, $3 = PR, $4 = headline
  printf '{"ts":"%sT10:00:00Z","slug":"%s","phase":"review","type":"lesson_draft_emitted","pr":"%s","headline":"%s"}\n' \
    "$2" "$1" "$3" "$4"
}

next_day() {  # YYYY-MM-DD → next day
  date -u -j -v +1d -f '%Y-%m-%dT%H:%M:%SZ' "${1}T00:00:00Z" '+%Y-%m-%d' 2>/dev/null \
    || date -u -d "$1 +1 day" '+%Y-%m-%d'
}

# Seed N green days ending at end_day on $slug, via run_completed exit=0.
seed_clean_streak_ending() {  # $1=slug, $2=end YYYY-MM-DD, $3=N
  local slug="$1" end="$2" n="$3" i d
  local file="$HOME/.cache/${slug}-agent/events.jsonl"
  mkdir -p "$(dirname "$file")"
  # Compute start = end - (N-1) days.
  d="$(date -u -j -v -$(( n - 1 ))d -f '%Y-%m-%dT%H:%M:%SZ' "${end}T00:00:00Z" '+%Y-%m-%d' 2>/dev/null \
        || date -u -d "$end - $(( n - 1 )) days" '+%Y-%m-%d')"
  : > "$file"
  for (( i=0; i<n; i++ )); do
    emit_run_completed "$slug" "$d" 0 >> "$file"
    d="$(next_day "$d")"
  done
}

# ========================================================================
# Fixtures.
# ========================================================================
# Slug af-cross-10: a clean 10-day streak ending today (2026-06-13).
# Yesterday (2026-06-12) would be 9d. This crosses the default 10d threshold.
mk_manifest af-cross-10
seed_clean_streak_ending af-cross-10 "2026-06-13" 10

# Slug cq-new-23: a clean 23-day streak ending today; the historical
# longest in the window is 18d (an earlier 18-day run, then a break,
# then today's 23-day run).
mk_manifest cq-new-23
CQ_FILE="$HOME/.cache/cq-new-23-agent/events.jsonl"
mkdir -p "$(dirname "$CQ_FILE")"
{
  # 18-day clean run May 1 → May 18 (2026)
  d="2026-05-01"
  for (( i=0; i<18; i++ )); do
    emit_run_completed cq-new-23 "$d" 0
    d="$(next_day "$d")"
  done
  # Break on 2026-05-19
  emit_ship_paused cq-new-23 "2026-05-19"
  # 23-day clean run May 22 → June 13
  d="2026-05-22"
  for (( i=0; i<23; i++ )); do
    emit_run_completed cq-new-23 "$d" 0
    d="$(next_day "$d")"
  done
} > "$CQ_FILE"

# Slug dc-break-14: 14 green days then a ship_paused break TODAY (2026-06-13).
# Includes a lesson_draft_emitted on the break day so the recovery line
# can surface it.
mk_manifest dc-break-14
DC_FILE="$HOME/.cache/dc-break-14-agent/events.jsonl"
mkdir -p "$(dirname "$DC_FILE")"
{
  d="2026-05-30"  # 14 days back from 2026-06-12 inclusive
  for (( i=0; i<14; i++ )); do
    emit_run_completed dc-break-14 "$d" 0
    d="$(next_day "$d")"
  done
  # Break today.
  emit_ship_paused dc-break-14 "2026-06-13"
  emit_lesson_draft dc-break-14 "2026-06-13" "214" "test wrote to a non-isolated path"
} > "$DC_FILE"

# Slug q-none: no events.jsonl (or empty file).
mk_manifest q-none
QN_FILE="$HOME/.cache/q-none-agent/events.jsonl"
mkdir -p "$(dirname "$QN_FILE")"
: > "$QN_FILE"

# ========================================================================
# AC #1 — `bin/fleet milestone` (no flags) walks every discovered project,
#         detects threshold crossings AND streak breaks in the trailing
#         24h window, emits one block per event, exit 0.
# ========================================================================
echo "AC#1 — default invocation walks discovery roots and detects events"
OUT="$TMP/ac1.out"
set +e
"$FLEET" milestone > "$OUT" 2>&1
EXIT=$?
set -e

if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 milestone exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi

# Must mention all three eventful slugs.
for slug in af-cross-10 cq-new-23 dc-break-14; do
  grep -qF -- "$slug" "$OUT" \
    || { echo "FAIL: AC#1 missing block for $slug"; cat "$OUT"; exit 1; }
done
# Must NOT mention the quiet slug.
if grep -qF -- "q-none" "$OUT"; then
  echo "FAIL: AC#1 quiet slug (q-none) leaked into render"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #2 — MILESTONE_THRESHOLDS knob (default 10,30,100; empty disables
#         threshold-crossing detection).
# ========================================================================
echo "AC#2 — MILESTONE_THRESHOLDS knob default + empty"

# Default detects the 10d crossing on af-cross-10.
OUT="$TMP/ac2-default.out"
"$FLEET" milestone --slug af-cross-10 > "$OUT"
grep -qF -- "af-cross-10" "$OUT" \
  || { echo "FAIL: AC#2 default threshold should fire on 10d crossing"; cat "$OUT"; exit 1; }

# Override: set MILESTONE_THRESHOLDS in the manifest to empty → threshold
# detection disabled; the af-cross-10 slug should produce no block (and
# the empty branch should fire if it's the only slug).
mk_manifest empty-thresh 'MILESTONE_THRESHOLDS=""'
seed_clean_streak_ending empty-thresh "2026-06-13" 10
OUT="$TMP/ac2-empty.out"
"$FLEET" milestone --slug empty-thresh > "$OUT"
if grep -qE "NEW LONGEST STREAK|THRESHOLD" "$OUT"; then
  echo "FAIL: AC#2 empty MILESTONE_THRESHOLDS should disable threshold-crossing detection"
  cat "$OUT"; exit 1
fi

# Custom ladder: 5,20,50 — should fire the crossing for the 23d cq-new-23
# at the 20d ladder rung (since yesterday it was 22d? No — that's wrong:
# the streak is climbing, yesterday cq-new-23 was at 22d which is > 20d
# so the 20d crossing already happened earlier). We instead seed a fresh
# slug that just-crossed 20d today.
mk_manifest cust-20 'MILESTONE_THRESHOLDS="5,20,50"'
seed_clean_streak_ending cust-20 "2026-06-13" 20
OUT="$TMP/ac2-custom.out"
"$FLEET" milestone --slug cust-20 > "$OUT"
grep -qE "20d|THRESHOLD" "$OUT" \
  || { echo "FAIL: AC#2 custom ladder should fire on 20d"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #3 — threshold-crossing fires when today >= T AND yesterday < T.
#         Yesterday's compute uses an ISO8601 24h-shifted FLEET_NOW
#         override — never a `date -j -f '%Y-%m-%d'` of a bare date.
# ========================================================================
echo "AC#3 — threshold crossing today=10d, yesterday=9d"
OUT="$TMP/ac3.out"
"$FLEET" milestone --slug af-cross-10 > "$OUT"
# Must mention 10d (the threshold) somewhere on the af-cross-10 block.
grep -qE "10d|10 days" "$OUT" \
  || { echo "FAIL: AC#3 missing 10d threshold marker"; cat "$OUT"; exit 1; }
# Negative branch: a slug at 9d today (yesterday=8d) MUST NOT cross the
# 10d threshold. (NEW LONGEST STREAK is a DIFFERENT event — a fresh
# synthetic slug with no prior run trivially produces a "new longest"
# block, so we only assert the absence of a THRESHOLD CROSSED line.)
mk_manifest below-thresh
seed_clean_streak_ending below-thresh "2026-06-13" 9
OUT="$TMP/ac3-below.out"
"$FLEET" milestone --slug below-thresh > "$OUT"
if grep -qF -- "THRESHOLD CROSSED" "$OUT"; then
  echo "FAIL: AC#3 below-threshold slug should NOT fire a threshold crossing"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #4 — NEW LONGEST STREAK fires when current streak strictly exceeds
#         prior longest. Threshold-crossing and new-longest can stack on
#         one slug.
# ========================================================================
echo "AC#4 — NEW LONGEST STREAK at 23d > prior 18d"
OUT="$TMP/ac4.out"
"$FLEET" milestone --slug cq-new-23 > "$OUT"
grep -qF -- "NEW LONGEST STREAK" "$OUT" \
  || { echo "FAIL: AC#4 missing 'NEW LONGEST STREAK' line"; cat "$OUT"; exit 1; }
grep -qF -- "23d" "$OUT" \
  || { echo "FAIL: AC#4 missing 23d current value"; cat "$OUT"; exit 1; }
grep -qF -- "18d" "$OUT" \
  || { echo "FAIL: AC#4 missing 18d previous best"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #5 — streak-break line: (a) current=0, (b) most-recent break event in
#         trailing 24h, (c) prior streak length >= MILESTONE_BREAK_FLOOR.
#         Includes break type+date, drafted lesson, recovery posture.
# ========================================================================
echo "AC#5 — streak break with break type + lesson + recovery command"
OUT="$TMP/ac5.out"
"$FLEET" milestone --slug dc-break-14 > "$OUT"
grep -qF -- "STREAK BROKEN" "$OUT" \
  || { echo "FAIL: AC#5 missing 'STREAK BROKEN' marker"; cat "$OUT"; exit 1; }
grep -qF -- "ship_paused" "$OUT" \
  || { echo "FAIL: AC#5 missing breaking-event type 'ship_paused'"; cat "$OUT"; exit 1; }
grep -qF -- "2026-06-13" "$OUT" \
  || { echo "FAIL: AC#5 missing break date 2026-06-13"; cat "$OUT"; exit 1; }
grep -qF -- "test wrote to a non-isolated path" "$OUT" \
  || { echo "FAIL: AC#5 missing drafted lesson text"; cat "$OUT"; exit 1; }
grep -qF -- "fleet resume dc-break-14" "$OUT" \
  || { echo "FAIL: AC#5 missing recovery posture 'fleet resume dc-break-14'"; cat "$OUT"; exit 1; }
# 14d (prior streak length) should be cited.
grep -qF -- "14d" "$OUT" \
  || { echo "FAIL: AC#5 missing prior streak length 14d"; cat "$OUT"; exit 1; }

# Variant: budget_block break must NOT propose `fleet resume` (operator
# owns the budget). Use a fresh slug just above floor (≥7).
mk_manifest brk-budget
BG_FILE="$HOME/.cache/brk-budget-agent/events.jsonl"
mkdir -p "$(dirname "$BG_FILE")"
{
  d="2026-06-06"
  for (( i=0; i<7; i++ )); do
    emit_run_completed brk-budget "$d" 0
    d="$(next_day "$d")"
  done
  emit_budget_block brk-budget "2026-06-13"
} > "$BG_FILE"
OUT="$TMP/ac5-budget.out"
"$FLEET" milestone --slug brk-budget > "$OUT"
grep -qF -- "budget_block" "$OUT" \
  || { echo "FAIL: AC#5 budget_block break should be detected"; cat "$OUT"; exit 1; }
if grep -qF -- "fleet resume brk-budget" "$OUT"; then
  echo "FAIL: AC#5 budget_block break should NOT propose 'fleet resume'"
  cat "$OUT"; exit 1
fi

# Variant: below-floor break (5d) is silenced. MILESTONE_BREAK_FLOOR is 7.
mk_manifest brk-tiny
BT_FILE="$HOME/.cache/brk-tiny-agent/events.jsonl"
mkdir -p "$(dirname "$BT_FILE")"
{
  d="2026-06-08"
  for (( i=0; i<5; i++ )); do
    emit_run_completed brk-tiny "$d" 0
    d="$(next_day "$d")"
  done
  emit_ship_paused brk-tiny "2026-06-13"
} > "$BT_FILE"
OUT="$TMP/ac5-tiny.out"
"$FLEET" milestone --slug brk-tiny > "$OUT"
if grep -qF -- "STREAK BROKEN" "$OUT"; then
  echo "FAIL: AC#5 below-floor (5d < 7d default) break should NOT emit a block"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #6 — celebration paste-ready line ends with literal
#         'powered by agent-fleet'.
# ========================================================================
echo "AC#6 — paste-ready line ends with 'powered by agent-fleet'"
OUT="$TMP/ac6.out"
"$FLEET" milestone --slug cq-new-23 > "$OUT"
grep -qF -- "powered by agent-fleet" "$OUT" \
  || { echo "FAIL: AC#6 missing 'powered by agent-fleet' suffix"; cat "$OUT"; exit 1; }
grep -qF -- "paste-ready" "$OUT" \
  || { echo "FAIL: AC#6 missing 'paste-ready:' label"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #7 — --since Nd|YYYY-MM-DD overrides the default 24h window.
# ========================================================================
echo "AC#7 — --since Nd and YYYY-MM-DD overrides window"
# --since 7d: dc-break-14's break is today (2026-06-13), so it stays in
# the window. Should still detect the break.
OUT="$TMP/ac7-nd.out"
"$FLEET" milestone --since 7d --slug dc-break-14 > "$OUT"
grep -qF -- "STREAK BROKEN" "$OUT" \
  || { echo "FAIL: AC#7 --since 7d should still pick up today's break"; cat "$OUT"; exit 1; }

# --since YYYY-MM-DD form should accept and not error.
OUT="$TMP/ac7-ymd.out"
set +e
"$FLEET" milestone --since 2026-06-06 --slug dc-break-14 > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#7 --since 2026-06-06 should exit 0, got $EXIT"; cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #8 — --slug NAME restricts to one project.
# ========================================================================
echo "AC#8 — --slug restricts to one project"
OUT="$TMP/ac8.out"
"$FLEET" milestone --slug af-cross-10 > "$OUT"
grep -qF -- "af-cross-10" "$OUT" \
  || { echo "FAIL: AC#8 --slug af-cross-10 missing block"; cat "$OUT"; exit 1; }
if grep -qF -- "cq-new-23" "$OUT"; then
  echo "FAIL: AC#8 --slug af-cross-10 leaked cq-new-23"; cat "$OUT"; exit 1
fi
if grep -qF -- "dc-break-14" "$OUT"; then
  echo "FAIL: AC#8 --slug af-cross-10 leaked dc-break-14"; cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #9 — --json emits one JSON object per detected event, with the
#         prescribed key set. Validated via Node.
# ========================================================================
echo "AC#9 — --json shape and validity"
OUT="$TMP/ac9.out"
"$FLEET" milestone --json > "$OUT"

# Every required key present somewhere in the document.
for k in '"slug"' '"kind"' '"value"' '"previous_best"' '"broken_by"' \
         '"broken_on"' '"drafted_lesson"' '"recovery_command"' '"paste_ready"'; do
  grep -qF -- "$k" "$OUT" \
    || { echo "FAIL: AC#9 --json missing key $k"; cat "$OUT"; exit 1; }
done

# Validity: a JSON.parse of the file must not throw. The render is a
# JSON array of objects.
if command -v node >/dev/null 2>&1; then
  node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$OUT" \
    || { echo "FAIL: AC#9 --json did not parse as valid JSON"; cat "$OUT"; exit 1; }
fi
echo "  ok"

# ========================================================================
# AC #10 — --help prints USAGE mentioning --since, --slug, --json, the
#          threshold-ladder knob, and MILESTONE_BREAK_FLOOR. exit 0.
# ========================================================================
echo "AC#10 — --help banner mentions all knobs"
HELP_OUT="$TMP/ac10-help.out"
set +e
"$FLEET" milestone --help > "$HELP_OUT"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#10 --help should exit 0, got $EXIT"; cat "$HELP_OUT"; exit 1
fi
for kw in "--since" "--slug" "--json" "MILESTONE_THRESHOLDS" "MILESTONE_BREAK_FLOOR"; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL: AC#10 --help missing '$kw'"; cat "$HELP_OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #11 — empty case prints the prescribed no-events line.
# ========================================================================
echo "AC#11 — empty case prints 'no threshold crossings or streak breaks'"
# Point at a discovery root holding only the quiet slug.
EMPTY_ROOT="$TMP/empty-projects"
mkdir -p "$EMPTY_ROOT/q-only"
cat > "$EMPTY_ROOT/q-only/agents.config.sh" <<CFG
PROJECT_NAME="q-only"
SLUG="q-only"
NAMESPACE="com.q-only"
REPO_URL="https://github.com/example/q-only"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/q-only-agent"
: > "$HOME/.cache/q-only-agent/events.jsonl"

OUT="$TMP/ac11.out"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" "$FLEET" milestone > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#11 empty case should exit 0, got $EXIT"; cat "$OUT"; exit 1
fi
grep -qF -- "no threshold crossings or streak breaks" "$OUT" \
  || { echo "FAIL: AC#11 empty case missing prescribed text"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #12 — pure reader: zero events.jsonl writes. byte size of every
#          events.jsonl unchanged before/after invocation.
# ========================================================================
echo "AC#12 — pure reader, no events.jsonl writes"
BEFORE_SIZES="$TMP/ac12.before"
AFTER_SIZES="$TMP/ac12.after"
find "$HOME/.cache" -name events.jsonl -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null | sort > "$BEFORE_SIZES"
"$FLEET" milestone > /dev/null
find "$HOME/.cache" -name events.jsonl -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null | sort > "$AFTER_SIZES"
if ! diff -q "$BEFORE_SIZES" "$AFTER_SIZES" > /dev/null; then
  echo "FAIL: AC#12 events.jsonl mutated by milestone invocation"
  diff -u "$BEFORE_SIZES" "$AFTER_SIZES" || true
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #13 — "next thresholds active" footer. Lists per-slug nearest
#          unmet threshold + days-to-reach. Both branches.
# ========================================================================
echo "AC#13 — next thresholds footer (both branches)"
OUT="$TMP/ac13.out"
"$FLEET" milestone > "$OUT"
grep -qF -- "next thresholds active" "$OUT" \
  || { echo "FAIL: AC#13 missing 'next thresholds active' footer"; cat "$OUT"; exit 1; }

# Branch B: all thresholds already crossed. Build a slug at 100d+ days
# (the top threshold) so nothing is unmet on the default ladder.
mk_manifest top-crossed 'MILESTONE_THRESHOLDS="5"'
seed_clean_streak_ending top-crossed "2026-06-13" 30
ALL_ROOT="$TMP/all-crossed"
mkdir -p "$ALL_ROOT/top-crossed"
cp "$FIXTURE_ROOT/top-crossed/agents.config.sh" "$ALL_ROOT/top-crossed/agents.config.sh"

OUT="$TMP/ac13-allcrossed.out"
set +e
FLEET_DISCOVERY_ROOT="$ALL_ROOT" "$FLEET" milestone > "$OUT" 2>&1
set -e
grep -qF -- "all active streaks have crossed every configured threshold" "$OUT" \
  || { echo "FAIL: AC#13 all-crossed branch missing prescribed footer"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #14 — lib/common.sh untouched on this branch.
# ========================================================================
echo "AC#14 — lib/common.sh untouched"
cd "$REPO_ROOT"
changed=$(git diff --name-only main...HEAD -- lib/common.sh | awk 'END { print NR+0 }')
if [ "$changed" -ne 0 ]; then
  echo "FAIL: AC#14 lib/common.sh changed on this branch"
  git diff --name-only main...HEAD -- lib/common.sh
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #15 — prompts/ untouched on this branch.
# ========================================================================
echo "AC#15 — prompts/ untouched"
changed=$(git diff --name-only main...HEAD -- prompts/ | awk 'END { print NR+0 }')
if [ "$changed" -ne 0 ]; then
  echo "FAIL: AC#15 prompts/ changed on this branch"
  git diff --name-only main...HEAD -- prompts/
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #16 — fixture directory tests/fixtures/milestone/ exists with at
#          least one file (covers fixture-presence convention).
# ========================================================================
echo "AC#16 — fixture directory present"
[ -d "$FIXTURE_DIR" ] \
  || { echo "FAIL: AC#16 tests/fixtures/milestone/ missing"; exit 1; }
if [ -z "$(find "$FIXTURE_DIR" -type f -print -quit)" ]; then
  echo "FAIL: AC#16 tests/fixtures/milestone/ is empty"; exit 1
fi
echo "  ok"

echo
echo "PASS: tests/milestone.sh — all 16 acceptance criteria green."
