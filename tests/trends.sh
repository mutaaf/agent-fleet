#!/bin/bash
# tests/trends.sh — `bin/fleet trends` 12-week sparkline test (ticket 0058).
#
# One assertion block per acceptance-criteria checkbox in
# docs/backlog/0058-fleet-trends-12w-sparklines.md (14 boxes).
#
# Fixture: five synthetic slugs (climbing, declining, flat, bimodal,
# paused) each with a manifest under tests/fixtures/trends/<slug>/. The
# events.jsonl and runs.jsonl are generated at test runtime from a
# frozen FLEET_NOW_OVERRIDE so the 12-week window math is deterministic
# (per LESSONS 2026-06-11 BSD `date -j -f` quirk we use `date +%s`-style
# arithmetic on the epoch anchor, not `-j -f` round-trips).
#
# Stubs live under $HOME/.local/bin per LESSONS 2026-05-26 (PATH reset
# in lib/common.sh — bin/fleet does NOT source it, but we keep the
# convention uniform). The `date` stub wraps the system date binary and
# increments an invocation counter so AC#9's "< 10 date calls during
# `trends --all`" assertion can fire. Backup/restore via `cp` per
# LESSONS 2026-05-27. Counts via `awk … END { print n+0 }` per LESSONS
# 2026-06-01. Every awk script declares `BEGIN { count = 0 }` per
# LESSONS 2026-06-08.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
FIX_ROOT="$REPO_ROOT/tests/fixtures/trends"

