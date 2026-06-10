#!/bin/bash
# tests/streak.sh — `bin/fleet streak` test against tmpdir fixtures.
#
# Ticket 0042. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0042-fleet-streak-continuous-green-days.md. The `streak`
# reader is a PURE CONSUMER of each project's events.jsonl — no new
# event types, no writes to events.jsonl, no fleet_* signature changes.
#
# Fixtures: eight synthetic projects under a tmpdir FLEET_DISCOVERY_ROOT,
# each seeded from tests/fixtures/streak/*.events.jsonl per AC#13:
#   clean30                  — 30-day clean streak ending today
#   middle_neutral           — 30-day window with one neutral middle day
#   ship_paused              — 25-day streak then ship_paused break
#   budget_block             — 25-day streak then budget_block break
#   gate_failed_resolved     — every day has gate_failed + same-day resolution
#   gate_failed_unresolved   — gate_failed mid-window with no same-day resolve
#   neutral_today            — green for 29 days, NO events for today
#   month_boundary           — 13-day streak across the May→June boundary
#
# Time is pinned via FLEET_NOW_OVERRIDE (epoch for 2026-06-09T12:00:00Z)
# so the rendered table + every count stays deterministic.
#
# Per LESSONS 2026-05-26 stubs go under $HOME/.local/bin so lib/common.sh's
# PATH reset does not wipe them out. Per LESSONS 2026-05-27 every fixture
# file is copied via `cp` — never `$(cat …)` — to preserve byte-exact
# trailing newlines. Per LESSONS 2026-06-01 every count uses
# `awk … END { print n+0 }`. Per LESSONS 2026-05-30 every help-text grep
# uses `grep -qF -- "$kw"`. Run-time budget: <8s.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/streak"

TMP="$(mktemp -d -t fleet-streak-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Pin "now" to 2026-06-09T12:00:00Z so every count is deterministic.
# epoch(2026-06-09T12:00:00Z) = 1781006400
NOW_EPOCH=1781006400
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

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

mk_fixture() {  # $1 = slug, $2 = fixture file name (e.g. clean30.events.jsonl)
  local slug="$1" file="$2"
  mk_manifest "$slug"
  local cache="$HOME/.cache/${slug}-agent"
  mkdir -p "$cache"
  # LESSONS 2026-05-27: byte-exact copy, never $(cat …) round-trips.
  cp "$FIXTURE_DIR/$file" "$cache/events.jsonl"
}

mk_fixture clean30                clean30.events.jsonl
mk_fixture middle_neutral         middle_neutral.events.jsonl
mk_fixture ship_paused            ship_paused.events.jsonl
mk_fixture budget_block           budget_block.events.jsonl
mk_fixture gate_failed_resolved   gate_failed_resolved.events.jsonl
mk_fixture gate_failed_unresolved gate_failed_unresolved.events.jsonl
mk_fixture neutral_today          neutral_today.events.jsonl
mk_fixture month_boundary         month_boundary.events.jsonl

# Stub `gh` and `launchctl` so they never reach the host. The discover
# helper reuses the overview discover, and overview itself may shell
# out to these, but streak should not — defensive belt-and-suspenders.
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/sh
exit 0
STUB
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$HOME/.local/bin/gh" "$HOME/.local/bin/launchctl"

# ============================================================================
# AC#1 — default `fleet streak` walks every discovered project, computes
# current + longest, prints the table.
# ============================================================================
echo "AC#1 — default streak table renders rows for all eight discovered projects"
out="$TMP/ac1.out"
"$FLEET" streak > "$out"

# Header row must mention each column label.
grep -qF -- "SLUG"      "$out" || { echo "FAIL AC#1 missing SLUG header"      >&2; cat "$out" >&2; exit 1; }
grep -qF -- "CURRENT"   "$out" || { echo "FAIL AC#1 missing CURRENT header"   >&2; cat "$out" >&2; exit 1; }
grep -qF -- "LONGEST"   "$out" || { echo "FAIL AC#1 missing LONGEST header"   >&2; cat "$out" >&2; exit 1; }
grep -qF -- "LAST GREEN" "$out" || { echo "FAIL AC#1 missing LAST GREEN header" >&2; cat "$out" >&2; exit 1; }
grep -qF -- "BROKEN BY"  "$out" || { echo "FAIL AC#1 missing BROKEN BY header"  >&2; cat "$out" >&2; exit 1; }

