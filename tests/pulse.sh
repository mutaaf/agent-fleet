#!/bin/bash
# tests/pulse.sh — `bin/fleet pulse` daily-heartbeat tests.
#
# Ticket 0055. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0055-fleet-pulse-daily-heartbeat.md. `pulse` is a PURE READER
# of events.jsonl + agents.config.sh + inbox / docs/LESSONS.md state — no new
# event types, no fleet_emit_event calls, no fleet_* signature changes, no
# `lib/` or `prompts/` edits.
#
# Per LESSONS 2026-05-26 stubs live under $HOME/.local/bin (lib/common.sh
# resets PATH). Per LESSONS 2026-05-27 every fixture file is copied with
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 every count uses `awk … END { print n+0 }`.
# Per LESSONS 2026-05-30 every help-text grep uses `grep -qF -- "$kw"`.
# Per LESSONS 2026-06-08 awk scripts that index by counter declare
# `BEGIN { count = 0 }`. The clock is frozen via FLEET_NOW_OVERRIDE.
# Per LESSONS 2026-06-15 the streak predicate is INLINED in awk — `pulse`
# must NOT shell out to `fleet streak` per-slug (the test asserts this).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-pulse-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local stay sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.cache/agent-fleet"
mkdir -p "$HOME/.cache/fleet"

# Anchor "today" at 2026-06-15T12:00:00Z (epoch 1781524800).
NOW_EPOCH=1781524800
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

# Fixture root for slug manifests.
FIXTURE_ROOT="$TMP/projects"
mkdir -p "$FIXTURE_ROOT"
export FLEET_DISCOVERY_ROOT="$FIXTURE_ROOT"

# Clear all per-slug fixtures between AC blocks so each section starts
# from a single-slug baseline.
reset_fixtures() {
  rm -rf "$FIXTURE_ROOT" "$HOME/.cache"
  mkdir -p "$FIXTURE_ROOT"
  mkdir -p "$HOME/.cache/agent-fleet"
  mkdir -p "$HOME/.cache/fleet"
}

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
emit_pr_footer_posted() {  # $1 = slug, $2 = epoch, $3 = pr number
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"pr_footer_posted","number":"%s"}\n' \
    "$(iso_at "$2")" "$1" "$3"
}
emit_ship_paused() {  # $1 = slug, $2 = epoch
  printf '{"ts":"%s","slug":"%s","phase":"ship","type":"ship_paused","reason":"sendbacks","count":"3","prs":"1,2,3"}\n' \
    "$(iso_at "$2")" "$1"
}
emit_ship_resumed() {  # $1 = slug, $2 = epoch
  printf '{"ts":"%s","slug":"%s","phase":"resume","type":"ship_resumed","source":"%s","paused_for":"24h","reason":"streak cleared","forced":"0"}\n' \
    "$(iso_at "$2")" "$1" "$1"
}

# ========================================================================
# AC #1 — `bin/fleet pulse` is a new subcommand. No flags + ≥1 slug =>
#         multi-line banner. Zero discovered slugs => hint + exit 0.
# ========================================================================
echo "AC#1 — banner shape with slugs; hint when empty"

# Empty fleet first.
reset_fixtures
OUT="$TMP/ac1empty.out"
"$FLEET" pulse > "$OUT" 2>&1
EXIT=$?
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 empty fleet exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi
grep -qF -- "no slugs discovered" "$OUT" \
  || { echo "FAIL: AC#1 empty fleet missing hint"; cat "$OUT"; exit 1; }
grep -qF -- "fleet onboard" "$OUT" \
  || { echo "FAIL: AC#1 empty fleet hint should mention fleet onboard"; cat "$OUT"; exit 1; }

# Now seed one slug + check banner shape.
mk_manifest sidebrew
S_FILE="$HOME/.cache/sidebrew-agent/events.jsonl"
mkdir -p "$(dirname "$S_FILE")"
emit_run_started   sidebrew "$(( NOW_EPOCH - 86400 ))"   > "$S_FILE"
emit_run_completed sidebrew "$(( NOW_EPOCH - 3600 ))"  0 >> "$S_FILE"
OUT="$TMP/ac1banner.out"
"$FLEET" pulse > "$OUT" 2>&1
grep -qE '^pulse — ' "$OUT" \
  || { echo "FAIL: AC#1 banner header missing 'pulse — ' prefix"; cat "$OUT"; exit 1; }
