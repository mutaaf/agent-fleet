#!/bin/bash
# tests/morning.sh — `bin/fleet morning` daily-briefing composition test.
#
# Ticket 0036. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0036-fleet-morning-one-command-briefing.md.
#
# Fixture (three synthetic projects) seeded under a tmpdir
# FLEET_DISCOVERY_ROOT, mirroring tests/weekly.sh + tests/inbox.sh. Time
# is pinned via FLEET_NOW_OVERRIDE (the morning-specific seam) and the
# existing FLEET_WEEKLY_FAKE_NOW / FLEET_INBOX_FAKE_NOW are wired to the
# same anchor so the composed output stays deterministic.
#
# Stubs in $HOME/.local/bin per LESSONS 2026-05-26 (lib/common.sh resets
# PATH).  bin/fleet doesn't source common.sh, but the four readers may
# call launchctl/gh.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
GOLDEN_TEXT="$REPO_ROOT/tests/fixtures/morning/morning.text.golden.txt"

TMP="$(mktemp -d -t fleet-morning-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/Library are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/.cache/fleet"

# Stable epoch anchor — 2026-06-07T12:00:00Z (a Sunday).
NOW_EPOCH=1780833600
export FLEET_NOW_OVERRIDE="2026-06-07 12:00"
export FLEET_WEEKLY_FAKE_NOW="$NOW_EPOCH"
export FLEET_INBOX_FAKE_NOW="$NOW_EPOCH"
export FLEET_ATLAS_FAKE_NOW="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_5D_AGO=$(( NOW_EPOCH - 5 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))
T_6H_AGO=$(( NOW_EPOCH - 6 * 3600 ))

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# ----- Fixture A: agent-fleet (healthy + 1 unpromoted DRAFT) -------------
mkdir -p "$FIXTURE/agent-fleet/docs"
cat > "$FIXTURE/agent-fleet/agents.config.sh" <<CFG
PROJECT_NAME="Agent Fleet"
SLUG="agent-fleet"
NAMESPACE="com.agent-fleet"
REPO_URL="https://github.com/mutaaf/agent-fleet"
SELF_CANCEL="20260830"
CFG

cat > "$FIXTURE/agent-fleet/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

Existing promoted lesson, no marker.

<!-- DRAFT: reviewer send-back, PR #200, 2026-06-05 -->
## 2026-06-05 — DRAFT placeholder

(promote me)
LESSONS

AF_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$AF_CACHE"
{
  for i in 1 2 3; do
    printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.47,"result_head":"SHIP 003%s-x — PR #%s green"}\n' \
      "$(iso_at $(( T_3D_AGO + i * 3600 )))" "$(iso_at $(( T_3D_AGO + i * 3600 + 60 )))" "$i" "$(( 200 + i ))"
  done
} > "$AF_CACHE/runs.jsonl"
{
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"200","headline":"draft one"}\n' \
    "$(iso_at "$T_1D_AGO")"
  # An infra_flake_rerun in window so atlas has something to surface.
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"42","pr":"201"}\n' \
    "$(iso_at "$T_2D_AGO")"
} > "$AF_CACHE/events.jsonl"

# ----- Fixture B: almanac (throttled — budget_block today) ---------------
mkdir -p "$FIXTURE/almanac/docs"
cat > "$FIXTURE/almanac/agents.config.sh" <<CFG
PROJECT_NAME="Almanac"
SLUG="almanac"
NAMESPACE="com.almanac"
REPO_URL="https://github.com/example/almanac"
SELF_CANCEL="20260901"
CFG
cat > "$FIXTURE/almanac/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

No drafts.
LESSONS
AL_CACHE="$HOME/.cache/almanac-agent"
mkdir -p "$AL_CACHE"
: > "$AL_CACHE/runs.jsonl"
{
  printf '{"ts":"%s","slug":"almanac","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_6H_AGO")"
} > "$AL_CACHE/events.jsonl"