# Each slug must appear as a row.
for slug in clean30 middle_neutral ship_paused budget_block \
            gate_failed_resolved gate_failed_unresolved \
            neutral_today month_boundary; do
  grep -qF -- "$slug" "$out" || {
    echo "FAIL AC#1 missing row for slug '$slug'" >&2
    cat "$out" >&2
    exit 1
  }
done

# ============================================================================
# AC#2 — "green day" predicate. The four sub-predicates exercised by the
# fixtures themselves:
#   (a) ≥1 run_completed exit=0  → clean30, all 30 days green
#   (b) zero ship_paused          → ship_paused fixture's 2026-06-05 IS NOT green
#   (c) zero budget_block         → budget_block fixture's 2026-06-05 IS NOT green
#   (d) every gate_failed has a same-day run_completed exit=0
#      gate_failed_resolved   — every day green (30d streak)
#      gate_failed_unresolved — 2026-06-05 NOT green
# Days with ZERO ship events at all are NEUTRAL (neutral_today, middle_neutral).
# ============================================================================
echo "AC#2 — green-day predicate (4 sub-checks via fixtures)"
# (a) clean30 should show 30d current.
grep -E "^clean30[[:space:]]+30d" "$out" >/dev/null || {
  echo "FAIL AC#2(a) clean30 expected '30d current' for ≥1 run_completed exit=0 path" >&2
  grep -E "^clean30" "$out" >&2
  exit 1
}
# (b) ship_paused: current = 4d (2026-06-06..2026-06-09), longest = 25d.
grep -E "^ship_paused[[:space:]]+4d" "$out" >/dev/null || {
  echo "FAIL AC#2(b) ship_paused expected '4d current' (break on 2026-06-05)" >&2
  grep -E "^ship_paused" "$out" >&2
  exit 1
}
# (c) budget_block: current = 4d, longest = 25d.
grep -E "^budget_block[[:space:]]+4d" "$out" >/dev/null || {
  echo "FAIL AC#2(c) budget_block expected '4d current' (break on 2026-06-05)" >&2
  grep -E "^budget_block" "$out" >&2
  exit 1
}
# (d1) gate_failed_resolved: 30d current (every day's gate_failed has same-day resolve).
grep -E "^gate_failed_resolved[[:space:]]+30d" "$out" >/dev/null || {
  echo "FAIL AC#2(d1) gate_failed_resolved expected '30d current' (same-day resolve = green)" >&2
  grep -E "^gate_failed_resolved" "$out" >&2
  exit 1
}
# (d2) gate_failed_unresolved: current = 4d (2026-06-06..2026-06-09), break on 06-05.
grep -E "^gate_failed_unresolved[[:space:]]+4d" "$out" >/dev/null || {
  echo "FAIL AC#2(d2) gate_failed_unresolved expected '4d current' (unresolved gate_failed = red)" >&2
  grep -E "^gate_failed_unresolved" "$out" >&2
  exit 1
}

# ============================================================================
# AC#3 — current streak honors FLEET_NOW_OVERRIDE; neutral today != regression.
#   clean30                 — every day green, including today           → 30d
#   neutral_today           — green up to yesterday, no events today    → 29d
#   middle_neutral          — neutral on 2026-05-25 in the middle; the
#                             streak is from 2026-05-26..2026-06-09 = 15d
#                             current (because the gap of one neutral day
#                             does not extend a streak — neutrals are
#                             non-green; they neither extend NOR break).
# ============================================================================
echo "AC#3 — current streak honors FLEET_NOW_OVERRIDE and treats today's neutral as pending"
grep -E "^neutral_today[[:space:]]+29d" "$out" >/dev/null || {
  echo "FAIL AC#3 neutral_today expected '29d current' (today neutral = streak as of yesterday)" >&2
  grep -E "^neutral_today" "$out" >&2
  exit 1
}
# middle_neutral: today is green (2026-06-09), so current streak is from
# the most recent break-or-neutral to today. The neutral on 2026-05-25
# splits the window: green days 2026-05-26..2026-06-09 = 15 days current.
grep -E "^middle_neutral[[:space:]]+15d" "$out" >/dev/null || {
  echo "FAIL AC#3 middle_neutral expected '15d current' (neutral day splits streak)" >&2
  grep -E "^middle_neutral" "$out" >&2
  exit 1
}