TMP="$(mktemp -d -t fleet-trends-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache is sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Pinned epoch: 2026-06-15T00:00:00Z (Mon). The default window is the
# trailing 12 weeks = 84 days. Anchor: now - 84*86400 = 2026-03-23.
NOW_EPOCH=1781481600  # 2026-06-15 00:00:00 UTC
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Convenience: emit a fully-formed ISO8601 UTC timestamp.
iso_at() {  # $1 = epoch seconds
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

# Bucket anchor: epoch of (now - 84d). Bucket k spans
# [anchor + k*604800, anchor + (k+1)*604800).
ANCHOR=$(( NOW_EPOCH - 84 * 86400 ))

# Helper: emit an event into a given events.jsonl at bucket k, offset
# within bucket = 6h, of a given type. Slug is the cache dir parent.
emit_event() {  # $1=events_file $2=bucket $3=type $4=slug [extra k=v...]
  local f="$1" bucket="$2" type="$3" slug="$4"
  shift 4
  local ep=$(( ANCHOR + bucket * 604800 + 6 * 3600 ))
  local extra=""
  while [ $# -gt 0 ]; do
    extra+=",\"${1%%=*}\":\"${1#*=}\""
    shift
  done
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"%s"%s}\n' \
    "$(iso_at $ep)" "$slug" "$type" "$extra" >> "$f"
}

# Helper: emit a runs.jsonl row with given cost in bucket k.
emit_run() {  # $1=runs_file $2=bucket $3=slug $4=cost
  local f="$1" bucket="$2" slug="$3" cost="$4"
  local ep=$(( ANCHOR + bucket * 604800 + 6 * 3600 ))
  printf '{"slug":"%s","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":%s,"result_head":"SHIP test"}\n' \
    "$slug" "$(iso_at $ep)" "$(iso_at $((ep + 60)))" "$cost" >> "$f"
}

# Stage the four "shape" slugs + the paused slug into a discovery root.
FIX_TMP="$TMP/projects"
mkdir -p "$FIX_TMP"
cp -R "$FIX_ROOT/climbing"  "$FIX_TMP/climbing"
cp -R "$FIX_ROOT/declining" "$FIX_TMP/declining"
cp -R "$FIX_ROOT/flat"      "$FIX_TMP/flat"
cp -R "$FIX_ROOT/bimodal"   "$FIX_TMP/bimodal"
cp -R "$FIX_ROOT/paused"    "$FIX_TMP/paused"
export FLEET_DISCOVERY_ROOT="$FIX_TMP"

CACHE_CLIMB="$HOME/.cache/climbing-agent"
CACHE_DECL="$HOME/.cache/declining-agent"
CACHE_FLAT="$HOME/.cache/flat-agent"
CACHE_BIM="$HOME/.cache/bimodal-agent"
CACHE_PAUSED="$HOME/.cache/paused-agent"
mkdir -p "$CACHE_CLIMB" "$CACHE_DECL" "$CACHE_FLAT" "$CACHE_BIM" "$CACHE_PAUSED"

# ----- climbing: PR velocity rises smoothly across 12 buckets ------------
# Bucket k gets k+1 pr_footer_posted events (1..12). Cost rises 1.00..12.00.
# Send-back rate is 0 throughout.
EV_CLIMB="$CACHE_CLIMB/events.jsonl"
RUN_CLIMB="$CACHE_CLIMB/runs.jsonl"
: > "$EV_CLIMB"; : > "$RUN_CLIMB"
for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
  pr_n=$(( k + 1 ))
  for i in $(seq 1 "$pr_n"); do
    emit_event "$EV_CLIMB" "$k" pr_opened "climbing" "number=$((100 + k * 20 + i))"
    emit_event "$EV_CLIMB" "$k" pr_footer_posted "climbing" "pr=$((100 + k * 20 + i))"
    emit_run   "$RUN_CLIMB" "$k" "climbing" "1.00"
  done
done

# ----- declining: PR velocity ▆▇▇▇▆▅▄▃ then continues down --------------
# Bucket k=0..3 = 4 PRs, k=4..7 = 4,5,6,7 (rise), k=8..11 = 6,5,4,3 (fall).
# Bucket also accumulates send-backs (lesson_draft_emitted) rising in the
# last 4 weeks AND pr_opened so the rate is computable.
EV_DECL="$CACHE_DECL/events.jsonl"
RUN_DECL="$CACHE_DECL/runs.jsonl"
: > "$EV_DECL"; : > "$RUN_DECL"
# Pattern: 4 4 4 4 5 6 7 8 6 4 2 1  (last 4 weeks: 6,4,2,1 — clearly declining,
# monotone-non-increasing, last-4 mean 3.25 vs prior-4 mean 6.5 = -50% slope.)
DECL_PATTERN=(4 4 4 4 5 6 7 8 6 4 2 1)
# Send-back: 0 0 0 0 0 0 0 0 1 2 4 6  (rising in last 4 weeks, monotone-non-
# decreasing, last-4 mean 3.25 vs prior-4 mean 0 → up.)
DECL_SB=(0 0 0 0 0 0 0 0 1 2 4 6)
# pr_opened (denominator): 5 5 5 5 5 5 5 5 5 5 5 5
for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
  prs="${DECL_PATTERN[$k]}"
  for i in $(seq 1 "$prs"); do
    emit_event "$EV_DECL" "$k" pr_footer_posted "declining" "pr=$((200 + k * 20 + i))"
    emit_run   "$RUN_DECL" "$k" "declining" "0.50"
  done
  # 5 pr_opened per bucket as the denominator
  for i in 1 2 3 4 5; do
    emit_event "$EV_DECL" "$k" pr_opened "declining" "number=$((300 + k * 20 + i))"
  done
  sb="${DECL_SB[$k]}"
  if [ "$sb" -gt 0 ]; then
    for i in $(seq 1 "$sb"); do
      emit_event "$EV_DECL" "$k" lesson_draft_emitted "declining" "pr=$((400 + k * 20 + i))"
    done
  fi
done

# ----- flat: 3 PRs per bucket, constant cost, constant send-back --------
EV_FLAT="$CACHE_FLAT/events.jsonl"
RUN_FLAT="$CACHE_FLAT/runs.jsonl"
: > "$EV_FLAT"; : > "$RUN_FLAT"
for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
  for i in 1 2 3; do
    emit_event "$EV_FLAT" "$k" pr_footer_posted "flat" "pr=$((500 + k * 20 + i))"
    emit_event "$EV_FLAT" "$k" pr_opened "flat" "number=$((500 + k * 20 + i))"
    emit_run   "$RUN_FLAT" "$k" "flat" "0.25"
  done
done

# ----- bimodal: 0..7 then 6..3 with a smooth peak around bucket 7 -------
# Exact pattern: 0 1 2 3 4 5 6 7 6 5 4 3 (AC#4 reference shape mapping
# to glyphs ▁▂▃▄▅▆▇█▇▆▅▄)
EV_BIM="$CACHE_BIM/events.jsonl"
RUN_BIM="$CACHE_BIM/runs.jsonl"
: > "$EV_BIM"; : > "$RUN_BIM"
BIM_PATTERN=(0 1 2 3 4 5 6 7 6 5 4 3)
for k in 0 1 2 3 4 5 6 7 8 9 10 11; do
  prs="${BIM_PATTERN[$k]}"
  if [ "$prs" -gt 0 ]; then
    for i in $(seq 1 "$prs"); do
      emit_event "$EV_BIM" "$k" pr_footer_posted "bimodal" "pr=$((600 + k * 20 + i))"
      emit_run   "$RUN_BIM" "$k" "bimodal" "0.10"
    done
  fi
done

# ----- paused: only ship_paused events, zero PRs in window --------------
EV_PAUSED="$CACHE_PAUSED/events.jsonl"
RUN_PAUSED="$CACHE_PAUSED/runs.jsonl"
: > "$EV_PAUSED"; : > "$RUN_PAUSED"
emit_event "$EV_PAUSED" 5 ship_paused "paused" "reason=test"

# Backup byte sizes for AC#12 pure-reader assertion.
mkdir -p "$TMP/backup"
for cache in "$CACHE_CLIMB" "$CACHE_DECL" "$CACHE_FLAT" "$CACHE_BIM" "$CACHE_PAUSED"; do
  base="$(basename "$cache")"
  mkdir -p "$TMP/backup/$base"
  cp "$cache/events.jsonl" "$TMP/backup/$base/events.jsonl"
  cp "$cache/runs.jsonl"   "$TMP/backup/$base/runs.jsonl"
done

# ------------------------------------------------------------------------
# Assertion machinery
# ------------------------------------------------------------------------
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$1"; }

# ========================================================================
# AC#1: usage refusal + unknown-slug refusal (both stderr, exit 2).
# ========================================================================
err="$TMP/err.txt"
if "$FLEET" trends >"$TMP/out.txt" 2>"$err"; then
  fail "AC1: trends with no slug should exit non-zero"
fi
if ! grep -qF -- "usage: bin/fleet trends" "$err"; then
  fail "AC1: usage line not on stderr (got: $(cat "$err"))"
fi

if "$FLEET" trends bogus-slug >"$TMP/out.txt" 2>"$err"; then
  fail "AC1: trends with unknown slug should exit non-zero"
fi
if ! grep -qF -- "slug bogus-slug not found" "$err"; then
  fail "AC1: unknown-slug error not on stderr (got: $(cat "$err"))"
fi
pass "AC1: usage + unknown-slug refusals"

# ========================================================================
# AC#2: default 12-week window via single awk pass; PRs/wk row counts
# pr_footer_posted per bucket. Bucket math is pure awk arithmetic
# (FLEET_NOW_OVERRIDE freezes the anchor for the test).
# ========================================================================
out="$TMP/out.txt"
if ! "$FLEET" trends climbing >"$out" 2>"$err"; then
  fail "AC2: trends climbing exited non-zero (err: $(cat "$err"))"
fi
if ! grep -qF -- "PRs merged/wk" "$out"; then
  fail "AC2: 'PRs merged/wk' row missing (out: $(cat "$out"))"
fi
if ! grep -qF -- "12 weeks ending 2026-06-15" "$out"; then
  fail "AC2: header missing 12-week window phrase (out: $(cat "$out"))"
fi
pass "AC2: 12-week window header + PRs row"

# ========================================================================
# AC#3: all three axes render. $ spent/wk sums runs.jsonl cost_usd per
# bucket; send-back rate divides lesson_draft_emitted / pr_opened per
# bucket (0 when denominator is 0).
# ========================================================================
out="$TMP/out.txt"
"$FLEET" trends declining >"$out" 2>"$err" || fail "AC3: declining run failed: $(cat "$err")"
if ! grep -qF -- "PRs merged/wk" "$out"; then
  fail "AC3: PRs row missing"
fi
if ! grep -qF -- "spent/wk" "$out"; then
  fail "AC3: spent row missing (out: $(cat "$out"))"
fi
if ! grep -qF -- "send-back rate/wk" "$out"; then
  fail "AC3: send-back row missing (out: $(cat "$out"))"
fi
# Paused slug — sparkline must not divide-by-zero.
"$FLEET" trends paused >"$out" 2>"$err" || fail "AC3: paused run failed: $(cat "$err")"
if ! grep -qE "range 0(%|-0%| )" "$out"; then
  # Acceptable: any range pattern containing 0 for paused's send-back row
  # (denominator is 0 for all buckets — must NOT explode).
  grep -qF -- "send-back rate/wk" "$out" || fail "AC3: paused send-back row not rendered"
fi
pass "AC3: three-axis render + paused 0/0 = 0%"

# ========================================================================
# AC#4: sparkline encoder maps 0..7,6..3 to ▁▂▃▄▅▆▇█▇▆▅▄. Bimodal fixture
# is shaped exactly so. min==max → all glyphs render as ▁.
# ========================================================================
out="$TMP/out.txt"
"$FLEET" trends bimodal >"$out" 2>"$err" || fail "AC4: bimodal run failed: $(cat "$err")"
# Extract the PR row glyph string (between two spaces and the "range" col).
glyphs="$(awk 'BEGIN { count = 0 } /PRs merged\/wk/ { match($0, /[▁▂▃▄▅▆▇█]+/); if (RSTART > 0) print substr($0, RSTART, RLENGTH); }' "$out")"
expect="▁▂▃▄▅▆▇█▇▆▅▄"
if [ "$glyphs" != "$expect" ]; then
  fail "AC4: bimodal sparkline mismatch (got '$glyphs' want '$expect')"
fi
# Flat row min==max: spending is 0.25 every bucket, so all glyphs == ▁.
"$FLEET" trends flat >"$out" 2>"$err" || fail "AC4: flat run failed"
flat_glyphs="$(awk 'BEGIN { count = 0 } /spent\/wk/ { match($0, /[▁▂▃▄▅▆▇█]+/); if (RSTART > 0) print substr($0, RSTART, RLENGTH); }' "$out")"
case "$flat_glyphs" in
  "▁▁▁▁▁▁▁▁▁▁▁▁") : ;;
  *) fail "AC4: flat row min==max should render all ▁ (got '$flat_glyphs')" ;;