# ----- Fixture C: courtiq (clean, no drafts, not paused) -----------------
mkdir -p "$FIXTURE/courtiq/docs"
cat > "$FIXTURE/courtiq/agents.config.sh" <<CFG
PROJECT_NAME="CourtIQ"
SLUG="courtiq"
NAMESPACE="com.courtiq"
REPO_URL="https://github.com/example/courtiq"
SELF_CANCEL="20260901"
CFG
cat > "$FIXTURE/courtiq/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap
LESSONS
CQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$CQ_CACHE"
{
  printf '{"slug":"courtiq","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.40,"result_head":"SHIP 0001-x — PR #1 green"}\n' \
    "$(iso_at "$T_5D_AGO")" "$(iso_at $(( T_5D_AGO + 60 )))"
} > "$CQ_CACHE/runs.jsonl"
: > "$CQ_CACHE/events.jsonl"

# ----- launchctl stub: nobody is paused (baseline fixture) ---------------
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.agent-fleet.agent-ship" => false
  "com.almanac.agent-ship" => false
  "com.courtiq.agent-ship" => false
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"

# ----- gh stub: no stuck PRs anywhere ------------------------------------
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  echo "[]"
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

export PATH="$HOME/.local/bin:$PATH"

# Atlas needs a heal-catalog. Point it at the repo's real one (read-only).
export FLEET_HEAL_CATALOG="$REPO_ROOT/lib/heal-catalog.sh"

# ========================================================================
# AC #1 — `bin/fleet morning` (no flags) prints, in order:
#   (1) one VERDICT line
#   (2) DIGEST (24h) heading + digest output
#   (3) INBOX heading + inbox output
#   (4) On Sundays: WEEKLY heading + weekly summary + atlas top-3
#   (5) NEXT footer hint
# Exits 0.
# ========================================================================
OUT="$TMP/morning.txt"
set +e
"$FLEET" morning > "$OUT" 2>&1
EXIT=$?
set -e

if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default morning should exit 0, got $EXIT"
  cat "$OUT"; exit 1
fi

# Verdict line is first line.
if ! head -1 "$OUT" | grep -qE '^MORNING — 2026-06-07 Sun · [0-9]+ owes you a click · [0-9]+ paused · fleet (OK|WARN|FAIL)$'; then
  echo "FAIL: AC#1 verdict line missing or malformed"
  head -3 "$OUT"; exit 1
fi

# Section headings in order.
expected_order=("DIGEST (24h)" "INBOX" "WEEKLY (Sunday-only — last 7d)" "NEXT:")
prev_line=0
for section in "${expected_order[@]}"; do
  line=$(grep -nF -- "$section" "$OUT" | head -1 | cut -d: -f1)
  if [ -z "$line" ]; then
    echo "FAIL: AC#1 section '$section' missing"; cat "$OUT"; exit 1
  fi
  if [ "$line" -le "$prev_line" ]; then
    echo "FAIL: AC#1 section '$section' out of order (line $line <= prev $prev_line)"
    cat "$OUT"; exit 1
  fi
  prev_line="$line"
done
echo "ok: AC#1 default morning briefing — verdict + 4 sections + NEXT footer"

# ========================================================================
# AC #2 — VERDICT line format under three fleet postures.
#   Baseline fixture above: 1 draft for agent-fleet + 1 budget tripped today
#   = 2 owes a click; 0 paused → fleet WARN.
# ========================================================================
VERDICT_LINE="$(head -1 "$OUT")"
# At least one inbox row → WARN (since paused=0).
if ! echo "$VERDICT_LINE" | grep -qE '· [0-9]+ owes you a click · 0 paused · fleet WARN$'; then
  echo "FAIL: AC#2 expected WARN band with 0 paused"
  echo "$VERDICT_LINE"; exit 1
fi
echo "ok: AC#2a verdict — WARN band"