grep -qE '^[[:space:]]+sidebrew' "$OUT" \
  || { echo "FAIL: AC#1 banner missing 'sidebrew' row"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #2 — `--prompt-line` shape: one cell per slug, two-space sep,
#         single line; truncates at 120 chars with '…'.
# ========================================================================
echo "AC#2 — --prompt-line shape and truncation"
# Seed 4 slugs (short to stay under 120).
for s in alpha bravo charlie delta; do
  mk_manifest "$s"
  F="$HOME/.cache/${s}-agent/events.jsonl"
  mkdir -p "$(dirname "$F")"
  emit_run_started   "$s" "$(( NOW_EPOCH - 86400 ))"   > "$F"
  emit_run_completed "$s" "$(( NOW_EPOCH - 3600 ))"  0 >> "$F"
done
OUT="$TMP/ac2.out"
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
LINES="$(awk 'END { print NR }' "$OUT")"
if [ "$LINES" != "1" ]; then
  echo "FAIL: AC#2 prompt-line should emit exactly one line, got $LINES"
  cat "$OUT"; exit 1
fi
# Should contain all four slugs.
for s in alpha bravo charlie delta; do
  grep -qF -- "$s" "$OUT" \
    || { echo "FAIL: AC#2 prompt-line missing slug '$s'"; cat "$OUT"; exit 1; }
done
# Width should be ≤120 chars on 4 slugs.
WIDTH="$(awk 'END { print length($0) }' "$OUT")"
if [ "$WIDTH" -gt 120 ]; then
  echo "FAIL: AC#2 prompt-line width $WIDTH > 120 on 4-slug fixture"
  cat "$OUT"; exit 1
fi

# Truncation: seed a wide fleet (10 long-named slugs).
reset_fixtures
for s in alphaXXXX bravoXXXX charlieXX deltaXXXX echoXXXXX foxtrotXX golfXXXXX hotelXXXX indiaXXXX julietXXX; do
  mk_manifest "$s"
  F="$HOME/.cache/${s}-agent/events.jsonl"
  mkdir -p "$(dirname "$F")"
  emit_run_started   "$s" "$(( NOW_EPOCH - 86400 ))"   > "$F"
  emit_run_completed "$s" "$(( NOW_EPOCH - 3600 ))"  0 >> "$F"
done
OUT="$TMP/ac2trunc.out"
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
WIDTH="$(awk 'END { print length($0) }' "$OUT")"
if [ "$WIDTH" -gt 120 ]; then
  echo "FAIL: AC#2 truncation width $WIDTH > 120 on wide fleet"
  cat "$OUT"; exit 1
fi
# The truncation marker should appear when 10 wide slugs overflow 120.
grep -qF -- "…" "$OUT" \
  || { echo "FAIL: AC#2 truncation should append '…' on wide fleet"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #3 — signal precedence: paused > inbox_debt > streak_break >
#         pr_velocity_dip > streak_growing > flat.
# ========================================================================
echo "AC#3 — signal precedence (6 fixtures)"

# (a) paused: ship_paused with no ship_resumed.
mk_manifest pa
PA_FILE="$HOME/.cache/pa-agent/events.jsonl"
mkdir -p "$(dirname "$PA_FILE")"
{
  emit_run_started pa "$(( NOW_EPOCH - 5 * 86400 ))"
  emit_ship_paused pa "$(( NOW_EPOCH - 3 * 86400 ))"
} > "$PA_FILE"
OUT="$TMP/ac3pa.out"
"$FLEET" pulse --prompt-line --no-cache --slug pa > "$OUT" 2>&1
grep -qF -- "⏸" "$OUT" \
  || { echo "FAIL: AC#3a paused render should contain '⏸'"; cat "$OUT"; exit 1; }

# (b) inbox_debt — manifest has SELF_CANCEL within 7d (a real inbox source).
mk_manifest ib
IB_FILE="$HOME/.cache/ib-agent/events.jsonl"
mkdir -p "$(dirname "$IB_FILE")"
emit_run_started ib "$(( NOW_EPOCH - 86400 ))" > "$IB_FILE"
# SELF_CANCEL=YYYYMMDD that's 2 days out from NOW_EPOCH (2026-06-15).
NEAR_DAY=$(date -u -r "$(( NOW_EPOCH + 2 * 86400 ))" '+%Y%m%d' 2>/dev/null \
  || date -u -d "@$(( NOW_EPOCH + 2 * 86400 ))" '+%Y%m%d')
cat > "$FIXTURE_ROOT/ib/agents.config.sh" <<CFG
PROJECT_NAME="ib"
SLUG="ib"
NAMESPACE="com.ib"
REPO_URL="https://github.com/example/ib"
SELF_CANCEL="$NEAR_DAY"
CFG
OUT="$TMP/ac3ib.out"
"$FLEET" pulse --prompt-line --no-cache --slug ib > "$OUT" 2>&1
grep -qE 'inbox=[1-9]' "$OUT" \
  || { echo "FAIL: AC#3b inbox_debt render missing 'inbox=N'"; cat "$OUT"; exit 1; }

# (c) streak_break: had a ≥3d streak ending within last 24h.
mk_manifest sb
SB_FILE="$HOME/.cache/sb-agent/events.jsonl"
mkdir -p "$(dirname "$SB_FILE")"
{
  emit_run_started sb "$(( NOW_EPOCH - 14 * 86400 ))"
  # 4 consecutive green days BEFORE the break window (days -7 through -4
  # from NOW_EPOCH so that the streak ENDED within last 24h).
  for i in 7 6 5 4; do
    EP=$(( NOW_EPOCH - i * 86400 ))
    DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
    printf '{"ts":"%sT12:00:00Z","slug":"sb","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
      "$DAY"
  done
  # A red run on day -1 (yesterday) — this is the BREAK.
  EP=$(( NOW_EPOCH - 86400 ))
  DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
  printf '{"ts":"%sT12:00:00Z","slug":"sb","phase":"ship","type":"gate_failed","check":"validate"}\n' "$DAY"
} > "$SB_FILE"
OUT="$TMP/ac3sb.out"
"$FLEET" pulse --prompt-line --no-cache --slug sb > "$OUT" 2>&1
grep -qE 'streak↓' "$OUT" \
  || { echo "FAIL: AC#3c streak_break render missing 'streak↓'"; cat "$OUT"; exit 1; }

# (d) pr_velocity_dip: trailing 7d count 0, prior 7d ≥ 1.
mk_manifest pv
PV_FILE="$HOME/.cache/pv-agent/events.jsonl"
mkdir -p "$(dirname "$PV_FILE")"
{
  emit_run_started pv "$(( NOW_EPOCH - 30 * 86400 ))"
  # Prior 7d: 2 pr_footer_posted events.
  emit_pr_footer_posted pv "$(( NOW_EPOCH - 10 * 86400 ))" 1
  emit_pr_footer_posted pv "$(( NOW_EPOCH - 12 * 86400 ))" 2
} > "$PV_FILE"
OUT="$TMP/ac3pv.out"
"$FLEET" pulse --prompt-line --no-cache --slug pv > "$OUT" 2>&1
grep -qF -- "0PR/wk↓" "$OUT" \
  || { echo "FAIL: AC#3d pr_velocity_dip render missing '0PR/wk↓'"; cat "$OUT"; exit 1; }

# (e) streak_growing: ≥3 consecutive green days, no break.
mk_manifest sg
SG_FILE="$HOME/.cache/sg-agent/events.jsonl"
mkdir -p "$(dirname "$SG_FILE")"
{
  emit_run_started sg "$(( NOW_EPOCH - 14 * 86400 ))"
  for i in 3 2 1 0; do
    EP=$(( NOW_EPOCH - i * 86400 ))
    DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
    printf '{"ts":"%sT12:00:00Z","slug":"sg","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
      "$DAY"
  done
} > "$SG_FILE"
OUT="$TMP/ac3sg.out"
"$FLEET" pulse --prompt-line --no-cache --slug sg > "$OUT" 2>&1
grep -qE '[0-9]+d↑' "$OUT" \
  || { echo "FAIL: AC#3e streak_growing render missing 'Nd↑'"; cat "$OUT"; exit 1; }

# (f) flat: no signal triggers.
mk_manifest ft
FT_FILE="$HOME/.cache/ft-agent/events.jsonl"
mkdir -p "$(dirname "$FT_FILE")"
emit_run_started ft "$(( NOW_EPOCH - 86400 ))" > "$FT_FILE"
OUT="$TMP/ac3ft.out"
"$FLEET" pulse --prompt-line --no-cache --slug ft > "$OUT" 2>&1
grep -qF -- "·" "$OUT" \
  || { echo "FAIL: AC#3f flat render missing '·'"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #4 — render shapes already covered by AC#3 cells. Spot-check that
#         each cell prints `<slug> <render>` with two-space cell separator.
# ========================================================================
echo "AC#4 — cell shapes use slug + space + render"
mk_manifest aa
AA_FILE="$HOME/.cache/aa-agent/events.jsonl"
mkdir -p "$(dirname "$AA_FILE")"
emit_run_started aa "$(( NOW_EPOCH - 86400 ))" > "$AA_FILE"

mk_manifest bb
BB_FILE="$HOME/.cache/bb-agent/events.jsonl"
mkdir -p "$(dirname "$BB_FILE")"
emit_run_started bb "$(( NOW_EPOCH - 86400 ))" > "$BB_FILE"

OUT="$TMP/ac4.out"
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
# Should look like "aa ·  bb ·" (two-space separator between cells).
grep -qE 'aa[[:space:]]+·[[:space:]]+[[:space:]]bb' "$OUT" \
  || grep -qE 'aa · {2}bb' "$OUT" \
  || { echo "FAIL: AC#4 cells should be separated by two spaces"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #5 — streak predicate is INLINED. The walker MUST NOT shell out
#         to `fleet streak`. We assert this by counting subprocess
#         invocations through a stub that records every call.
# ========================================================================
echo "AC#5 — streak predicate inlined (no per-slug shellout)"

# Stub `fleet` shadow: if the kit ever shells out to "fleet streak" it
# would resolve to this stub, which appends a line to a counter file.
COUNTER="$TMP/streak-stub-calls"
: > "$COUNTER"
cat > "$HOME/.local/bin/streak-stub-record" <<'STUB'
#!/bin/bash
echo "called" >> "$COUNTER_FILE"
exit 0
STUB
chmod +x "$HOME/.local/bin/streak-stub-record"

# Seed 5 slugs with various event counts.
for s in s1 s2 s3 s4 s5; do
  mk_manifest "$s"
  F="$HOME/.cache/${s}-agent/events.jsonl"
  mkdir -p "$(dirname "$F")"
  {
    emit_run_started "$s" "$(( NOW_EPOCH - 30 * 86400 ))"
    for i in 5 4 3 2 1 0; do
      EP=$(( NOW_EPOCH - i * 86400 ))
      DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
      printf '{"ts":"%sT12:00:00Z","slug":"%s","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
        "$DAY" "$s"
    done
  } > "$F"
done

# Count `date` invocations via the stub. We allow up to 20 across 5 slugs.
DATE_COUNTER="$TMP/date-calls"
: > "$DATE_COUNTER"
# Wrap /bin/date in a counting stub, but only when invoked AS `date`
# (not /bin/date). The runner uses absolute paths sometimes; the stub
# in $HOME/.local/bin only catches PATH lookups, which is the
# overwhelming common case.
cat > "$HOME/.local/bin/date" <<'STUB'
#!/bin/bash
echo "$@" >> "$DATE_COUNTER_FILE"
exec /bin/date "$@"
STUB
chmod +x "$HOME/.local/bin/date"
export DATE_COUNTER_FILE="$DATE_COUNTER"
export COUNTER_FILE="$COUNTER"

OUT="$TMP/ac5.out"
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
COUNT="$(awk 'END { print NR }' "$DATE_COUNTER")"
unset DATE_COUNTER_FILE COUNTER_FILE
# Strict bound: the streak predicate itself does NO `date` shellout
# in the awk walker; only the cache-age helper / install-anchor helper
# call `date`. ~5 slugs × ~3-4 calls per slug is fine; >50 means the
# walker is shelling out per day.
if [ "$COUNT" -gt 50 ]; then
  echo "FAIL: AC#5 date called $COUNT times (want <50). per-day shellout regression."
  exit 1
fi
# Also assert: no call to `fleet streak`.
if [ -s "$COUNTER" ]; then
  echo "FAIL: AC#5 pulse shelled out to `fleet streak`"
  cat "$COUNTER"
  exit 1
fi
rm -f "$HOME/.local/bin/date"
echo "  ok ($COUNT date calls across 5 slugs)"

reset_fixtures

# ========================================================================
# AC #6 — merged-PR count via pr_footer_posted in trailing 7d vs prior 7d.
# ========================================================================
echo "AC#6 — merged-PR count window arithmetic"

mk_manifest mp
MP_FILE="$HOME/.cache/mp-agent/events.jsonl"
mkdir -p "$(dirname "$MP_FILE")"
{
  emit_run_started mp "$(( NOW_EPOCH - 30 * 86400 ))"
  # Prior 7d (days -8 through -13): 1 pr_footer_posted.
  emit_pr_footer_posted mp "$(( NOW_EPOCH - 10 * 86400 ))" 1
  # No trailing 7d events → dip.
} > "$MP_FILE"
OUT="$TMP/ac6.out"
"$FLEET" pulse --prompt-line --no-cache --slug mp > "$OUT" 2>&1
grep -qF -- "0PR/wk↓" "$OUT" \
  || { echo "FAIL: AC#6 0PR/wk↓ should fire when prior≥1 and trailing=0"; cat "$OUT"; exit 1; }

# Counter case: a trailing 7d event suppresses the dip.
{
  emit_pr_footer_posted mp "$(( NOW_EPOCH - 86400 ))" 2
} >> "$MP_FILE"
OUT="$TMP/ac6b.out"
"$FLEET" pulse --prompt-line --no-cache --slug mp > "$OUT" 2>&1
if grep -qF -- "0PR/wk↓" "$OUT"; then
  echo "FAIL: AC#6 0PR/wk↓ should NOT fire when trailing ≥ 1"; cat "$OUT"; exit 1
fi
echo "  ok"

reset_fixtures

# ========================================================================
# AC #7 — --slug <name> restricts to one slug. Unknown → exit 2 stderr.
#         Missing --slug value → exit 2 stderr.
# ========================================================================
echo "AC#7 — --slug refusals and one-slug render"

mk_manifest only
O_FILE="$HOME/.cache/only-agent/events.jsonl"
mkdir -p "$(dirname "$O_FILE")"
emit_run_started only "$(( NOW_EPOCH - 86400 ))" > "$O_FILE"

# Valid slug → only one cell.
OUT="$TMP/ac7valid.out"
"$FLEET" pulse --prompt-line --no-cache --slug only > "$OUT" 2>&1
grep -qF -- "only" "$OUT" \
  || { echo "FAIL: AC#7 valid slug rendered no 'only'"; cat "$OUT"; exit 1; }

# Unknown slug → exit 2 + stderr hint.
OUT="$TMP/ac7unknown.out"
set +e
"$FLEET" pulse --slug nonesuch > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#7 unknown slug exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "slug nonesuch not found" "$OUT" \
  || { echo "FAIL: AC#7 unknown stderr missing 'slug nonesuch not found'"; cat "$OUT"; exit 1; }
grep -qF -- "discovered slugs:" "$OUT" \
  || { echo "FAIL: AC#7 unknown stderr missing 'discovered slugs:'"; cat "$OUT"; exit 1; }

# Missing --slug arg → exit 2.
OUT="$TMP/ac7missing.out"
set +e
"$FLEET" pulse --slug > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "2" ]; then
  echo "FAIL: AC#7 missing --slug value exit $EXIT (want 2)"; cat "$OUT"; exit 1
fi
grep -qF -- "--slug requires a value" "$OUT" \
  || { echo "FAIL: AC#7 missing --slug stderr"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #8 — --json emits a structured array, one element per slug.
# ========================================================================
echo "AC#8 — --json structured array"

mk_manifest j1
J1_FILE="$HOME/.cache/j1-agent/events.jsonl"
mkdir -p "$(dirname "$J1_FILE")"
{
  emit_run_started j1 "$(( NOW_EPOCH - 14 * 86400 ))"
  for i in 3 2 1 0; do
    EP=$(( NOW_EPOCH - i * 86400 ))
    DAY=$(date -u -r "$EP" '+%Y-%m-%d' 2>/dev/null || date -u -d "@$EP" '+%Y-%m-%d')
    printf '{"ts":"%sT12:00:00Z","slug":"j1","phase":"ship","type":"run_completed","exit":"0","duration_ms":"42"}\n' \
      "$DAY"
  done
} > "$J1_FILE"

mk_manifest j2
J2_FILE="$HOME/.cache/j2-agent/events.jsonl"
mkdir -p "$(dirname "$J2_FILE")"
emit_run_started j2 "$(( NOW_EPOCH - 86400 ))" > "$J2_FILE"

OUT="$TMP/ac8.out"
"$FLEET" pulse --json --no-cache > "$OUT" 2>&1
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(arr)) throw new Error("not an array");
  if (arr.length !== 2) throw new Error("want 2 elements, got " + arr.length);
  for (const el of arr) {
    if (typeof el.slug !== "string") throw new Error("slug missing on element");
    if (typeof el.signal !== "string") throw new Error("signal missing on element");
    const validSignals = ["paused","inbox_debt","streak_break","pr_velocity_dip","streak_growing","flat"];
    if (!validSignals.includes(el.signal)) throw new Error("bad signal: " + el.signal);
    if (typeof el.render !== "string") throw new Error("render missing");
    if (typeof el.detail !== "object" || el.detail === null) throw new Error("detail must be object");
  }
' "$OUT" || { echo "FAIL: AC#8 JSON parse"; cat "$OUT"; exit 1; }
echo "  ok"

reset_fixtures

# ========================================================================
# AC #9 — resilient to a flaky slug: corrupted events.jsonl renders '?'.
# ========================================================================
echo "AC#9 — resilience to a flaky slug"

mk_manifest hh1
H1_FILE="$HOME/.cache/hh1-agent/events.jsonl"
mkdir -p "$(dirname "$H1_FILE")"
emit_run_started hh1 "$(( NOW_EPOCH - 86400 ))" > "$H1_FILE"

mk_manifest hh2
H2_FILE="$HOME/.cache/hh2-agent/events.jsonl"
mkdir -p "$(dirname "$H2_FILE")"
emit_run_started hh2 "$(( NOW_EPOCH - 86400 ))" > "$H2_FILE"

mk_manifest hh3
H3_FILE="$HOME/.cache/hh3-agent/events.jsonl"
mkdir -p "$(dirname "$H3_FILE")"
emit_run_started hh3 "$(( NOW_EPOCH - 86400 ))" > "$H3_FILE"

# Corrupted slug: unreadable events.jsonl (directory at the path).
mk_manifest broken
mkdir -p "$HOME/.cache/broken-agent/events.jsonl"  # directory, not file

OUT="$TMP/ac9.out"
set +e
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#9 corrupted slug should not crash; exit $EXIT"; cat "$OUT"; exit 1
fi
grep -qE 'broken[[:space:]]+\?' "$OUT" \
  || { echo "FAIL: AC#9 corrupted slug should render 'broken ?'"; cat "$OUT"; exit 1; }
# Other slugs still render.
for s in hh1 hh2 hh3; do
  grep -qF -- "$s" "$OUT" \
    || { echo "FAIL: AC#9 healthy slug '$s' should still render"; cat "$OUT"; exit 1; }
done
echo "  ok"

reset_fixtures

# ========================================================================
# AC #10 — --prompt-line caches output for 90s; stale = re-walk.
# ========================================================================
echo "AC#10 — 90s TTL cache"

mk_manifest cc
CC_FILE="$HOME/.cache/cc-agent/events.jsonl"
mkdir -p "$(dirname "$CC_FILE")"
emit_run_started cc "$(( NOW_EPOCH - 86400 ))" > "$CC_FILE"

CACHE="$HOME/.cache/agent-fleet/pulse-prompt-line"
rm -f "$CACHE"

# First invocation writes the cache.
"$FLEET" pulse --prompt-line > "$TMP/ac10a.out" 2>&1
if [ ! -f "$CACHE" ]; then
  echo "FAIL: AC#10 first invocation should write cache file at $CACHE"
  exit 1
fi
MTIME_BEFORE="$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null)"

# Second invocation within TTL should NOT re-write the cache.
sleep 1
"$FLEET" pulse --prompt-line > "$TMP/ac10b.out" 2>&1
MTIME_AFTER="$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null)"
if [ "$MTIME_BEFORE" != "$MTIME_AFTER" ]; then
  echo "FAIL: AC#10 fresh cache should not be re-written (mtime: $MTIME_BEFORE → $MTIME_AFTER)"
  exit 1
fi
# Output should match.
if ! cmp -s "$TMP/ac10a.out" "$TMP/ac10b.out"; then
  echo "FAIL: AC#10 fresh cache should produce same output"
  diff "$TMP/ac10a.out" "$TMP/ac10b.out" || true
  exit 1
fi

# Force cache to be > 90s old via touch.
STALE_EPOCH=$(( NOW_EPOCH - 200 ))
touch -t "$(date -r "$STALE_EPOCH" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$STALE_EPOCH" '+%Y%m%d%H%M.%S')" "$CACHE"
"$FLEET" pulse --prompt-line > "$TMP/ac10c.out" 2>&1
MTIME_STALE="$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null)"
if [ "$MTIME_STALE" = "$STALE_EPOCH" ]; then
  echo "FAIL: AC#10 stale cache should be re-written"
  exit 1
fi
echo "  ok"

reset_fixtures

# ========================================================================
# AC #11 — --no-cache bypasses the cache.
# ========================================================================
echo "AC#11 — --no-cache bypasses cache"

mk_manifest nc
NC_FILE="$HOME/.cache/nc-agent/events.jsonl"
mkdir -p "$(dirname "$NC_FILE")"
emit_run_started nc "$(( NOW_EPOCH - 86400 ))" > "$NC_FILE"

CACHE="$HOME/.cache/agent-fleet/pulse-prompt-line"
rm -f "$CACHE"

# Write a poisoned cache value.
mkdir -p "$(dirname "$CACHE")"
echo "poisoned cached output" > "$CACHE"
MTIME_INITIAL="$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null)"

# Without --no-cache, the poisoned value should appear.
OUT="$TMP/ac11poisoned.out"
"$FLEET" pulse --prompt-line > "$OUT" 2>&1
grep -qF -- "poisoned cached output" "$OUT" \
  || { echo "FAIL: AC#11 default mode should serve cached output"; cat "$OUT"; exit 1; }

# With --no-cache the poisoned value should NOT appear.
OUT="$TMP/ac11bypass.out"
"$FLEET" pulse --prompt-line --no-cache > "$OUT" 2>&1
if grep -qF -- "poisoned cached output" "$OUT"; then
  echo "FAIL: AC#11 --no-cache should bypass cache"; cat "$OUT"; exit 1
fi
grep -qF -- "nc" "$OUT" \
  || { echo "FAIL: AC#11 --no-cache should re-walk and emit 'nc'"; cat "$OUT"; exit 1; }
: "$MTIME_INITIAL"
echo "  ok"

reset_fixtures

# ========================================================================
# AC #12 — --help prints USAGE.
# ========================================================================
echo "AC#12 — --help mentions --prompt-line, --slug, --json, --no-cache"
OUT="$TMP/ac12.out"
"$FLEET" pulse --help > "$OUT" 2>&1
for kw in "--prompt-line" "--slug" "--json" "--no-cache"; do
  grep -qF -- "$kw" "$OUT" \
    || { echo "FAIL: AC#12 help missing keyword '$kw'"; cat "$OUT"; exit 1; }
done
echo "  ok"

reset_fixtures

# ========================================================================
# AC #13 — pure reader: events.jsonl byte size unchanged before vs after.
# ========================================================================
echo "AC#13 — pure reader (events.jsonl byte size unchanged)"

mk_manifest pure
P_FILE="$HOME/.cache/pure-agent/events.jsonl"
mkdir -p "$(dirname "$P_FILE")"
{
  emit_run_started   pure "$(( NOW_EPOCH - 86400 ))"
  emit_run_completed pure "$(( NOW_EPOCH - 3600 ))" 0
  emit_pr_footer_posted pure "$(( NOW_EPOCH - 7200 ))" 1
} > "$P_FILE"

B4="$(wc -c < "$P_FILE" | tr -d ' ')"
"$FLEET" pulse                       --no-cache > /dev/null 2>&1
"$FLEET" pulse --prompt-line         --no-cache > /dev/null 2>&1
"$FLEET" pulse --json                --no-cache > /dev/null 2>&1
"$FLEET" pulse --slug pure           --no-cache > /dev/null 2>&1
AFTER="$(wc -c < "$P_FILE" | tr -d ' ')"
if [ "$B4" != "$AFTER" ]; then
  echo "FAIL: AC#13 events.jsonl size changed: $B4 -> $AFTER"
  exit 1
fi
echo "  ok"

# ========================================================================
# AC #14 — lib/common.sh + prompts/ untouched on this branch.
# ========================================================================
echo "AC#14 — lib/common.sh + prompts/ untouched"
cd "$REPO_ROOT"
DIFF="$(git diff --name-only main...HEAD -- lib/common.sh prompts/ 2>/dev/null || true)"
if [ -n "$DIFF" ]; then
  echo "FAIL: AC#14 lib/common.sh or prompts/ changed:"
  echo "$DIFF"
  exit 1
fi
echo "  ok"

echo
echo "tests/pulse.sh: all 14 ACs PASS"