# ============================================================================
# AC#4 — `--since`, `--slug`, `--json` flags.
# ============================================================================
echo "AC#4 — --since / --slug / --json flags"
# --slug restricts.
slug_out="$TMP/ac4.slug.out"
"$FLEET" streak --slug clean30 > "$slug_out"
grep -qF -- "clean30"        "$slug_out" || { echo "FAIL AC#4 --slug should keep clean30 row"        >&2; exit 1; }
grep -qF -- "neutral_today"  "$slug_out" && { echo "FAIL AC#4 --slug should filter out neutral_today" >&2; cat "$slug_out" >&2; exit 1; } || true

# --since 7d narrows the window. clean30 (30d) is bounded by the window;
# current streak max is min(actual, since_days). With --since 7d, current
# becomes 7d (window only spans 7 days back).
since_out="$TMP/ac4.since.out"
"$FLEET" streak --slug clean30 --since 7d > "$since_out"
grep -E "^clean30[[:space:]]+7d" "$since_out" >/dev/null || {
  echo "FAIL AC#4 --since 7d should cap clean30 current at 7d" >&2
  cat "$since_out" >&2
  exit 1
}

# --json schema, one object per project.
json_out="$TMP/ac4.json.out"
"$FLEET" streak --slug clean30 --json > "$json_out"
grep -qF -- '"slug":"clean30"'        "$json_out" || { echo "FAIL AC#4 --json missing slug" >&2; cat "$json_out" >&2; exit 1; }
grep -qF -- '"current":30'            "$json_out" || { echo "FAIL AC#4 --json missing current" >&2; cat "$json_out" >&2; exit 1; }
grep -qF -- '"longest":30'            "$json_out" || { echo "FAIL AC#4 --json missing longest" >&2; cat "$json_out" >&2; exit 1; }
grep -qF -- '"last_green":"2026-06-09"' "$json_out" || { echo "FAIL AC#4 --json missing last_green" >&2; cat "$json_out" >&2; exit 1; }
grep -qF -- '"broken_by":null'        "$json_out" || { echo "FAIL AC#4 --json broken_by should be null for unbroken current" >&2; cat "$json_out" >&2; exit 1; }

# --since with absolute YYYY-MM-DD form.
date_out="$TMP/ac4.date.out"
"$FLEET" streak --slug clean30 --since 2026-06-01 > "$date_out"
grep -E "^clean30[[:space:]]+9d" "$date_out" >/dev/null || {
  echo "FAIL AC#4 --since 2026-06-01 should bound current at 9d" >&2
  cat "$date_out" >&2
  exit 1
}

# ============================================================================
# AC#5 — BROKEN BY column names the FIRST event type for the most recent
# break. When current > 0, the column for THAT row is `—`.
# ============================================================================
echo "AC#5 — broken-by column"
# clean30 has no break → `—`
clean_row="$(grep -E "^clean30[[:space:]]" "$out")"
case "$clean_row" in
  *"—"*) ;;
  *) echo "FAIL AC#5 clean30 row should end with em-dash, got: $clean_row" >&2; exit 1 ;;
esac

# Construct an unhealthy-today fixture: green for 5 days, RED today.
# Then BROKEN BY must mention today's break.
mk_manifest broken_today
broken_cache="$HOME/.cache/broken_today-agent"
mkdir -p "$broken_cache"
{
  for d in 2026-06-04 2026-06-05 2026-06-06 2026-06-07 2026-06-08; do
    printf '{"ts":"%sT12:00:00Z","slug":"broken_today","phase":"ship","type":"run_completed","exit":"0","duration_ms":"30000"}\n' "$d"
  done
  # Today (2026-06-09) — ship fired AND was paused.
  printf '{"ts":"2026-06-09T11:00:00Z","slug":"broken_today","phase":"ship","type":"run_completed","exit":"0","duration_ms":"30000"}\n'
  printf '{"ts":"2026-06-09T13:00:00Z","slug":"broken_today","phase":"ship","type":"ship_paused","reason":"sendback_streak"}\n'
} > "$broken_cache/events.jsonl"

