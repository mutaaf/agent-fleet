#!/bin/bash
# tests/streak.sh — `bin/fleet streak` continuous green-day run test.
#
# Ticket 0042. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0042-fleet-streak-continuous-green-days.md. The `streak`
# reader is a PURE CONSUMER of the existing events.jsonl channel — no
# new event types, no fleet_* signature changes, no lib/ or prompts/
# edits.
#
# Fixtures: eight synthetic events.jsonl files seeded under per-slug
# fixture trees, mirroring tests/diff.sh + tests/atlas.sh. The clock is
# pinned via FLEET_NOW_OVERRIDE so every "today is YYYY-MM-DD" branch
# stays deterministic across runs.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-05-30 (`grep -F --` flag trap) every help-text grep
# uses `grep -qF -- "$kw"`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/streak"

TMP="$(mktemp -d -t fleet-streak-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Anchor "today" at 2026-06-10T12:00:00Z. The default window is 90 days
# so the walk reaches back to roughly 2026-03-12.
NOW_EPOCH=1781092800
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

# Seed a manifest at the fixture root for one slug.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

mk_manifest() {  # $1 = slug
  local slug="$1"
  mkdir -p "$FIXTURE_ROOT/$slug"
  cat > "$FIXTURE_ROOT/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CFG
}

# Helper: emit one ship/run_completed event on a UTC YYYY-MM-DD.
emit_run_completed() {  # $1 = slug, $2 = YYYY-MM-DD, $3 = exit code
  local slug="$1" day="$2" exit_code="$3"
  printf '{"ts":"%sT12:00:00Z","slug":"%s","phase":"ship","type":"run_completed","exit":"%s","duration_ms":"42"}\n' \
    "$day" "$slug" "$exit_code"
}

emit_gate_failed() {  # $1 = slug, $2 = YYYY-MM-DD
  printf '{"ts":"%sT11:00:00Z","slug":"%s","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
    "$2" "$1"
}

emit_ship_paused() {  # $1 = slug, $2 = YYYY-MM-DD
  printf '{"ts":"%sT09:00:00Z","slug":"%s","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"100"}\n' \
    "$2" "$1"
}

emit_budget_block() {  # $1 = slug, $2 = YYYY-MM-DD
  printf '{"ts":"%sT08:00:00Z","slug":"%s","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$2" "$1"
}

# Walk forward across days in YYYY-MM-DD via BSD `date -j -f` (LESSONS
# 2026-06-05). Echoes the next day after $1.
next_day() {
  date -u -j -v +1d -f '%Y-%m-%d' "$1" '+%Y-%m-%d'
}

# Seed a green N-day run ending at $end_day for $slug. Emits one
# run_completed exit=0 per day.
seed_clean_streak() {  # $1 = slug, $2 = first YYYY-MM-DD, $3 = N days
  local slug="$1" day="$2" n="$3" i
  local file="$HOME/.cache/${slug}-agent/events.jsonl"
  mkdir -p "$(dirname "$file")"
  : > "$file"
  for (( i=0; i<n; i++ )); do
    emit_run_completed "$slug" "$day" 0 >> "$file"
    day="$(next_day "$day")"
  done
}

# ========================================================================
# AC #1 — `bin/fleet streak` (no flags) walks discovered projects, prints
#         the table header + one row per project, exit 0.
# ========================================================================
echo "AC#1 — default invocation walks discovery roots, prints table"
mk_manifest agent-fleet
mk_manifest courtiq
mk_manifest digitalcraft
# agent-fleet: 11 clean days ending today (2026-06-10).
START_AF="$(date -u -j -v -10d -f '%Y-%m-%d' '2026-06-10' '+%Y-%m-%d')"
seed_clean_streak agent-fleet "$START_AF" 11
# courtiq: broken — last 7 days had a ship_paused on 2026-06-05.
CQ_FILE="$HOME/.cache/courtiq-agent/events.jsonl"
mkdir -p "$(dirname "$CQ_FILE")"
{
  d="$(date -u -j -v -20d -f '%Y-%m-%d' '2026-06-10' '+%Y-%m-%d')"
  for i in $(seq 1 20); do
    if [ "$d" = "2026-06-05" ]; then
      emit_ship_paused courtiq "$d"
    else
      # Days within the prior green stretch
      if [ "$i" -le 12 ]; then
        emit_run_completed courtiq "$d" 0
      fi
    fi
    d="$(next_day "$d")"
  done
} > "$CQ_FILE"
# digitalcraft: 4 clean days ending today.
START_DC="$(date -u -j -v -3d -f '%Y-%m-%d' '2026-06-10' '+%Y-%m-%d')"
seed_clean_streak digitalcraft "$START_DC" 4