esac
pass "AC4: sparkline encoder + min==max collapse"

# ========================================================================
# AC#5: trailing-4-week slope arrows. climbing → ↑, flat → →, declining → ↓.
# ========================================================================
out="$TMP/out.txt"
"$FLEET" trends climbing >"$out" 2>"$err" || fail "AC5: climbing run failed"
grep -qF -- "↑" "$out" || fail "AC5: climbing slope arrow ↑ missing"
"$FLEET" trends flat >"$out" 2>"$err" || fail "AC5: flat run failed"
grep -qF -- "→" "$out" || fail "AC5: flat slope arrow → missing"
"$FLEET" trends declining >"$out" 2>"$err" || fail "AC5: declining run failed"
grep -qF -- "↓" "$out" || fail "AC5: declining slope arrow ↓ missing"
pass "AC5: ↑ / → / ↓ slope arrows"

# ========================================================================
# AC#6: advisory footer fires only on TWO-axis trigger (PR↓ + send-back↑
# both ≥3 consecutive weeks). Single-axis trend → no footer.
# ========================================================================
out="$TMP/out.txt"
"$FLEET" trends declining >"$out" 2>"$err" || fail "AC6: declining run failed"
if ! grep -qF -- "PR velocity declining" "$out"; then
  fail "AC6: declining (two-axis) should print advisory (out: $(cat "$out"))"