# Build a CLEAN-fleet variant: delete all inboxables, expect OK.
CLEAN_DIR="$TMP/clean-projects"; mkdir -p "$CLEAN_DIR"
mkdir -p "$CLEAN_DIR/cleanslug/docs"
cat > "$CLEAN_DIR/cleanslug/agents.config.sh" <<CFG
PROJECT_NAME="Clean Slug"
SLUG="cleanslug"
NAMESPACE="com.cleanslug"
REPO_URL="https://github.com/example/cleanslug"
SELF_CANCEL="20270101"
CFG
cat > "$CLEAN_DIR/cleanslug/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap
LESSONS
mkdir -p "$HOME/.cache/cleanslug-agent"
: > "$HOME/.cache/cleanslug-agent/runs.jsonl"
: > "$HOME/.cache/cleanslug-agent/events.jsonl"
FLEET_DISCOVERY_ROOT="$CLEAN_DIR" "$FLEET" morning > "$TMP/morning.clean.txt" 2>&1
if ! head -1 "$TMP/morning.clean.txt" | grep -qE '· 0 owes you a click · 0 paused · fleet OK$'; then
  echo "FAIL: AC#2 expected OK band on clean fleet"
  head -1 "$TMP/morning.clean.txt"; exit 1
fi
echo "ok: AC#2b verdict — OK band"

# Build a PAUSED-fleet variant: simulate one paused project, expect FAIL.
PAUSED_DIR="$TMP/paused-projects"; mkdir -p "$PAUSED_DIR/pauseme/docs"
cat > "$PAUSED_DIR/pauseme/agents.config.sh" <<CFG
PROJECT_NAME="Pause Me"
SLUG="pauseme"
NAMESPACE="com.pauseme"
REPO_URL="https://github.com/example/pauseme"
SELF_CANCEL="20270101"
CFG
cat > "$PAUSED_DIR/pauseme/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap
LESSONS
mkdir -p "$HOME/.cache/pauseme-agent"
: > "$HOME/.cache/pauseme-agent/runs.jsonl"
: > "$HOME/.cache/pauseme-agent/events.jsonl"
# Drop a plist with mtime = 5d ago so paused_days reports "5d!".
PAUSEME_PLIST="$HOME/Library/LaunchAgents/com.pauseme.agent-ship.plist"
echo "<plist/>" > "$PAUSEME_PLIST"
T_PAUSE=$(( NOW_EPOCH - 5 * 86400 ))
LOCAL_STAMP="$(date -r "$T_PAUSE" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$T_PAUSE" +%Y%m%d%H%M.%S)"
touch -t "$LOCAL_STAMP" "$PAUSEME_PLIST"
# Override launchctl stub to mark pauseme as disabled.
cp "$HOME/.local/bin/launchctl" "$TMP/launchctl.orig"
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.pauseme.agent-ship" => true
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"
FLEET_DISCOVERY_ROOT="$PAUSED_DIR" "$FLEET" morning > "$TMP/morning.paused.txt" 2>&1
if ! head -1 "$TMP/morning.paused.txt" | grep -qE '· [0-9]+ paused · fleet FAIL$'; then
  echo "FAIL: AC#2 expected FAIL band on paused fleet"
  head -1 "$TMP/morning.paused.txt"; exit 1
fi
echo "ok: AC#2c verdict — FAIL band"
# Restore baseline launchctl stub.
cp "$TMP/launchctl.orig" "$HOME/.local/bin/launchctl"

# ========================================================================
# AC #3 — composition shells through to in-process functions. Trace via
#         `bash -x` and assert no `bin/fleet digest` subprocess.
# ========================================================================
TRACE="$TMP/trace.log"
set +e
bash -x "$FLEET" morning > /dev/null 2> "$TRACE"
set -e
# An exec of bin/fleet (subprocess re-invocation) would show up as
# `+ exec ... bin/fleet ...` or as a child shell line. Allow the script's
# OWN execution preamble (the shebang + outer bash). What we forbid:
# any `bin/fleet (digest|inbox|weekly|atlas)` exec inside the trace.
if grep -E '\+ (exec )?[^ ]*bin/fleet (digest|inbox|weekly|atlas)' "$TRACE" >/dev/null; then
  echo "FAIL: AC#3 morning spawned a bin/fleet subprocess instead of in-process call"
  grep -E '\+ (exec )?[^ ]*bin/fleet (digest|inbox|weekly|atlas)' "$TRACE" | head -5
  exit 1