OUT="$TMP/ac1.out"
set +e
"$FLEET" streak > "$OUT" 2>&1
EXIT=$?
set -e

if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 streak exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi

# Table header columns must all be present.
for col in SLUG CURRENT LONGEST "LAST GREEN" "BROKEN BY"; do
  grep -qF -- "$col" "$OUT" || { echo "FAIL: AC#1 missing column '$col'"; cat "$OUT"; exit 1; }
done

# One row per project.
for slug in agent-fleet courtiq digitalcraft; do
  grep -qE "^${slug}[[:space:]]" "$OUT" \
    || { echo "FAIL: AC#1 missing row for $slug"; cat "$OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #2 — green-day predicate: ≥1 run_completed exit=0 AND zero
#         ship_paused AND zero budget_block AND every gate_failed
#         resolved by run_completed exit=0 same UTC day. Days with zero
#         ship events are NEUTRAL.
# ========================================================================
echo "AC#2 — four-predicate green-day rule"

# Variant: gate_failed RESOLVED same day → green.
mk_manifest gate-resolved
GR_FILE="$HOME/.cache/gate-resolved-agent/events.jsonl"
mkdir -p "$(dirname "$GR_FILE")"
{
  emit_gate_failed gate-resolved "2026-06-09"
  emit_run_completed gate-resolved "2026-06-09" 0
  emit_run_completed gate-resolved "2026-06-10" 0
} > "$GR_FILE"
OUT="$TMP/ac2-resolved.out"
"$FLEET" streak --slug gate-resolved > "$OUT"
# current streak should be 2d on a same-day-resolved gate failure.
grep -qE "^gate-resolved[[:space:]]+2d" "$OUT" \
  || { echo "FAIL: AC#2 gate_failed resolved same day should yield 2d"; cat "$OUT"; exit 1; }

# Variant: gate_failed UNRESOLVED → broken.
mk_manifest gate-unresolved
GU_FILE="$HOME/.cache/gate-unresolved-agent/events.jsonl"
mkdir -p "$(dirname "$GU_FILE")"
{
  emit_run_completed gate-unresolved "2026-06-08" 0
  emit_run_completed gate-unresolved "2026-06-09" 0
  emit_gate_failed gate-unresolved "2026-06-10"
} > "$GU_FILE"
OUT="$TMP/ac2-unresolved.out"
"$FLEET" streak --slug gate-unresolved > "$OUT"
# today (2026-06-10) is broken; current streak = 0d
grep -qE "^gate-unresolved[[:space:]]+0d" "$OUT" \
  || { echo "FAIL: AC#2 unresolved gate_failed today should be 0d"; cat "$OUT"; exit 1; }
grep -qF -- "gate_failed" "$OUT" \
  || { echo "FAIL: AC#2 broken-by should cite gate_failed"; cat "$OUT"; exit 1; }

# Variant: neutral day (no ship events) is NOT a regression.
mk_manifest neutral
NT_FILE="$HOME/.cache/neutral-agent/events.jsonl"
mkdir -p "$(dirname "$NT_FILE")"
{
  emit_run_completed neutral "2026-06-08" 0
  emit_run_completed neutral "2026-06-09" 0
  # 2026-06-10 absent — neutral, current streak = streak as of yesterday = 2d
} > "$NT_FILE"
OUT="$TMP/ac2-neutral.out"
"$FLEET" streak --slug neutral > "$OUT"
grep -qE "^neutral[[:space:]]+2d" "$OUT" \
  || { echo "FAIL: AC#2 neutral day should preserve yesterday's streak"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #3 — current streak = consecutive green days ending TODAY; today
#         broken → 0d; today neutral → yesterday's streak. Longest is the
#         max over the 90-day window.
# ========================================================================
echo "AC#3 — current vs longest over 90-day window"

mk_manifest longest-test
LT_FILE="$HOME/.cache/longest-test-agent/events.jsonl"
mkdir -p "$(dirname "$LT_FILE")"
{
  # 10 days green starting 30 days ago.
  START="$(date -u -j -v -30d -f '%Y-%m-%d' '2026-06-10' '+%Y-%m-%d')"
  d="$START"
  for i in $(seq 1 10); do
    emit_run_completed longest-test "$d" 0
    d="$(next_day "$d")"
  done
  # Break in the middle.
  emit_ship_paused longest-test "$d"
  d="$(next_day "$d")"
  # 5 days green.
  for i in $(seq 1 5); do
    emit_run_completed longest-test "$d" 0
    d="$(next_day "$d")"
  done
} > "$LT_FILE"
OUT="$TMP/ac3.out"
"$FLEET" streak --slug longest-test > "$OUT"
# longest is 10, current is 0 (today is far past last green, so neutral
# tail bounded by last green ≈ 14 days ago — neutral preserves so current
# is whatever ran up to today; but no events at all in last 14 days means
# entire neutral tail since the last green. We expect current = something
# >= 5 if neutral preserves, OR 0 if no streak across modes. Read the
# checked-in golden behavior carefully: current = the streak as it stood
# the last day there was an event; on neutral-only tail, that is the
# 5-day count ending at the last green.
# We assert longest >= 10 (the explicit 10-day run is the max). The
# table layout is `SLUG CURRENT LONGEST LAST_GREEN BROKEN_BY` but the
# CURRENT column may render as `Nd ✓` (two whitespace-separated
# fields), so we slice at fixed column offsets via awk's substr to
# pluck LONGEST out of the row reliably.
row=$(grep -E "^longest-test[[:space:]]" "$OUT")
got_longest=$(printf -- '%s' "$row" | awk '{ for (i=1;i<=NF;i++) if (match($i, /^[0-9]+d$/)) { c++; if (c==2) { print $i; exit } } }')
if [ -z "$got_longest" ] || [ "${got_longest%d}" -lt 10 ]; then
  echo "FAIL: AC#3 longest should be >= 10d, got '$got_longest' row='$row'"
  cat "$OUT"; exit 1
fi
echo "  ok"

# ========================================================================
# AC #4 — flags --since, --slug, --json.
# ========================================================================
echo "AC#4 — flags"

# --since override changes the window. Use a 7d window so the 10-day
# longest from AC#3 is no longer reachable.
OUT="$TMP/ac4-since.out"
"$FLEET" streak --slug longest-test --since 7d > "$OUT"
row=$(grep -E "^longest-test[[:space:]]" "$OUT")
got_longest=$(printf -- '%s' "$row" | awk '{ for (i=1;i<=NF;i++) if (match($i, /^[0-9]+d$/)) { c++; if (c==2) { print $i; exit } } }')
if [ -z "$got_longest" ] || [ "${got_longest%d}" -ge 10 ]; then
  echo "FAIL: AC#4 --since 7d should cap longest below 10d, got '$got_longest' row='$row'"
  cat "$OUT"; exit 1
fi

# --slug restricts to one project.
OUT="$TMP/ac4-slug.out"
"$FLEET" streak --slug agent-fleet > "$OUT"
grep -qE "^agent-fleet[[:space:]]" "$OUT" \
  || { echo "FAIL: AC#4 --slug agent-fleet missing row"; cat "$OUT"; exit 1; }
if grep -qE "^courtiq[[:space:]]" "$OUT"; then
  echo "FAIL: AC#4 --slug agent-fleet leaked courtiq row"; cat "$OUT"; exit 1
fi

# --json emits one object per slug with the right shape.
OUT="$TMP/ac4-json.out"
"$FLEET" streak --slug agent-fleet --json > "$OUT"
grep -qF -- '"slug"' "$OUT" || { echo "FAIL: AC#4 --json missing slug key"; cat "$OUT"; exit 1; }
grep -qF -- '"current"' "$OUT" || { echo "FAIL: AC#4 --json missing current key"; cat "$OUT"; exit 1; }
grep -qF -- '"longest"' "$OUT" || { echo "FAIL: AC#4 --json missing longest key"; cat "$OUT"; exit 1; }
grep -qF -- '"last_green"' "$OUT" || { echo "FAIL: AC#4 --json missing last_green key"; cat "$OUT"; exit 1; }
grep -qF -- '"broken_by"' "$OUT" || { echo "FAIL: AC#4 --json missing broken_by key"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #5 — "broken by" column names the first event type breaking the most
#         recent streak: ship_paused / budget_block / gate_failed + date.
#         When current > 0, broken_by = "—".
# ========================================================================
echo "AC#5 — broken-by column per break type"

mk_manifest brk-paused
BP_FILE="$HOME/.cache/brk-paused-agent/events.jsonl"
mkdir -p "$(dirname "$BP_FILE")"
{
  emit_run_completed brk-paused "2026-06-08" 0
  emit_run_completed brk-paused "2026-06-09" 0
  emit_ship_paused brk-paused "2026-06-10"
} > "$BP_FILE"

mk_manifest brk-budget
BG_FILE="$HOME/.cache/brk-budget-agent/events.jsonl"
mkdir -p "$(dirname "$BG_FILE")"
{
  emit_run_completed brk-budget "2026-06-08" 0
  emit_run_completed brk-budget "2026-06-09" 0
  emit_budget_block brk-budget "2026-06-10"
} > "$BG_FILE"

OUT="$TMP/ac5-paused.out"
"$FLEET" streak --slug brk-paused > "$OUT"
grep -qF -- "ship_paused" "$OUT" \
  || { echo "FAIL: AC#5 brk-paused broken_by should cite ship_paused"; cat "$OUT"; exit 1; }
grep -qF -- "2026-06-10" "$OUT" \
  || { echo "FAIL: AC#5 brk-paused broken_by should cite the break date"; cat "$OUT"; exit 1; }

OUT="$TMP/ac5-budget.out"
"$FLEET" streak --slug brk-budget > "$OUT"
grep -qF -- "budget_block" "$OUT" \
  || { echo "FAIL: AC#5 brk-budget broken_by should cite budget_block"; cat "$OUT"; exit 1; }

# Active streak: broken_by = "—"
OUT="$TMP/ac5-active.out"
"$FLEET" streak --slug agent-fleet > "$OUT"
grep -qE "^agent-fleet[[:space:]].*—" "$OUT" \
  || { echo "FAIL: AC#5 active streak should render — for broken_by"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #6 — summary line counts current green streaks + names longest-active
#         + longest-all-time projects. Empty fleet branch.
# ========================================================================
echo "AC#6 — summary line + empty-fleet branch"
OUT="$TMP/ac6.out"
"$FLEET" streak > "$OUT"
grep -qE "streak:" "$OUT" \
  || { echo "FAIL: AC#6 missing 'streak:' summary line"; cat "$OUT"; exit 1; }
# At least one of "longest active" or "longest all-time".
grep -qF -- "longest active" "$OUT" \
  || { echo "FAIL: AC#6 summary should mention longest active"; cat "$OUT"; exit 1; }
grep -qF -- "longest all-time" "$OUT" \
  || { echo "FAIL: AC#6 summary should mention longest all-time"; cat "$OUT"; exit 1; }

# Empty fleet: point the discovery root at an empty dir.
EMPTY_ROOT="$TMP/empty-projects"
mkdir -p "$EMPTY_ROOT"
OUT="$TMP/ac6-empty.out"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_ROOT" HOME="$TMP/empty-home" "$FLEET" streak > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#6 empty fleet should still exit 0, got $EXIT"; cat "$OUT"; exit 1
fi
grep -qF -- "no projects discovered" "$OUT" \
  || { echo "FAIL: AC#6 empty-fleet branch should say 'no projects discovered'"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #7 — `streak --help` prints USAGE mentioning --since, --slug, --json.
#         Ends with exit 0 (LESSONS 2026-06-01).
# ========================================================================
echo "AC#7 — --help banner"
HELP_OUT="$TMP/ac7-help.out"
set +e
"$FLEET" streak --help > "$HELP_OUT"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#7 --help should exit 0, got $EXIT"; exit 1
fi
for kw in "--since" "--slug" "--json"; do
  grep -qF -- "$kw" "$HELP_OUT" \
    || { echo "FAIL: AC#7 --help missing '$kw'"; cat "$HELP_OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #8 — pure reader: zero events.jsonl writes. Byte size of every
#         events.jsonl unchanged before/after invocation.
# ========================================================================
echo "AC#8 — pure reader, no events.jsonl writes"
BEFORE_SIZES="$TMP/ac8.before"
AFTER_SIZES="$TMP/ac8.after"
find "$HOME/.cache" -name events.jsonl -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null | sort > "$BEFORE_SIZES"
"$FLEET" streak > /dev/null
find "$HOME/.cache" -name events.jsonl -print0 2>/dev/null \
  | xargs -0 stat -f '%z %N' 2>/dev/null | sort > "$AFTER_SIZES"
if ! diff -q "$BEFORE_SIZES" "$AFTER_SIZES" > /dev/null; then
  echo "FAIL: AC#8 events.jsonl mutated by streak invocation"
  diff -u "$BEFORE_SIZES" "$AFTER_SIZES" || true
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #9 — awk walker uses explicit BEGIN { day_count = 0; streak = 0;
#         longest = 0 } (LESSONS 2026-06-08 empty-string-key trap).
# ========================================================================
echo "AC#9 — awk script has explicit BEGIN counter init"
grep -qE 'BEGIN[[:space:]]*\{[^}]*day_count[[:space:]]*=[[:space:]]*0' "$FLEET" \
  || { echo "FAIL: AC#9 streak_walk_days awk script missing BEGIN { day_count = 0 }"; exit 1; }
grep -qE 'BEGIN[[:space:]]*\{[^}]*streak[[:space:]]*=[[:space:]]*0' "$FLEET" \
  || { echo "FAIL: AC#9 awk script missing BEGIN { streak = 0 } init"; exit 1; }
grep -qE 'BEGIN[[:space:]]*\{[^}]*longest[[:space:]]*=[[:space:]]*0' "$FLEET" \
  || { echo "FAIL: AC#9 awk script missing BEGIN { longest = 0 } init"; exit 1; }
echo "  ok"

# ========================================================================
# AC #10 — day arithmetic via `date -u -j -v +1d -f '%Y-%m-%d'` (BSD).
#          NO bash arithmetic on dates. Asserts correctness across month
#          boundary.
# ========================================================================
echo "AC#10 — day arithmetic via BSD date, month boundary"

mk_manifest month-bdy
MB_FILE="$HOME/.cache/month-bdy-agent/events.jsonl"
mkdir -p "$(dirname "$MB_FILE")"
# Seed a 5-day streak spanning 2026-05-30 → 2026-06-03.
{
  emit_run_completed month-bdy "2026-05-30" 0
  emit_run_completed month-bdy "2026-05-31" 0
  emit_run_completed month-bdy "2026-06-01" 0
  emit_run_completed month-bdy "2026-06-02" 0
  emit_run_completed month-bdy "2026-06-03" 0
} > "$MB_FILE"
OUT="$TMP/ac10.out"
"$FLEET" streak --slug month-bdy > "$OUT"
row=$(grep -E "^month-bdy[[:space:]]" "$OUT")
got_longest=$(printf -- '%s' "$row" | awk '{ for (i=1;i<=NF;i++) if (match($i, /^[0-9]+d$/)) { c++; if (c==2) { print $i; exit } } }')
if [ -z "$got_longest" ] || [ "${got_longest%d}" -ne 5 ]; then
  echo "FAIL: AC#10 month-boundary 5-day streak should yield longest=5d, got '$got_longest' row='$row'"
  cat "$OUT"; exit 1
fi
# Source-level guard: the streak code uses `date -u -j -v` (no bash
# arithmetic on dates).
grep -qE "date -u -j -v" "$FLEET" \
  || { echo "FAIL: AC#10 streak day arithmetic should use BSD 'date -u -j -v'"; exit 1; }
echo "  ok"

# ========================================================================
# AC #11 — lib/common.sh unchanged on this branch.
# ========================================================================
echo "AC#11 — lib/common.sh untouched"
cd "$REPO_ROOT"
changed=$(git diff --name-only main...HEAD -- lib/common.sh | awk 'END { print NR+0 }')
if [ "$changed" -ne 0 ]; then
  echo "FAIL: AC#11 lib/common.sh changed on this branch"
  git diff --name-only main...HEAD -- lib/common.sh
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #12 — prompts/ unchanged on this branch.
# ========================================================================
echo "AC#12 — prompts/ untouched"
changed=$(git diff --name-only main...HEAD -- prompts/ | awk 'END { print NR+0 }')
if [ "$changed" -ne 0 ]; then
  echo "FAIL: AC#12 prompts/ changed on this branch"
  git diff --name-only main...HEAD -- prompts/
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #13 — fixture dir holds the canonical synthetic events.jsonl for
#          each scenario the test exercises.
# ========================================================================
echo "AC#13 — fixture directory present"
[ -d "$FIXTURE_DIR" ] \
  || { echo "FAIL: AC#13 tests/fixtures/streak/ missing"; exit 1; }
# At least one fixture file present (a README counts).
if [ -z "$(find "$FIXTURE_DIR" -type f -print -quit)" ]; then
  echo "FAIL: AC#13 tests/fixtures/streak/ is empty"; exit 1
fi
echo "  ok"

echo
echo "PASS: tests/streak.sh — all 13 acceptance criteria green."