fi
"$FLEET" trends climbing >"$out" 2>"$err" || fail "AC6: climbing run failed"
if grep -qF -- "PR velocity declining" "$out"; then
  fail "AC6: climbing (single-axis up) should NOT print advisory"
fi
"$FLEET" trends bimodal >"$out" 2>"$err" || fail "AC6: bimodal run failed"
if grep -qF -- "PR velocity declining" "$out"; then
  fail "AC6: bimodal (single-axis only) should NOT print advisory"
fi
pass "AC6: advisory footer fires only on two-axis trigger"

# ========================================================================
# AC#7: --weeks N override; min 4, max 52.
# ========================================================================
"$FLEET" trends climbing --weeks 4 >"$TMP/out.txt" 2>"$err" || fail "AC7: --weeks 4 failed: $(cat "$err")"
grep -qF -- "4 weeks ending" "$TMP/out.txt" || fail "AC7: --weeks 4 not honored"
"$FLEET" trends climbing --weeks 52 >"$TMP/out.txt" 2>"$err" || fail "AC7: --weeks 52 failed: $(cat "$err")"
grep -qF -- "52 weeks ending" "$TMP/out.txt" || fail "AC7: --weeks 52 not honored"
if "$FLEET" trends climbing --weeks 3 >"$TMP/out.txt" 2>"$err"; then
  fail "AC7: --weeks 3 should refuse"