fi
echo "ok: AC#3 composition is in-process (no bin/fleet subprocess)"

# ========================================================================
# AC #4 — --no-weekly suppresses the WEEKLY block on a Sunday;
#         --weekly forces it on a non-Sunday.
# ========================================================================
"$FLEET" morning --no-weekly > "$TMP/morning.no-weekly.txt"
if grep -qF -- "WEEKLY (Sunday-only" "$TMP/morning.no-weekly.txt"; then
  echo "FAIL: AC#4 --no-weekly should suppress the WEEKLY block"
  cat "$TMP/morning.no-weekly.txt"; exit 1
fi
echo "ok: AC#4a --no-weekly suppresses WEEKLY on Sunday"

# --weekly on a non-Sunday: pin to a Monday.
FLEET_NOW_OVERRIDE="2026-06-08 12:00" "$FLEET" morning --weekly > "$TMP/morning.weekly-forced.txt"
if ! grep -qF -- "WEEKLY (Sunday-only" "$TMP/morning.weekly-forced.txt"; then
  echo "FAIL: AC#4 --weekly should force WEEKLY block on non-Sunday"
  cat "$TMP/morning.weekly-forced.txt"; exit 1
fi
# Verdict line should show Mon.
if ! head -1 "$TMP/morning.weekly-forced.txt" | grep -qE '^MORNING — 2026-06-08 Mon · '; then
  echo "FAIL: AC#4 forced-weekly run should show Mon in verdict"
  head -1 "$TMP/morning.weekly-forced.txt"; exit 1
fi
echo "ok: AC#4b --weekly forces WEEKLY on non-Sunday"

# A non-Sunday default run should NOT print WEEKLY.
FLEET_NOW_OVERRIDE="2026-06-08 12:00" "$FLEET" morning > "$TMP/morning.monday.txt"
if grep -qF -- "WEEKLY (Sunday-only" "$TMP/morning.monday.txt"; then
  echo "FAIL: AC#4 non-Sunday default should suppress WEEKLY"
  cat "$TMP/morning.monday.txt"; exit 1
fi
echo "ok: AC#4c non-Sunday default suppresses WEEKLY"

# ========================================================================
# AC #5 — --json emits one composed JSON object.
# ========================================================================
"$FLEET" morning --json > "$TMP/morning.json"
node -e '
  const fs = require("fs");
  const raw = fs.readFileSync(process.argv[1], "utf8");
  let o;
  try { o = JSON.parse(raw); } catch (e) {
    console.error("FAIL: JSON did not parse: " + e.message);
    console.error("---");
    console.error(raw);
    process.exit(1);
  }
  for (const k of ["date","verdict","owes_click","paused","digest","inbox","weekly","atlas_top"]) {
    if (!(k in o)) { console.error("FAIL: --json missing key " + k); process.exit(1); }
  }
  if (typeof o.date !== "string") { console.error("FAIL: date not string"); process.exit(1); }
  if (!["OK","WARN","FAIL"].includes(o.verdict)) { console.error("FAIL: bad verdict " + o.verdict); process.exit(1); }
  if (typeof o.owes_click !== "number") { console.error("FAIL: owes_click not number"); process.exit(1); }
  if (typeof o.paused !== "number") { console.error("FAIL: paused not number"); process.exit(1); }
  if (!Array.isArray(o.digest)) { console.error("FAIL: digest not array"); process.exit(1); }
  if (typeof o.inbox !== "object") { console.error("FAIL: inbox not object"); process.exit(1); }
  // Sunday in this fixture: weekly + atlas_top present.
  if (o.weekly === null) { console.error("FAIL: Sunday should populate weekly"); process.exit(1); }
  console.log("ok: AC#5 --json shape on Sunday");