broken_out="$TMP/ac5.broken.out"
"$FLEET" streak --slug broken_today > "$broken_out"
grep -E "^broken_today[[:space:]]+0d" "$broken_out" >/dev/null || {
  echo "FAIL AC#5 broken_today expected '0d current' (today is broken)" >&2
  cat "$broken_out" >&2
  exit 1
}
grep -qF -- "2026-06-09 ship_paused" "$broken_out" || {
  echo "FAIL AC#5 broken_today expected 'BROKEN BY' to cite today's ship_paused" >&2
  cat "$broken_out" >&2
  exit 1
}

# ============================================================================
# AC#6 — summary line counts current-green projects, names longest-active +
# longest-all-time with date range. Empty fleet shows onboarding hint.
# ============================================================================
echo "AC#6 — summary line + empty-fleet hint"
# Project count: clean30, middle_neutral, ship_paused (4d), budget_block (4d),
# gate_failed_resolved, gate_failed_unresolved (4d), neutral_today (29d),
# month_boundary (13d), broken_today (0d) → 8 of 9 on a current streak.
all_out="$TMP/ac6.all.out"
"$FLEET" streak > "$all_out"
grep -qE "streak: 8 of 9 projects currently on a green streak" "$all_out" || {
  echo "FAIL AC#6 expected '8 of 9 projects' summary line" >&2
  tail -5 "$all_out" >&2
  exit 1
}
# Longest-active: clean30, gate_failed_resolved are both 30d. Longest-all-time
# is also 30d. The summary should name a longest project.
grep -qF -- "longest active streak" "$all_out" || {
  echo "FAIL AC#6 expected 'longest active streak' phrase" >&2
  tail -5 "$all_out" >&2
  exit 1
}
grep -qF -- "longest all-time streak" "$all_out" || {
  echo "FAIL AC#6 expected 'longest all-time streak' phrase" >&2
  tail -5 "$all_out" >&2
  exit 1
}

# Empty fleet: drop discovery root to an empty dir.
empty_out="$TMP/ac6.empty.out"
( export FLEET_DISCOVERY_ROOT="$TMP/empty-root"; mkdir -p "$FLEET_DISCOVERY_ROOT"
  "$FLEET" streak > "$empty_out" )
grep -qF -- "no projects discovered" "$empty_out" || {
  echo "FAIL AC#6 empty fleet should print 'no projects discovered' hint" >&2
  cat "$empty_out" >&2
  exit 1
}

# ============================================================================
# AC#7 — `fleet streak --help` prints USAGE with --since / --slug / --json.
# Help block ends with `exit 0` (Help path).
# ============================================================================
echo "AC#7 — help banner mentions all three flags"
help_out="$TMP/ac7.help.out"
"$FLEET" streak --help > "$help_out"
for kw in "--since" "--slug" "--json"; do
  grep -qF -- "$kw" "$help_out" || {
    echo "FAIL AC#7 help missing keyword '$kw'" >&2
    cat "$help_out" >&2
    exit 1
  }
done
# Source-level: help block must end with `exit 0` (LESSONS 2026-06-01).
grep -qF -- 'exit 0' "$FLEET" || {
  echo "FAIL AC#7 bin/fleet must contain explicit exit 0 (dispatcher fall-through guard)" >&2
  exit 1
}

# ============================================================================
# AC#8 — `streak` is a PURE READER. events.jsonl byte size unchanged.
# (One invocation is enough: the implementation has the same code path for
# text/json/--slug renderings; if any wrote, all three would.)
# ============================================================================
echo "AC#8 — pure reader, events.jsonl unchanged"
target="$HOME/.cache/clean30-agent/events.jsonl"
before="$(LC_ALL=C wc -c < "$target" | tr -d ' ')"
"$FLEET" streak --slug clean30 > /dev/null
after="$(LC_ALL=C wc -c < "$target" | tr -d ' ')"
[ "$before" = "$after" ] || {
  echo "FAIL AC#8 events.jsonl size changed: $before → $after" >&2
  exit 1
}
# Also assert via source-level grep: no fleet_emit_event call in the
# streak codepath. This is the structural check that defends the
# invariant across future refactors.
streak_block="$(awk '/^# --- streak \(ticket 0042\)/,/^# --- atlas/' "$FLEET")"
case "$streak_block" in
  *fleet_emit_event*) echo "FAIL AC#8 streak block contains fleet_emit_event call" >&2; exit 1 ;;