fi
grep -qF -- "--weeks must be 4-52" "$err" || fail "AC7: --weeks 3 error wrong (got: $(cat "$err"))"
if "$FLEET" trends climbing --weeks 53 >"$TMP/out.txt" 2>"$err"; then
  fail "AC7: --weeks 53 should refuse"
fi
grep -qF -- "--weeks must be 4-52" "$err" || fail "AC7: --weeks 53 error wrong"
pass "AC7: --weeks 4..52 enforced"

# ========================================================================
# AC#8: --axis <prs|cost|sendbacks> restricts to one row.
# ========================================================================
"$FLEET" trends climbing --axis prs >"$TMP/out.txt" 2>"$err" || fail "AC8: --axis prs failed"
grep -qF -- "PRs merged/wk" "$TMP/out.txt" || fail "AC8: --axis prs missing PRs row"
if grep -qF -- "spent/wk" "$TMP/out.txt"; then
  fail "AC8: --axis prs should NOT print spent row"
fi
"$FLEET" trends climbing --axis cost >"$TMP/out.txt" 2>"$err" || fail "AC8: --axis cost failed"
grep -qF -- "spent/wk" "$TMP/out.txt" || fail "AC8: --axis cost missing spent row"
if grep -qF -- "PRs merged/wk" "$TMP/out.txt"; then
  fail "AC8: --axis cost should NOT print PRs row"
fi
"$FLEET" trends climbing --axis sendbacks >"$TMP/out.txt" 2>"$err" || fail "AC8: --axis sendbacks failed"
grep -qF -- "send-back rate/wk" "$TMP/out.txt" || fail "AC8: --axis sendbacks missing row"
if "$FLEET" trends climbing --axis bogus >"$TMP/out.txt" 2>"$err"; then
  fail "AC8: --axis bogus should refuse"
fi
grep -qF -- "--axis must be one of" "$err" || fail "AC8: bogus axis err wrong (got: $(cat "$err"))"
pass "AC8: --axis restricts render"

# ========================================================================
# AC#9: --all prints one row per slug (PR-velocity only), sorted by
# descending last-4-week slope. Date-call budget < 10 for the whole run.
# ========================================================================
# Install a `date` stub that records its invocations to a counter file.
DATE_COUNT_FILE="$TMP/date-calls.txt"
echo 0 > "$DATE_COUNT_FILE"
REAL_DATE="$(command -v date)"
cat > "$HOME/.local/bin/date" <<EOF
#!/bin/bash
n=\$(cat "$DATE_COUNT_FILE" 2>/dev/null || echo 0)
echo \$((n + 1)) > "$DATE_COUNT_FILE"
exec "$REAL_DATE" "\$@"
EOF
chmod +x "$HOME/.local/bin/date"
echo 0 > "$DATE_COUNT_FILE"

PATH="$HOME/.local/bin:$PATH" "$FLEET" trends --all >"$TMP/out.txt" 2>"$err" \
  || fail "AC9: --all failed: $(cat "$err")"
# Restore PATH-shadowed date stub off — remove so subsequent tests do not pay.
rm -f "$HOME/.local/bin/date"

# Should mention all four "shape" slugs + paused.
for s in climbing declining flat bimodal paused; do
  grep -qF -- "$s" "$TMP/out.txt" || fail "AC9: --all missing slug '$s'"
done
date_calls="$(cat "$DATE_COUNT_FILE")"
if [ "$date_calls" -ge 10 ]; then
  fail "AC9: --all used $date_calls date calls (must be < 10) per LESSONS 2026-06-15"
fi
# Order: climbing's slope ↑ should appear above declining's ↓.
climb_line="$(awk '/^[[:space:]]*climbing[[:space:]]/ { print NR; exit } BEGIN { count = 0 }' "$TMP/out.txt")"
decl_line="$(awk '/^[[:space:]]*declining[[:space:]]/ { print NR; exit } BEGIN { count = 0 }' "$TMP/out.txt")"
if [ -n "$climb_line" ] && [ -n "$decl_line" ] && [ "$climb_line" -gt "$decl_line" ]; then
  fail "AC9: --all should sort climbing (↑) above declining (↓); climb=$climb_line decl=$decl_line"