' "$TMP/morning.json"

# Non-Sunday: weekly/atlas_top must be JSON null.
FLEET_NOW_OVERRIDE="2026-06-08 12:00" "$FLEET" morning --json > "$TMP/morning.mon.json"
node -e '
  const fs = require("fs");
  const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (o.weekly !== null) { console.error("FAIL: non-Sunday weekly should be null"); process.exit(1); }
  if (o.atlas_top !== null) { console.error("FAIL: non-Sunday atlas_top should be null"); process.exit(1); }
  console.log("ok: AC#5 --json weekly/atlas_top null on non-Sunday");
' "$TMP/morning.mon.json"

# ========================================================================
# AC #6 — --slug narrows digest + inbox sections to one project.
# ========================================================================
"$FLEET" morning --slug agent-fleet > "$TMP/morning.slug.txt"
# digest should contain agent-fleet but not almanac/courtiq rows.
DIGEST_START=$(grep -nF -- "DIGEST (24h)" "$TMP/morning.slug.txt" | head -1 | cut -d: -f1)
INBOX_START=$(grep -nF -- "INBOX" "$TMP/morning.slug.txt" | head -1 | cut -d: -f1)
DIGEST_BLOCK="$(awk -v s="$DIGEST_START" -v e="$INBOX_START" 'NR>s && NR<e' "$TMP/morning.slug.txt")"
if ! echo "$DIGEST_BLOCK" | grep -qF 'agent-fleet'; then
  echo "FAIL: AC#6 --slug digest missing agent-fleet"
  echo "$DIGEST_BLOCK"; exit 1
fi
if echo "$DIGEST_BLOCK" | grep -qE '^almanac|^courtiq'; then
  echo "FAIL: AC#6 --slug digest leaked other slugs"
  echo "$DIGEST_BLOCK"; exit 1
fi
echo "ok: AC#6 --slug filter"

# ========================================================================
# AC #7 — NEXT footer priority ordering: paused > draft > self-cancel
#         > budget > stale PR > nothing.
# ========================================================================
# Baseline fixture has: 1 draft + 1 budget (no paused, no SC<=7d, no stale PR).
# Priority: draft wins → footer should mention lessons-promote.
NEXT_LINE="$(grep -F -- "NEXT:" "$OUT" | head -1)"
if ! echo "$NEXT_LINE" | grep -qF 'fleet lessons-promote'; then
  echo "FAIL: AC#7 draft-priority should yield lessons-promote hint"
  echo "$NEXT_LINE"; exit 1
fi
echo "ok: AC#7a NEXT — draft priority (lessons-promote)"

# Paused branch wins over draft. Use the pauseme fixture above + add a draft to it.
mkdir -p "$PAUSED_DIR/pauseme/docs"
cat > "$PAUSED_DIR/pauseme/docs/LESSONS.md" <<'LESSONS'
# LESSONS

## 2026-05-25 — bootstrap

<!-- DRAFT: PR #99 -->
## 2026-06-05 — DRAFT placeholder
(promote me)
LESSONS
# Re-enable the paused launchctl stub.
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.pauseme.agent-ship" => true
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"
FLEET_DISCOVERY_ROOT="$PAUSED_DIR" "$FLEET" morning > "$TMP/morning.paused.next.txt" 2>&1
NEXT_PAUSED="$(grep -F -- "NEXT:" "$TMP/morning.paused.next.txt" | head -1)"
if ! echo "$NEXT_PAUSED" | grep -qF 'fleet resume'; then
  echo "FAIL: AC#7 paused-priority should yield 'fleet resume <slug>' hint"
  echo "$NEXT_PAUSED"; exit 1
fi
echo "ok: AC#7b NEXT — paused priority (fleet resume)"

# Restore baseline launchctl stub.
cp "$TMP/launchctl.orig" "$HOME/.local/bin/launchctl"

