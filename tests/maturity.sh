#!/bin/bash
# tests/maturity.sh — `bin/fleet maturity <slug>` 7-step activation funnel test.
#
# Ticket 0054. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0054-fleet-maturity-activation-funnel-score.md. `maturity`
# is a PURE READER of events.jsonl + agents.config.sh + CROSS_LESSONS +
# the morning-last-run state file — no new event types, no
# fleet_emit_event calls, no fleet_* signature changes.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-05-30 every help-text grep uses `grep -qF -- "$kw"`.
# Per LESSONS 2026-06-08 awk scripts that index by counter declare
# `BEGIN { count = 0 }`. The clock is frozen via FLEET_NOW_OVERRIDE.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-maturity-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/state/agent-fleet"

# Anchor "today" at 2026-06-15T12:00:00Z.
# Epoch seconds for that moment:
NOW_EPOCH=1781524800
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Seed a manifest at the fixture root for one slug.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Clear all per-slug fixtures between AC blocks so each section starts
# from a single-slug baseline. Per LESSONS 2026-05-27 we copy/remove
# whole subtrees rather than rewrite individual files in place.
reset_fixtures() {
  rm -rf "$FIXTURE_ROOT" "$HOME/.cache"
  mkdir -p "$FIXTURE_ROOT"
  rm -f "$HOME/.local/state/agent-fleet/morning-last-run"
}

mk_manifest() {  # $1 = slug; $2 = optional CROSS_LESSONS path
  local slug="$1" cl="${2-}"
  mkdir -p "$FIXTURE_ROOT/$slug"
  if [ -n "$cl" ]; then
    cat > "$FIXTURE_ROOT/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CROSS_LESSONS="$cl"
CFG
  else
    cat > "$FIXTURE_ROOT/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CFG
  fi
}

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

emit_run_started() {  # $1 = slug, $2 = epoch
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"run_started","pid":"42"}\n' \
    "$(iso_at "$2")" "$1"
}
emit_run_completed() {  # $1 = slug, $2 = epoch, $3 = exit
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"run_completed","exit":"%s","duration_ms":"42"}\n' \
    "$(iso_at "$2")" "$1" "$3"
}
emit_pr_opened() {  # $1 = slug, $2 = epoch, $3 = number
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_opened","number":"%s","branch":"feat/x"}\n' \
    "$(iso_at "$2")" "$1" "$3"
}
emit_pr_footer_posted() {  # $1 = slug, $2 = epoch, $3 = pr number
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_footer_posted","number":"%s"}\n' \
    "$(iso_at "$2")" "$1" "$3"
}
emit_lesson_promoted() {  # $1 = slug, $2 = epoch, $3 = text_sha
  printf '{"ts":"%s","slug":"%s","phase":"promote","type":"lesson_promoted","source":"%s","text_sha":"%s","scope":"all"}\n' \
    "$(iso_at "$2")" "$1" "$1" "$3"
}

byte_size() {  # $1 = file
  if [ -f "$1" ]; then
    awk 'END { print length($0) + 0 }' < /dev/null  # no-op placeholder
    wc -c < "$1" | tr -d ' '
  else
    echo 0
  fi
}

# ========================================================================
# AC #1 — `bin/fleet maturity <slug>` is a new subcommand. Missing slug
#         refusal, unknown slug refusal, both exit 2.
# ========================================================================
echo "AC#1 — missing slug and unknown slug refusals"
mk_manifest sidebrew

OUT="$TMP/ac1a.out"
set +e
"$FLEET" maturity > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 missing slug exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "usage:" "$OUT" \
  || { echo "FAIL: AC#1 missing slug stderr lacks 'usage:'"; cat "$OUT"; exit 1; }
grep -qF -- "bin/fleet maturity <slug>" "$OUT" \
  || { echo "FAIL: AC#1 missing slug stderr lacks subcommand name"; cat "$OUT"; exit 1; }