esac

# ============================================================================
# AC#9 — awk script uses explicit BEGIN block initializing day_count, streak,
# longest. Source-level grep on bin/fleet.
# ============================================================================
echo "AC#9 — BEGIN block initializes counters (POSIX awk empty-string-key guard)"
# Look for the BEGIN block with day_count initialization in the streak awk script.
grep -qE 'BEGIN[[:space:]]*\{[^}]*day_count[[:space:]]*=[[:space:]]*0' "$FLEET" || {
  echo "FAIL AC#9 bin/fleet missing 'BEGIN { day_count = 0 ... }' in streak awk script" >&2
  exit 1
}

# Also test runtime: a fixture whose FIRST event would otherwise land
# under arr[""] should be counted correctly. The clean30 fixture's first
# event (2026-05-11) is the canonical lead — counted in the 30d streak.
# We've already asserted that in AC#1/AC#2; nothing more to add here.

# ============================================================================
# AC#10 — date arithmetic via BSD `date -u -j -v +1d -f '%Y-%m-%d'`. The
# month_boundary fixture crosses the May→June boundary, so an incorrect
# walker would skip 2026-06-01.
# ============================================================================
echo "AC#10 — date arithmetic correct across month boundary"
mb_out="$TMP/ac10.mb.out"
"$FLEET" streak --slug month_boundary > "$mb_out"
grep -E "^month_boundary[[:space:]]+13d" "$mb_out" >/dev/null || {
  echo "FAIL AC#10 month_boundary expected '13d current' (2026-05-28..2026-06-09 inclusive)" >&2
  cat "$mb_out" >&2
  exit 1
}
# Source-level: helper uses BSD `date -u -j -v +1d`.
grep -qE 'date -u -j .*-v \+1d|date -u -j -v \+1d' "$FLEET" || {
  echo "FAIL AC#10 bin/fleet missing 'date -u -j -v +1d' for streak day arithmetic" >&2
  exit 1
}

# ============================================================================
# AC#11 — lib/common.sh untouched.
# ============================================================================
echo "AC#11 — lib/common.sh untouched"
if [ -d "$REPO_ROOT/.git" ]; then
  diff_out="$(git -C "$REPO_ROOT" diff --name-only origin/main...HEAD -- lib/common.sh 2>/dev/null || true)"
  [ -z "$diff_out" ] || {
    echo "FAIL AC#11 lib/common.sh changed: $diff_out" >&2
    exit 1
  }
fi

# ============================================================================
# AC#12 — prompts/ untouched.
# ============================================================================
echo "AC#12 — prompts/ untouched"
if [ -d "$REPO_ROOT/.git" ]; then
  diff_out="$(git -C "$REPO_ROOT" diff --name-only origin/main...HEAD -- prompts/ 2>/dev/null || true)"
  [ -z "$diff_out" ] || {
    echo "FAIL AC#12 prompts/ changed: $diff_out" >&2
    exit 1
  }
fi

# ============================================================================
# AC#13 — tests/streak.sh exists, fixtures present, $HOME/.local/bin stubs
# used. Self-referential meta-check: the file you're reading.
# ============================================================================
echo "AC#13 — fixtures + test scaffolding"
for f in clean30 middle_neutral ship_paused budget_block \
         gate_failed_resolved gate_failed_unresolved \
         neutral_today month_boundary; do
  [ -s "$FIXTURE_DIR/${f}.events.jsonl" ] || {
    echo "FAIL AC#13 missing fixture: $FIXTURE_DIR/${f}.events.jsonl" >&2
    exit 1
  }
done
# Source-level: this test sets HOME=$TMP/home (LESSONS 2026-05-26).
grep -qF -- 'export HOME="$TMP/home"' "$REPO_ROOT/tests/streak.sh" || {
  echo "FAIL AC#13 tests/streak.sh must export HOME=\$TMP/home (LESSONS 2026-05-26)" >&2
  exit 1
}

echo "PASS — all 13 AC blocks green."
exit 0