# "Nothing else owes you a click" branch — clean fleet, no draft.
NEXT_CLEAN="$(grep -F -- "NEXT:" "$TMP/morning.clean.txt" | head -1)"
if ! echo "$NEXT_CLEAN" | grep -qF 'nothing else owes you a click. enjoy your day.'; then
  echo "FAIL: AC#7 clean fleet should yield 'nothing else owes you a click' hint"
  echo "$NEXT_CLEAN"; exit 1
fi
echo "ok: AC#7c NEXT — clean fleet"

# ========================================================================
# AC #8 — Empty fleet → stderr message, exit 0, no verdict line.
# ========================================================================
EMPTY_DIR="$TMP/empty-root"; mkdir -p "$EMPTY_DIR"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_DIR" "$FLEET" morning > "$TMP/morning.empty.out" 2> "$TMP/morning.empty.err"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: AC#8 empty fleet should exit 0, got $EMPTY_EXIT"
  cat "$TMP/morning.empty.err"; exit 1
fi
if ! grep -qF -- "no projects found under FLEET_DISCOVERY_ROOT" "$TMP/morning.empty.err"; then
  echo "FAIL: AC#8 empty fleet expected stderr message"
  cat "$TMP/morning.empty.err"; exit 1
fi
if grep -qE '^MORNING — ' "$TMP/morning.empty.out"; then
  echo "FAIL: AC#8 empty fleet should NOT print a verdict line"
  cat "$TMP/morning.empty.out"; exit 1
fi
echo "ok: AC#8 empty fleet"

# ========================================================================
# AC #9 — Help text mentions all four flags and exits 0.
# ========================================================================
HELP_OUT="$TMP/morning.help"
set +e
"$FLEET" morning --help > "$HELP_OUT" 2>&1
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL: AC#9 --help should exit 0, got $HELP_EXIT"
  cat "$HELP_OUT"; exit 1
fi
# Per LESSONS 2026-05-30 use grep -qF -- for flag patterns.
for kw in "--no-weekly" "--weekly" "--json" "--slug"; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#9 help missing keyword '$kw'"
    cat "$HELP_OUT"; exit 1
  fi
done
echo "ok: AC#9 help text mentions all flags"

# ========================================================================
# AC #10 — Dispatcher fall-through guard. Both the if-block and the
#          morning() function body end with explicit `exit N` on every
#          path. We also confirm the morning() body does NOT reference
#          any function defined LATER in the file.
# ========================================================================
# 10a: assert there is exactly one `if [ "$CMD" = "morning" ]` block and
#      it is exit-safe (the morning function ends with exit).
DISPATCHER_HITS="$(grep -nE '^if \[ "\$CMD" = "morning" \]; then$' "$REPO_ROOT/bin/fleet" | wc -l | tr -d ' ')"
if [ "$DISPATCHER_HITS" != "1" ]; then
  echo "FAIL: AC#10 expected exactly one morning dispatcher line, got $DISPATCHER_HITS"
  exit 1
fi
# 10b: confirm morning() function body ends with `exit 0`.
MORNING_BODY="$(awk '/^morning\(\) \{/,/^\}/' "$REPO_ROOT/bin/fleet")"
if [ -z "$MORNING_BODY" ]; then
  echo "FAIL: AC#10 morning() function not found in bin/fleet"
  exit 1
fi
# Allow trailing newlines/whitespace; check that an `exit 0` appears in the
# tail of the function (last 5 lines).
TAIL_OF_FN="$(echo "$MORNING_BODY" | tail -n 5)"
if ! echo "$TAIL_OF_FN" | grep -qE '^[[:space:]]*exit 0[[:space:]]*$'; then
  echo "FAIL: AC#10 morning() must end with exit 0"
  echo "$TAIL_OF_FN"; exit 1