OUT="$TMP/ac1b.out"
set +e
"$FLEET" maturity nonesuch > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#1 unknown slug exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "slug nonesuch not found" "$OUT" \
  || { echo "FAIL: AC#1 unknown slug stderr lacks 'slug nonesuch not found'"; cat "$OUT"; exit 1; }
grep -qF -- "discovered slugs:" "$OUT" \
  || { echo "FAIL: AC#1 unknown slug stderr lacks 'discovered slugs:'"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #2 — installed-at anchor = first run_started; fallback to mtime;
#         fallback to NOW. "installed N days ago" appears in header.
# ========================================================================
echo "AC#2 — install anchor: run_started, then mtime, then NOW"

# Fixture A: events.jsonl has a run_started 14 days ago.
mk_manifest anchor-a
A_FILE="$HOME/.cache/anchor-a-agent/events.jsonl"
mkdir -p "$(dirname "$A_FILE")"
ANCHOR_A_EPOCH=$(( NOW_EPOCH - 14 * 86400 ))
emit_run_started anchor-a "$ANCHOR_A_EPOCH" > "$A_FILE"
emit_run_completed anchor-a "$ANCHOR_A_EPOCH" 0 >> "$A_FILE"
OUT="$TMP/ac2a.out"
"$FLEET" maturity anchor-a > "$OUT" 2>&1
grep -qF -- "installed 14 days ago" "$OUT" \
  || { echo "FAIL: AC#2a header missing 'installed 14 days ago'"; cat "$OUT"; exit 1; }

# Fixture B: events.jsonl exists but no run_started; mtime = 7 days ago.
mk_manifest anchor-b
B_FILE="$HOME/.cache/anchor-b-agent/events.jsonl"
mkdir -p "$(dirname "$B_FILE")"
echo '{"ts":"2000-01-01T00:00:00Z","slug":"anchor-b","phase":"ship","type":"budget_block"}' > "$B_FILE"
ANCHOR_B_EPOCH=$(( NOW_EPOCH - 7 * 86400 ))
touch -t "$(date -r "$ANCHOR_B_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$ANCHOR_B_EPOCH" '+%Y%m%d%H%M.%S')" "$B_FILE"
OUT="$TMP/ac2b.out"
"$FLEET" maturity anchor-b > "$OUT" 2>&1
grep -qF -- "installed 7 days ago" "$OUT" \
  || { echo "FAIL: AC#2b header missing 'installed 7 days ago' (mtime fallback)"; cat "$OUT"; exit 1; }

# Fixture C: events.jsonl missing entirely → anchor is NOW (0 days).
mk_manifest anchor-c
# No events.jsonl created.
OUT="$TMP/ac2c.out"
"$FLEET" maturity anchor-c > "$OUT" 2>&1
grep -qF -- "installed 0 days ago" "$OUT" \
  || { echo "FAIL: AC#2c header missing 'installed 0 days ago' (NOW fallback)"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #3 — Step 1 HAS_RUN_COMPLETED PASS / PENDING.
# ========================================================================
echo "AC#3 — step 1: HAS_RUN_COMPLETED"
mk_manifest s1pass
S1_FILE="$HOME/.cache/s1pass-agent/events.jsonl"
mkdir -p "$(dirname "$S1_FILE")"
emit_run_started s1pass "$(( NOW_EPOCH - 86400 ))" > "$S1_FILE"
emit_run_completed s1pass "$(( NOW_EPOCH - 3600 ))" 0 >> "$S1_FILE"
OUT="$TMP/ac3pass.out"
"$FLEET" maturity s1pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 1:' "$OUT" \
  || { echo "FAIL: AC#3 PASS line missing"; cat "$OUT"; exit 1; }
grep -qF -- "last completion:" "$OUT" \
  || { echo "FAIL: AC#3 PASS line lacks 'last completion:'"; cat "$OUT"; exit 1; }

mk_manifest s1pend
mkdir -p "$HOME/.cache/s1pend-agent"
: > "$HOME/.cache/s1pend-agent/events.jsonl"
OUT="$TMP/ac3pend.out"
"$FLEET" maturity s1pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 1:' "$OUT" \
  || { echo "FAIL: AC#3 PENDING line missing"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #4 — Step 2 HAS_PR_OPENED PASS / PENDING.
# ========================================================================
echo "AC#4 — step 2: HAS_PR_OPENED"
mk_manifest s2pass
S2_FILE="$HOME/.cache/s2pass-agent/events.jsonl"
mkdir -p "$(dirname "$S2_FILE")"
{
  emit_run_started   s2pass "$(( NOW_EPOCH - 86400 ))"
  emit_run_completed s2pass "$(( NOW_EPOCH - 3600 ))" 0
  emit_pr_opened     s2pass "$(( NOW_EPOCH - 7200 ))" 7
} > "$S2_FILE"
OUT="$TMP/ac4pass.out"
"$FLEET" maturity s2pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 2:' "$OUT" \
  || { echo "FAIL: AC#4 PASS line missing"; cat "$OUT"; exit 1; }

mk_manifest s2pend
S2P_FILE="$HOME/.cache/s2pend-agent/events.jsonl"
mkdir -p "$(dirname "$S2P_FILE")"
emit_run_completed s2pend "$(( NOW_EPOCH - 3600 ))" 0 > "$S2P_FILE"
OUT="$TMP/ac4pend.out"
"$FLEET" maturity s2pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 2:' "$OUT" \
  || { echo "FAIL: AC#4 PENDING line missing"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #5 — Step 3 MORNING_INVOKED: PASS / PASS drifting / PENDING.
# ========================================================================
echo "AC#5 — step 3: MORNING_INVOKED (file present, stale, missing)"
MSTATE="$HOME/.local/state/agent-fleet/morning-last-run"

# (a) Present, recent (1 day ago) → PASS, no drifting.
mk_manifest s3pass
S3_FILE="$HOME/.cache/s3pass-agent/events.jsonl"
mkdir -p "$(dirname "$S3_FILE")"
emit_run_started s3pass "$(( NOW_EPOCH - 86400 ))" > "$S3_FILE"
M1_EPOCH=$(( NOW_EPOCH - 86400 ))
mkdir -p "$(dirname "$MSTATE")"
: > "$MSTATE"
touch -t "$(date -r "$M1_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$M1_EPOCH" '+%Y%m%d%H%M.%S')" "$MSTATE"
OUT="$TMP/ac5pass.out"
"$FLEET" maturity s3pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 3:' "$OUT" \
  || { echo "FAIL: AC#5a PASS step 3 missing"; cat "$OUT"; exit 1; }
if grep -qF -- "drifting" "$OUT"; then
  echo "FAIL: AC#5a fresh morning should NOT say drifting"; cat "$OUT"; exit 1
fi

# (b) Present, stale (> 7 days) → PASS (drifting).
M2_EPOCH=$(( NOW_EPOCH - 9 * 86400 ))
touch -t "$(date -r "$M2_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$M2_EPOCH" '+%Y%m%d%H%M.%S')" "$MSTATE"
OUT="$TMP/ac5drift.out"
"$FLEET" maturity s3pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 3:' "$OUT" \
  || { echo "FAIL: AC#5b stale morning should still be PASS"; cat "$OUT"; exit 1; }
grep -qF -- "drifting" "$OUT" \
  || { echo "FAIL: AC#5b stale morning should say 'drifting'"; cat "$OUT"; exit 1; }

# (c) Missing → PENDING.
rm -f "$MSTATE"
OUT="$TMP/ac5pend.out"
"$FLEET" maturity s3pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 3:' "$OUT" \
  || { echo "FAIL: AC#5c missing morning state should be PENDING"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #6 — Step 4 PR_MERGED: PASS / PENDING / STUCK.
# ========================================================================
echo "AC#6 — step 4: PR_MERGED (pr_opened ↔ pr_footer_posted)"

# (a) PASS: pr_opened + matching pr_footer_posted.
mk_manifest s4pass
S4_FILE="$HOME/.cache/s4pass-agent/events.jsonl"
mkdir -p "$(dirname "$S4_FILE")"
{
  emit_run_started      s4pass "$(( NOW_EPOCH - 5 * 86400 ))"
  emit_pr_opened        s4pass "$(( NOW_EPOCH - 5 * 86400 ))" 11
  emit_pr_footer_posted s4pass "$(( NOW_EPOCH - 4 * 86400 ))" 11
} > "$S4_FILE"
OUT="$TMP/ac6pass.out"
"$FLEET" maturity s4pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 4:' "$OUT" \
  || { echo "FAIL: AC#6a PASS step 4 missing"; cat "$OUT"; exit 1; }

# (b) PENDING: no pr_opened at all.
mk_manifest s4pend
S4P_FILE="$HOME/.cache/s4pend-agent/events.jsonl"
mkdir -p "$(dirname "$S4P_FILE")"
emit_run_started s4pend "$(( NOW_EPOCH - 86400 ))" > "$S4P_FILE"
OUT="$TMP/ac6pend.out"
"$FLEET" maturity s4pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 4:' "$OUT" \
  || { echo "FAIL: AC#6b PENDING step 4 missing"; cat "$OUT"; exit 1; }

# (c) STUCK: pr_opened ≥1 but no pr_footer_posted and oldest unmerged
#     PR is older than 48h.
mk_manifest s4stuck
S4S_FILE="$HOME/.cache/s4stuck-agent/events.jsonl"
mkdir -p "$(dirname "$S4S_FILE")"
{
  emit_run_started s4stuck "$(( NOW_EPOCH - 5 * 86400 ))"
  emit_pr_opened   s4stuck "$(( NOW_EPOCH - 5 * 86400 ))" 1
} > "$S4S_FILE"
OUT="$TMP/ac6stuck.out"
"$FLEET" maturity s4stuck > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[STUCK\][[:space:]]+step 4:' "$OUT" \
  || { echo "FAIL: AC#6c STUCK step 4 missing"; cat "$OUT"; exit 1; }
grep -qF -- "fleet doctor" "$OUT" \
  || { echo "FAIL: AC#6c STUCK nudge should suggest fleet doctor"; cat "$OUT"; exit 1; }
echo "  ok"

# NOTE: AC#10 reuses s4stuck for the STUCK footer assertion. We do
# reset AC#7-#9 fixtures separately, then re-create s4stuck inside
# AC#10 itself.

reset_fixtures

# ========================================================================
# AC #7 — Step 5 LESSON_PROMOTED.
# ========================================================================
echo "AC#7 — step 5: LESSON_PROMOTED"
mk_manifest s5pass
S5_FILE="$HOME/.cache/s5pass-agent/events.jsonl"
mkdir -p "$(dirname "$S5_FILE")"
{
  emit_run_started     s5pass "$(( NOW_EPOCH - 14 * 86400 ))"
  emit_lesson_promoted s5pass "$(( NOW_EPOCH - 86400 ))" "abc12345"
} > "$S5_FILE"
OUT="$TMP/ac7pass.out"
"$FLEET" maturity s5pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 5:' "$OUT" \
  || { echo "FAIL: AC#7 PASS step 5 missing"; cat "$OUT"; exit 1; }

mk_manifest s5pend
S5P_FILE="$HOME/.cache/s5pend-agent/events.jsonl"
mkdir -p "$(dirname "$S5P_FILE")"
emit_run_started s5pend "$(( NOW_EPOCH - 86400 ))" > "$S5P_FILE"
OUT="$TMP/ac7pend.out"
"$FLEET" maturity s5pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 5:' "$OUT" \
  || { echo "FAIL: AC#7 PENDING step 5 missing"; cat "$OUT"; exit 1; }
grep -qF -- "lessons-promote" "$OUT" \
  || { echo "FAIL: AC#7 PENDING step 5 nudge should mention lessons-promote"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #8 — Step 6 STREAK_STARTED via `fleet streak --json` ≥ 7.
# ========================================================================
echo "AC#8 — step 6: STREAK_STARTED (fleet streak --json ≥7)"

# (a) PASS: ≥7 consecutive green days.
mk_manifest s6pass
S6_FILE="$HOME/.cache/s6pass-agent/events.jsonl"
mkdir -p "$(dirname "$S6_FILE")"
emit_run_started s6pass "$(( NOW_EPOCH - 10 * 86400 ))" > "$S6_FILE"
for i in 7 6 5 4 3 2 1 0; do
  EP=$(( NOW_EPOCH - i * 86400 ))
  # Day-stamp the run at noon to keep day boundaries clean.
  DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
  printf '{"ts":"%sT12:00:00Z","slug":"s6pass","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
    "$DAY" >> "$S6_FILE"
done
OUT="$TMP/ac8pass.out"
"$FLEET" maturity s6pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 6:' "$OUT" \
  || { echo "FAIL: AC#8 PASS step 6 missing — streak should be ≥7"; cat "$OUT"; exit 1; }

# (b) PENDING: only 3 green days.
mk_manifest s6pend
S6P_FILE="$HOME/.cache/s6pend-agent/events.jsonl"
mkdir -p "$(dirname "$S6P_FILE")"
emit_run_started s6pend "$(( NOW_EPOCH - 10 * 86400 ))" > "$S6P_FILE"
for i in 2 1 0; do
  EP=$(( NOW_EPOCH - i * 86400 ))
  DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
  printf '{"ts":"%sT12:00:00Z","slug":"s6pend","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
    "$DAY" >> "$S6P_FILE"
done
OUT="$TMP/ac8pend.out"
"$FLEET" maturity s6pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 6:' "$OUT" \
  || { echo "FAIL: AC#8 PENDING step 6 missing"; cat "$OUT"; exit 1; }
grep -qE "[0-9]+/7" "$OUT" \
  || { echo "FAIL: AC#8 PENDING step 6 should show N/7"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #9 — Step 7 CROSS_LESSON_CITED: manifest has CROSS_LESSONS AND a
#         heading matches a lesson_promoted event (fuzzy substring).
# ========================================================================
echo "AC#9 — step 7: CROSS_LESSON_CITED"

# Seed a CROSS_LESSONS.md feed.
CL_PATH="$TMP/CROSS_LESSONS.md"
cat > "$CL_PATH" <<'EOF'
# CROSS_LESSONS

## courtiq

## 2026-06-10 — printf leading dash trap
Use `printf --` to defuse leading-dash interpretation.

## sidebrew

## 2026-06-12 — awk middle empty field sentinel
Use `-` as a sentinel column when a middle TSV field can be empty.
EOF

# (a) PASS: manifest has CROSS_LESSONS, lesson_promoted text_sha matches a
#     heading. We use a separate scalar field on the event — the title in
#     the headline. We seed a lesson_promoted event whose `headline` field
#     equals one of the cross feed titles for the fuzzy match.
mk_manifest s7pass "$CL_PATH"
S7_FILE="$HOME/.cache/s7pass-agent/events.jsonl"
mkdir -p "$(dirname "$S7_FILE")"
{
  emit_run_started s7pass "$(( NOW_EPOCH - 14 * 86400 ))"
  # Emit a lesson_promoted event whose `headline` matches one of the
  # CROSS_LESSONS titles for the fuzzy lowercase-substring match.
  printf '{"ts":"%s","slug":"s7pass","phase":"promote","type":"lesson_promoted","source":"s7pass","text_sha":"deadbeef","scope":"all","headline":"printf leading dash trap"}\n' \
    "$(iso_at "$(( NOW_EPOCH - 86400 ))")"
} > "$S7_FILE"
OUT="$TMP/ac9pass.out"
"$FLEET" maturity s7pass > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 7:' "$OUT" \
  || { echo "FAIL: AC#9 PASS step 7 missing"; cat "$OUT"; exit 1; }

# (b) PENDING: manifest sets CROSS_LESSONS but no lesson_promoted matches.
mk_manifest s7pend "$CL_PATH"
S7P_FILE="$HOME/.cache/s7pend-agent/events.jsonl"
mkdir -p "$(dirname "$S7P_FILE")"
emit_run_started s7pend "$(( NOW_EPOCH - 14 * 86400 ))" > "$S7P_FILE"
OUT="$TMP/ac9pend.out"
"$FLEET" maturity s7pend > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 7:' "$OUT" \
  || { echo "FAIL: AC#9 PENDING step 7 missing"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #10 — next-nudge footer: lowest STUCK > lowest PENDING > none.
# ========================================================================
reset_fixtures
echo "AC#10 — next nudge footer prioritizes lowest STUCK then PENDING"

# Re-seed s4stuck for the STUCK case (resets above wiped it).
mk_manifest s4stuck
S4S_FILE="$HOME/.cache/s4stuck-agent/events.jsonl"
mkdir -p "$(dirname "$S4S_FILE")"
{
  emit_run_started s4stuck "$(( NOW_EPOCH - 5 * 86400 ))"
  emit_pr_opened   s4stuck "$(( NOW_EPOCH - 5 * 86400 ))" 1
} > "$S4S_FILE"

# Stuck case.
OUT="$TMP/ac10stuck.out"
"$FLEET" maturity s4stuck > "$OUT" 2>&1
grep -qE '^next nudge:' "$OUT" \
  || { echo "FAIL: AC#10 missing 'next nudge:' footer"; cat "$OUT"; exit 1; }
# The stuck step 4 nudge should be cited.
grep -qE 'next nudge:.*step 4' "$OUT" \
  || { echo "FAIL: AC#10 stuck footer should reference step 4"; cat "$OUT"; exit 1; }

# Pending-only case: a fresh slug with no events at all → every step
# PENDING, lowest is step 1.
mk_manifest pendall
mkdir -p "$HOME/.cache/pendall-agent"
: > "$HOME/.cache/pendall-agent/events.jsonl"
OUT="$TMP/ac10pend.out"
"$FLEET" maturity pendall > "$OUT" 2>&1
grep -qE 'next nudge:.*step 1' "$OUT" \
  || { echo "FAIL: AC#10 pending footer should reference step 1"; cat "$OUT"; exit 1; }

# All-PASS case: build a fixture where every step PASSes.
mk_manifest fully "$CL_PATH"
FULL_FILE="$HOME/.cache/fully-agent/events.jsonl"
mkdir -p "$(dirname "$FULL_FILE")"
{
  emit_run_started     fully "$(( NOW_EPOCH - 30 * 86400 ))"
  emit_run_completed   fully "$(( NOW_EPOCH - 3600 ))" 0
  emit_pr_opened       fully "$(( NOW_EPOCH - 10 * 86400 ))" 1
  emit_pr_footer_posted fully "$(( NOW_EPOCH - 9 * 86400 ))" 1
  emit_lesson_promoted fully "$(( NOW_EPOCH - 5 * 86400 ))" "feedface"
  printf '{"ts":"%s","slug":"fully","phase":"promote","type":"lesson_promoted","source":"fully","text_sha":"cafebabe","scope":"all","headline":"printf leading dash trap"}\n' \
    "$(iso_at "$(( NOW_EPOCH - 86400 ))")"
} > "$FULL_FILE"
# Seed 8 consecutive green days.
for i in 7 6 5 4 3 2 1 0; do
  EP=$(( NOW_EPOCH - i * 86400 ))
  DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
  printf '{"ts":"%sT11:00:00Z","slug":"fully","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
    "$DAY" >> "$FULL_FILE"
done
# Seed a fresh morning-last-run.
mkdir -p "$(dirname "$MSTATE")"
: > "$MSTATE"
touch -t "$(date -r "$(( NOW_EPOCH - 3600 ))" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$(( NOW_EPOCH - 3600 ))" '+%Y%m%d%H%M.%S')" "$MSTATE"
OUT="$TMP/ac10full.out"
"$FLEET" maturity fully > "$OUT" 2>&1
grep -qF -- "fully activated" "$OUT" \
  || { echo "FAIL: AC#10 all-PASS footer should say 'fully activated'"; cat "$OUT"; exit 1; }
grep -qF -- "fleet portfolio --redact" "$OUT" \
  || { echo "FAIL: AC#10 all-PASS footer should suggest 'fleet portfolio --redact'"; cat "$OUT"; exit 1; }
# Leave MSTATE in place so AC#11 can re-score `fully` as 7/7. (Earlier
# step-3 tests already restored their own state file before checking.)
echo "  ok"

# ========================================================================
# AC #11 — `bin/fleet maturity --all` prints one line per slug, sorted
#          ascending by score. Three fixtures with varying scores.
# ========================================================================
echo "AC#11 — --all prints one line per slug sorted by score asc"
# Use s1pend (0/7) and s2pass (1/7 actually 2/7), and fully (7/7).
OUT="$TMP/ac11.out"
"$FLEET" maturity --all > "$OUT" 2>&1
# Three of our fixture slugs must each appear on a line by themselves.
# (We intentionally do not pin the exact score since it depends on
# the cumulative fixture state. We assert presence + ordering only.)
grep -qE '^pendall[[:space:]]' "$OUT" \
  || { echo "FAIL: AC#11 missing 'pendall' line"; cat "$OUT"; exit 1; }
grep -qE '^fully[[:space:]]+7/7' "$OUT" \
  || { echo "FAIL: AC#11 missing 'fully 7/7' line"; cat "$OUT"; exit 1; }
# Sort: the lowest-scoring slug must appear BEFORE the fully-activated one.
awk '/^pendall[[:space:]]/ { p1 = NR } /^fully[[:space:]]/ { pf = NR } END { if (p1 > pf) exit 1 }' "$OUT" \
  || { echo "FAIL: AC#11 --all not sorted ascending by score"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #12 — --since accepts Nd or YYYY-MM-DD; the YYYY-MM-DD branch
#          appends T00:00:00 before BSD date (LESSONS 2026-06-11).
# ========================================================================
echo "AC#12 — --since Nd and --since YYYY-MM-DD"
mk_manifest s12
S12_FILE="$HOME/.cache/s12-agent/events.jsonl"
mkdir -p "$(dirname "$S12_FILE")"
{
  emit_run_started   s12 "$(( NOW_EPOCH - 60 * 86400 ))"
  # Run_completed 45 days ago — outside default 30d window but inside 90d.
  emit_run_completed s12 "$(( NOW_EPOCH - 45 * 86400 ))" 0
} > "$S12_FILE"

OUT="$TMP/ac12a.out"
"$FLEET" maturity s12 > "$OUT" 2>&1
# Default 30d → step 1 is PENDING (no run_completed inside).
grep -qE '^[[:space:]]*\[PENDING\][[:space:]]+step 1:' "$OUT" \
  || { echo "FAIL: AC#12 default 30d window should yield PENDING step 1"; cat "$OUT"; exit 1; }

OUT="$TMP/ac12b.out"
"$FLEET" maturity s12 --since 90d > "$OUT" 2>&1
# 90d window → step 1 is PASS.
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 1:' "$OUT" \
  || { echo "FAIL: AC#12 --since 90d should yield PASS step 1"; cat "$OUT"; exit 1; }

# YYYY-MM-DD branch — pick an early date.
OUT="$TMP/ac12c.out"
"$FLEET" maturity s12 --since 2026-01-01 > "$OUT" 2>&1
grep -qE '^[[:space:]]*\[PASS\][[:space:]]+step 1:' "$OUT" \
  || { echo "FAIL: AC#12 --since 2026-01-01 should yield PASS step 1"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #13 — --json emits a structured JSON object that Node parses.
# ========================================================================
echo "AC#13 — --json parses as a structured object"
# Re-seed `fully` (resets above wiped it).
mk_manifest fully "$CL_PATH"
FULL_FILE="$HOME/.cache/fully-agent/events.jsonl"
mkdir -p "$(dirname "$FULL_FILE")"
{
  emit_run_started     fully "$(( NOW_EPOCH - 30 * 86400 ))"
  emit_run_completed   fully "$(( NOW_EPOCH - 3600 ))" 0
  emit_pr_opened       fully "$(( NOW_EPOCH - 10 * 86400 ))" 1
  emit_pr_footer_posted fully "$(( NOW_EPOCH - 9 * 86400 ))" 1
  emit_lesson_promoted fully "$(( NOW_EPOCH - 5 * 86400 ))" "feedface"
  printf '{"ts":"%s","slug":"fully","phase":"promote","type":"lesson_promoted","source":"fully","text_sha":"cafebabe","scope":"all","headline":"printf leading dash trap"}\n' \
    "$(iso_at "$(( NOW_EPOCH - 86400 ))")"
} > "$FULL_FILE"
for i in 7 6 5 4 3 2 1 0; do
  EP=$(( NOW_EPOCH - i * 86400 ))
  DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
  printf '{"ts":"%sT11:00:00Z","slug":"fully","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
    "$DAY" >> "$FULL_FILE"
done
mkdir -p "$(dirname "$MSTATE")"
: > "$MSTATE"
touch -t "$(date -r "$(( NOW_EPOCH - 3600 ))" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$(( NOW_EPOCH - 3600 ))" '+%Y%m%d%H%M.%S')" "$MSTATE"

OUT="$TMP/ac13.out"
"$FLEET" maturity fully --json > "$OUT" 2>&1
node -e '
  const fs = require("fs");
  const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (typeof o.slug !== "string") throw new Error("slug missing");
  if (o.slug !== "fully") throw new Error("slug != fully: " + o.slug);
  if (typeof o.installed_days_ago !== "number") throw new Error("installed_days_ago missing");
  if (typeof o.score !== "number") throw new Error("score missing");
  if (!Array.isArray(o.steps) || o.steps.length !== 7) throw new Error("steps != 7");
  for (const s of o.steps) {
    if (typeof s.id !== "string") throw new Error("step id");
    if (!["PASS","PENDING","STUCK"].includes(s.status)) throw new Error("bad status: " + s.status);
    if (typeof s.nudge !== "string") throw new Error("nudge missing");
  }
  if (typeof o.next_nudge !== "string") throw new Error("next_nudge missing");
' "$OUT" || { echo "FAIL: AC#13 JSON parse"; cat "$OUT"; exit 1; }
echo "  ok"

# ========================================================================
# AC #14 — --help prints USAGE mentioning slug, --all, --since, --json.
# ========================================================================
echo "AC#14 — --help mentions slug + --all + --since + --json"
OUT="$TMP/ac14.out"
"$FLEET" maturity --help > "$OUT" 2>&1
for kw in "<slug>" "--all" "--since" "--json"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#14 help missing keyword '$kw'"; cat "$OUT"; exit 1; }
done
echo "  ok"

# ========================================================================
# AC #15 — pure reader: events.jsonl byte size unchanged before vs after.
# ========================================================================
echo "AC#15 — pure reader: events.jsonl byte size unchanged"
B4="$(wc -c < "$FULL_FILE" | tr -d ' ')"
"$FLEET" maturity fully > /dev/null 2>&1
"$FLEET" maturity fully --json > /dev/null 2>&1
"$FLEET" maturity --all > /dev/null 2>&1
AFTER="$(wc -c < "$FULL_FILE" | tr -d ' ')"
if [ "$B4" != "$AFTER" ]; then
  echo "FAIL: AC#15 events.jsonl size changed: $B4 -> $AFTER"
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #16 — lib/common.sh and prompts/ untouched (verified by git diff
#          against main).
# ========================================================================
echo "AC#16 — lib/common.sh and prompts/ untouched on this branch"
cd "$REPO_ROOT"
DIFF="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$DIFF" ]; then
  echo "FAIL: AC#16 lib/common.sh or prompts/ changed:"
  echo "$DIFF"
  exit 1
fi
echo "  ok"

echo
echo "tests/maturity.sh: all 16 ACs PASS"