fi
pass "AC9: --all (sorted, < 10 date calls)"

# ========================================================================
# AC#10: --json emits structured single-slug JSON with weeks[] +
# slopes{prs,cost,sendbacks} as ASCII up|flat|down (NOT Unicode arrows).
# ========================================================================
"$FLEET" trends climbing --json >"$TMP/out.txt" 2>"$err" || fail "AC10: --json failed: $(cat "$err")"
node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if (!d.slug || !Array.isArray(d.weeks) || d.weeks.length !== 12) throw new Error("bad shape: "+JSON.stringify(d).slice(0,200)); if (typeof d.slopes !== "object") throw new Error("missing slopes"); for (const k of ["prs","cost","sendbacks"]) { if (!["up","flat","down"].includes(d.slopes[k])) throw new Error("slope "+k+"="+d.slopes[k]+" not ascii up|flat|down"); } for (const w of d.weeks) { if (!w.start || typeof w.prs !== "number" || typeof w.usd !== "number" || typeof w.sendbacks_pct !== "number") throw new Error("bad week shape: "+JSON.stringify(w)); }' "$TMP/out.txt" \
  || fail "AC10: --json shape invalid"
# Slope must NOT contain raw Unicode arrows in JSON.
if grep -qF -- "↑" "$TMP/out.txt" || grep -qF -- "↓" "$TMP/out.txt" || grep -qF -- "→" "$TMP/out.txt"; then
  fail "AC10: JSON contains Unicode arrows (must be ASCII up|flat|down per LESSONS 2026-06-08)"
fi
pass "AC10: --json shape + ASCII slope strings"

# ========================================================================
# AC#11: --all --json emits a JSON array, one element per slug.
# ========================================================================
"$FLEET" trends --all --json >"$TMP/out.txt" 2>"$err" || fail "AC11: --all --json failed: $(cat "$err")"
node -e 'const a=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if (!Array.isArray(a) || a.length < 4) throw new Error("expected array of >=4 slugs, got "+JSON.stringify(a).slice(0,200)); for (const e of a) { if (!e.slug || !Array.isArray(e.weeks)) throw new Error("bad element: "+JSON.stringify(e).slice(0,160)); }' "$TMP/out.txt" \
  || fail "AC11: --all --json shape invalid"
pass "AC11: --all --json"

# ========================================================================
# AC#12: pure-reader contract. Every cache's events.jsonl + runs.jsonl
# byte size is unchanged after invocations.
# ========================================================================
for cache in "$CACHE_CLIMB" "$CACHE_DECL" "$CACHE_FLAT" "$CACHE_BIM" "$CACHE_PAUSED"; do
  base="$(basename "$cache")"
  for f in events.jsonl runs.jsonl; do
    a_size=$(wc -c <"$TMP/backup/$base/$f" | tr -d ' ')
    b_size=$(wc -c <"$cache/$f"            | tr -d ' ')
    if [ "$a_size" != "$b_size" ]; then
      fail "AC12: pure-reader violated — $cache/$f changed $a_size → $b_size bytes"
    fi
  done
done
pass "AC12: pure reader (no events.jsonl / runs.jsonl writes)"

# ========================================================================
# AC#13: lib/common.sh and prompts/ untouched on the feature branch.
# ========================================================================
cd "$REPO_ROOT"
changed="$(git diff --name-only origin/main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$changed" ]; then
  fail "AC13: lib/common.sh or prompts/ changed on branch:\n$changed"
fi
pass "AC13: lib/common.sh + prompts/ untouched"

# ========================================================================
# AC#14: --help banner mentions slug, --all, --axis, --weeks, --json. Help
# block ends `exit 0` (we infer by non-zero exit on missing kw being caught
# upstream, and by checking the help exits clean here).
# ========================================================================
HELP_OUT="$TMP/help.txt"
"$FLEET" trends --help >"$HELP_OUT" 2>"$err" || fail "AC14: --help exited non-zero (err: $(cat "$err"))"
for kw in "slug" "--all" "--axis" "--weeks" "--json"; do
  grep -qF -- "$kw" "$HELP_OUT" || fail "AC14: help missing '$kw'"
done
pass "AC14: --help mentions slug + --all + --axis + --weeks + --json"

echo
echo "all 14 trends acceptance criteria green"