fi
# 10c: confirm dispatcher block ends with `exit "$?"` or similar — pattern
#      `if [ "$CMD" = "morning" ]; then morning "$@"; fi`. Since morning()
#      itself exits, the fi is reachable only if the function returns; we
#      still assert the dispatcher block is present.
DISPATCH_LINE=$(grep -nE '^if \[ "\$CMD" = "morning" \]; then$' "$REPO_ROOT/bin/fleet" | head -1 | cut -d: -f1)
DISPATCH_BODY="$(awk -v s="$DISPATCH_LINE" 'NR>=s && NR<=s+2' "$REPO_ROOT/bin/fleet")"
if ! echo "$DISPATCH_BODY" | grep -qF 'morning "$@"'; then
  echo "FAIL: AC#10 dispatcher block must call morning \"\$@\""
  echo "$DISPATCH_BODY"; exit 1
fi
echo "ok: AC#10a dispatcher block exit-safe"

# 10d: morning() must NOT call any function defined LATER in the file.
# Find the line number of each delegated reader; assert each is < morning's
# line number.
MORNING_LINE=$(grep -nE '^morning\(\) \{$' "$REPO_ROOT/bin/fleet" | head -1 | cut -d: -f1)
if [ -z "$MORNING_LINE" ]; then
  echo "FAIL: AC#10 morning() function not found"
  exit 1
fi
for fn in digest inbox weekly atlas; do
  FN_LINE=$(grep -nE "^${fn}\(\) \{$" "$REPO_ROOT/bin/fleet" | head -1 | cut -d: -f1)
  if [ -z "$FN_LINE" ] || [ "$FN_LINE" -ge "$MORNING_LINE" ]; then
    echo "FAIL: AC#10 morning() must sit BELOW $fn() (forward-reference trap)"
    echo "  morning at $MORNING_LINE, $fn at ${FN_LINE:-<missing>}"
    exit 1
  fi
done
echo "ok: AC#10b morning() sits below all four reader functions"

# 10e: morning() body uses morning_json_escape (inlined) not bare provenance_json_escape.
# Per LESSONS 2026-06-05 (dispatcher forward-reference) and LESSONS 2026-06-03
# (UTF-8 sign-extension), the inlined helper mirrors provenance_json_escape's
# code-ge-0 guard.
if ! grep -qE '^morning_json_escape\(\)' "$REPO_ROOT/bin/fleet"; then
  echo "FAIL: AC#10 morning_json_escape() helper missing"
  exit 1
fi
# Ensure the inlined helper has the code >= 0 guard.
M_ESC_BODY="$(awk '/^morning_json_escape\(\) \{/,/^\}/' "$REPO_ROOT/bin/fleet")"
if ! echo "$M_ESC_BODY" | grep -qF '"$code" -ge 0'; then
  echo "FAIL: AC#10 morning_json_escape() missing 'code -ge 0' UTF-8 guard"
  exit 1
fi
echo "ok: AC#10c morning_json_escape inlined with UTF-8 guard"

# ========================================================================
# Bonus: AC#0/cover-all — golden text byte match (baseline fixture).
#
# Per LESSONS 2026-05-27 ($(cat) trailing-newline trap), we use cp for the
# backup/restore round-trip below (no command-substitution-of-file).
# ========================================================================
if [ ! -f "$GOLDEN_TEXT" ]; then
  echo "FAIL: golden text fixture missing at $GOLDEN_TEXT"
  exit 1
fi
# Reset the inbox-state + last-weekly markers so the "since last run / last
# weekly" lines render deterministically (per inbox AC#7/AC#8 we know the
# first invocation prints "since last run never" / "last weekly: never").
rm -f "$HOME/.cache/fleet/inbox-state" "$HOME/.cache/fleet/last-weekly-run"
"$FLEET" morning > "$TMP/morning.golden.out.txt"
if ! diff -u "$GOLDEN_TEXT" "$TMP/morning.golden.out.txt"; then
  echo "FAIL: golden text byte-match failed (see diff above)"
  exit 1
fi
echo "ok: golden text byte-match"

echo "ok: tests/morning.sh passed"
