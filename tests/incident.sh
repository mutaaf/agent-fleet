#!/bin/bash
# tests/incident.sh — `bin/fleet incident` post-mortem composition test.
#
# Ticket 0037. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0037-fleet-incident-post-mortem-from-events.md. The
# `incident` reader is a pure consumer of the existing events.jsonl
# channel + `gh pr view` for one network-touching open-action check;
# everything else is local file-walk + awk synthesis.
#
# Fixtures: three (sometimes more) synthetic projects seeded under a
# tmpdir FLEET_DISCOVERY_ROOT, mirroring tests/atlas.sh and
# tests/morning.sh. Time is pinned via FLEET_NOW_OVERRIDE so the
# rendered window header + every "Nh ago" age stays deterministic.
#
# Per LESSONS 2026-05-26 ($HOME/.local/bin stubs survive lib/common.sh's
# PATH reset). Per LESSONS 2026-05-27 every fixture file is copied via
# `cp` — never `$(cat …)` — to preserve byte-exact trailing newlines.
# Per LESSONS 2026-06-01 (`grep -c file || echo 0` double-print trap)
# every count uses `awk … END { print n+0 }`. Per LESSONS 2026-05-30
# (`grep -F --` flag trap) every help-text grep uses `grep -qF -- "$kw"`.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-incident-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache, $HOME/.local/bin are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"

# Stable epoch anchor — 2026-06-07T12:00:00Z (a Sunday).
NOW_EPOCH=1780833600
export FLEET_NOW_OVERRIDE="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_72H_AGO=$(( NOW_EPOCH - 72 * 3600 ))
T_60H_AGO=$(( NOW_EPOCH - 60 * 3600 ))
T_48H_AGO=$(( NOW_EPOCH - 48 * 3600 ))
T_30H_AGO=$(( NOW_EPOCH - 30 * 3600 ))
T_24H_AGO=$(( NOW_EPOCH - 24 * 3600 ))
T_12H_AGO=$(( NOW_EPOCH - 12 * 3600 ))
T_6H_AGO=$(( NOW_EPOCH - 6 * 3600 ))
T_3H_AGO=$(( NOW_EPOCH - 3 * 3600 ))
T_1H_AGO=$(( NOW_EPOCH - 1 * 3600 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

mk_manifest() {  # $1 = slug
  local slug="$1"
  mkdir -p "$FIXTURE/$slug"
  cat > "$FIXTURE/$slug/agents.config.sh" <<CFG
PROJECT_NAME="$slug"
SLUG="$slug"
NAMESPACE="com.$slug"
REPO_URL="https://github.com/example/$slug"
SELF_CANCEL="20990101"
CFG
}

# ----- Fixture A: agent-fleet (sendback_streak cluster) ------------------
mk_manifest agent-fleet
AF_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$AF_CACHE"
{
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"pr_opened","number":"88","branch":"feat/0033-quiet-hours"}\n' \
    "$(iso_at "$T_60H_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"88","headline":"QUIET_HOURS edge case","text_sha":"deadbe01"}\n' \
    "$(iso_at $(( T_60H_AGO + 1800 )))"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"pr_opened","number":"89","branch":"feat/0033-quiet-hours-v2"}\n' \
    "$(iso_at "$T_48H_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"89","headline":"QUIET_HOURS edge case","text_sha":"deadbe02"}\n' \
    "$(iso_at $(( T_48H_AGO + 1800 )))"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"pr_opened","number":"90","branch":"feat/0033-quiet-hours-v3"}\n' \
    "$(iso_at "$T_30H_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"90","headline":"QUIET_HOURS edge case","text_sha":"deadbe03"}\n' \
    "$(iso_at $(( T_30H_AGO + 1800 )))"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3","prs":"88,89,90"}\n' \
    "$(iso_at $(( T_30H_AGO + 3600 )))"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"rollback","type":"rollback_opened","pr":"91","reverts":"88","merge_commit":"abcdef0123"}\n' \
    "$(iso_at "$T_24H_AGO")"
} > "$AF_CACHE/events.jsonl"

# ----- Fixture B: almanac (clean week — no clusters) ---------------------
mk_manifest almanac
AL_CACHE="$HOME/.cache/almanac-agent"
mkdir -p "$AL_CACHE"
{
  printf '{"ts":"%s","slug":"almanac","phase":"ship","type":"run_started","pid":"123"}\n' \
    "$(iso_at "$T_12H_AGO")"
  printf '{"ts":"%s","slug":"almanac","phase":"ship","type":"run_completed","exit":"0","duration_ms":"45000"}\n' \
    "$(iso_at $(( T_12H_AGO + 45 )))"
} > "$AL_CACHE/events.jsonl"

# ----- Fixture C: courtiq (prompts_revision_walk cluster) ----------------
mk_manifest courtiq
CQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$CQ_CACHE"
{
  printf '{"ts":"%s","slug":"courtiq","phase":"ship","type":"prompts_drift","pinned":"abc123","actual":"def456"}\n' \
    "$(iso_at "$T_48H_AGO")"
  printf '{"ts":"%s","slug":"courtiq","phase":"revert","type":"prompts_reverted","from":"def456","to":"abc123","pr":"77","reason":"regression"}\n' \
    "$(iso_at "$T_24H_AGO")"
} > "$CQ_CACHE/events.jsonl"

# ----- gh stub: revert PR #91 returns state:OPEN (so it's an open action) -
cat > "$HOME/.local/bin/gh" <<'STUB'
#!/bin/bash
# $1=pr $2=view $3=<num> --json state
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  # Emit the requested JSON. Tests only care about state.
  echo '{"state":"OPEN"}'
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/gh"

export PATH="$HOME/.local/bin:$PATH"

# ========================================================================
# AC #1 — `bin/fleet incident --since 72h` walks every discovered project,
#         prints ONE markdown document with exactly four sections in
#         order: # INCIDENT — ..., ## Timeline, ## Cluster summary,
#         ## Open recovery actions. Exits 0.
# ========================================================================
OUT="$TMP/incident.md"
set +e
"$FLEET" incident --since 72h > "$OUT"
EXIT=$?
set -e
if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 incident exit $EXIT (want 0)"; cat "$OUT"; exit 1
fi

# Header line starts with `# INCIDENT — ` and contains an ISO window.
if ! head -1 "$OUT" | grep -qE '^# INCIDENT — '; then
  echo "FAIL: AC#1 missing header line"; head -3 "$OUT"; exit 1
fi
if ! head -1 "$OUT" | grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z → 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'; then
  echo "FAIL: AC#1 header window range malformed"; head -1 "$OUT"; exit 1
fi

# Four section headings, in order. Use awk to capture order.
order="$(awk '
  /^## Timeline$/             { print "Timeline"; next }
  /^## Cluster summary$/      { print "Cluster summary"; next }
  /^## Open recovery actions$/ { print "Open recovery actions"; next }
' "$OUT" | tr '\n' '|')"
if [ "$order" != "Timeline|Cluster summary|Open recovery actions|" ]; then
  echo "FAIL: AC#1 section order is '$order' (want 'Timeline|Cluster summary|Open recovery actions|')"
  cat "$OUT"; exit 1
fi
echo "ok: AC#1 four-section structure + header + exit 0"

# ========================================================================
# AC #2 — --slug NAME narrows the report. Empty events for that slug
#         in the window: prints the "No events in window" body and
#         exits 0.
# ========================================================================
SLUG_OUT="$TMP/incident.slug.md"
set +e
"$FLEET" incident --since 72h --slug agent-fleet > "$SLUG_OUT"
SLUG_EXIT=$?
set -e
if [ "$SLUG_EXIT" != "0" ]; then
  echo "FAIL: AC#2 --slug agent-fleet exit $SLUG_EXIT"; cat "$SLUG_OUT"; exit 1
fi
# Header should mention only agent-fleet.
if ! head -1 "$SLUG_OUT" | grep -qF -- 'agent-fleet'; then
  echo "FAIL: AC#2 --slug header missing 'agent-fleet'"; head -1 "$SLUG_OUT"; exit 1
fi
# No mention of courtiq/almanac in the slug-filtered output.
if grep -qF -- 'courtiq' "$SLUG_OUT"; then
  echo "FAIL: AC#2 --slug agent-fleet leaked courtiq"; cat "$SLUG_OUT"; exit 1
fi

# Empty branch: a slug that has a manifest but no events in the window.
mk_manifest sparkly
mkdir -p "$HOME/.cache/sparkly-agent"
: > "$HOME/.cache/sparkly-agent/events.jsonl"
EMPTY_OUT="$TMP/incident.empty.md"
set +e
"$FLEET" incident --since 72h --slug sparkly > "$EMPTY_OUT"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: AC#2 empty slug exit $EMPTY_EXIT"; cat "$EMPTY_OUT"; exit 1
fi
if ! grep -qF -- 'No events in window. fleet is quiet — this is normal.' "$EMPTY_OUT"; then
  echo "FAIL: AC#2 empty slug body missing quiet message"; cat "$EMPTY_OUT"; exit 1
fi
echo "ok: AC#2 --slug narrows + empty quiet branch"

# ========================================================================
# AC #3 — The Timeline section lists every event in the window in strict
#         ISO8601 chronological order, one bullet per event. Per-event
#         format: `- <iso-ts> — \`<type>\` <one-line-payload-render>`.
#         Asserted against three event-type fixtures.
# ========================================================================
# Extract just the Timeline body.
TL_BODY="$TMP/incident.timeline.txt"
awk '
  /^## Timeline$/        { in_tl = 1; next }
  /^## /                  { in_tl = 0 }
  in_tl && /^- /         { print }
' "$OUT" > "$TL_BODY"

if ! awk 'END { print (NR+0) }' "$TL_BODY" | grep -qE '^[0-9]+$'; then
  echo "FAIL: AC#3 timeline body unreadable"; exit 1
fi
tl_count="$(awk 'END { print (NR+0) }' "$TL_BODY")"
if [ "$tl_count" -lt 8 ]; then
  echo "FAIL: AC#3 timeline body has $tl_count rows (want >= 8 from sendback fixture)"
  cat "$TL_BODY"; exit 1
fi

# Chronological order: every line starts with an ISO8601 ts. Assert
# the ts column is monotonically non-decreasing — two events at the
# SAME ts can render in either order (the producer's stable secondary
# sort is on the raw JSON, not the rendered line).
if ! awk '
  match($0, /20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/) {
    ts = substr($0, RSTART, RLENGTH)
    if (prev != "" && ts < prev) { exit 1 }
    prev = ts
  }
' "$TL_BODY"; then
  echo "FAIL: AC#3 timeline not in ISO chronological order"
  cat "$TL_BODY"
  exit 1
fi

# Per-event format: pr_opened line.
if ! grep -qE '^- 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — `pr_opened` #88' "$TL_BODY"; then
  echo "FAIL: AC#3 pr_opened line format malformed"
  grep 'pr_opened' "$TL_BODY"; exit 1
fi

# ship_paused line.
if ! grep -qE '^- 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — `ship_paused` ' "$TL_BODY"; then
  echo "FAIL: AC#3 ship_paused line format malformed"
  grep 'ship_paused' "$TL_BODY"; exit 1
fi

# rollback_opened line.
if ! grep -qE '^- 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z — `rollback_opened` ' "$TL_BODY"; then
  echo "FAIL: AC#3 rollback_opened line format malformed"
  grep 'rollback_opened' "$TL_BODY"; exit 1
fi
echo "ok: AC#3 timeline format + chronological order"

# ========================================================================
# AC #4 — Cluster summary detects the four named clusters. One bullet
#         per detected cluster; "No clusters detected — events are
#         independent." when none fire.
# ========================================================================
CL_BODY="$TMP/incident.clusters.txt"
awk '
  /^## Cluster summary$/         { in_cs = 1; next }
  /^## /                          { in_cs = 0 }
  in_cs && NF > 0                { print }
' "$OUT" > "$CL_BODY"

# sendback_streak detected (agent-fleet).
if ! grep -qF -- 'sendback_streak' "$CL_BODY"; then
  echo "FAIL: AC#4 sendback_streak cluster not detected"; cat "$CL_BODY"; exit 1
fi
# rollback_after_merge detected (agent-fleet PR #88 → revert #91).
if ! grep -qF -- 'rollback_after_merge' "$CL_BODY"; then
  echo "FAIL: AC#4 rollback_after_merge cluster not detected"; cat "$CL_BODY"; exit 1
fi
# prompts_revision_walk detected (courtiq drift→reverted).
if ! grep -qF -- 'prompts_revision_walk' "$CL_BODY"; then
  echo "FAIL: AC#4 prompts_revision_walk cluster not detected"; cat "$CL_BODY"; exit 1
fi
# budget_block_recurrence NOT detected (no budget_block events).
if grep -qF -- 'budget_block_recurrence' "$CL_BODY"; then
  echo "FAIL: AC#4 budget_block_recurrence falsely detected"; cat "$CL_BODY"; exit 1
fi

# Now the empty-cluster branch: clean fleet.
EMPTY_FIXTURE="$TMP/empty_projects"
mkdir -p "$EMPTY_FIXTURE/blank"
cat > "$EMPTY_FIXTURE/blank/agents.config.sh" <<CFG
PROJECT_NAME="blank"
SLUG="blank"
NAMESPACE="com.blank"
REPO_URL="https://github.com/example/blank"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/blank-agent"
{
  printf '{"ts":"%s","slug":"blank","phase":"ship","type":"run_started","pid":"42"}\n' \
    "$(iso_at "$T_6H_AGO")"
  printf '{"ts":"%s","slug":"blank","phase":"ship","type":"run_completed","exit":"0","duration_ms":"45000"}\n' \
    "$(iso_at $(( T_6H_AGO + 45 )))"
} > "$HOME/.cache/blank-agent/events.jsonl"

CL_EMPTY="$TMP/incident.cluster_empty.md"
set +e
FLEET_DISCOVERY_ROOT="$EMPTY_FIXTURE" "$FLEET" incident --since 72h > "$CL_EMPTY"
EMPTY_EXIT=$?
set -e
if [ "$EMPTY_EXIT" != "0" ]; then
  echo "FAIL: AC#4 clean-fleet incident exit $EMPTY_EXIT"; cat "$CL_EMPTY"; exit 1
fi
if ! grep -qF -- 'No clusters detected — events are independent.' "$CL_EMPTY"; then
  echo "FAIL: AC#4 clean-fleet missing 'No clusters detected' bullet"
  cat "$CL_EMPTY"; exit 1
fi

# Now the budget_block_recurrence positive case.
B_FIX="$TMP/budget_projects"
mkdir -p "$B_FIX/billy"
cat > "$B_FIX/billy/agents.config.sh" <<CFG
PROJECT_NAME="billy"
SLUG="billy"
NAMESPACE="com.billy"
REPO_URL="https://github.com/example/billy"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/billy-agent"
{
  # Two budget_block events on different UTC days.
  printf '{"ts":"%s","slug":"billy","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_48H_AGO")"
  printf '{"ts":"%s","slug":"billy","phase":"ship","type":"budget_block","reason":"daily_cap","spent":"5.00","cap":"5.00"}\n' \
    "$(iso_at "$T_3H_AGO")"
} > "$HOME/.cache/billy-agent/events.jsonl"

B_OUT="$TMP/incident.budget.md"
set +e
FLEET_DISCOVERY_ROOT="$B_FIX" "$FLEET" incident --since 72h > "$B_OUT"
B_EXIT=$?
set -e
if [ "$B_EXIT" != "0" ]; then
  echo "FAIL: AC#4 budget fixture exit $B_EXIT"; cat "$B_OUT"; exit 1
fi
if ! grep -qF -- 'budget_block_recurrence' "$B_OUT"; then
  echo "FAIL: AC#4 budget_block_recurrence not detected"; cat "$B_OUT"; exit 1
fi
echo "ok: AC#4 four cluster detectors + empty-cluster branch"

# ========================================================================
# AC #5 — Open recovery actions lists ONLY actions with a typed-event
#         opener but no typed-event closer. Three branches + empty.
# ========================================================================
OA_BODY="$TMP/incident.actions.txt"
awk '
  /^## Open recovery actions$/   { in_oa = 1; next }
  /^## /                          { in_oa = 0 }
  in_oa && NF > 0                { print }
' "$OUT" > "$OA_BODY"

# resume action — ship_paused with no ship_resumed.
if ! grep -qE 'fleet resume agent-fleet' "$OA_BODY"; then
  echo "FAIL: AC#5 'fleet resume agent-fleet' action missing"
  cat "$OA_BODY"; exit 1
fi
# promote action — 3 lesson_draft_emitted with no lesson_promoted.
if ! grep -qF -- 'fleet lessons-promote' "$OA_BODY"; then
  echo "FAIL: AC#5 'fleet lessons-promote' action missing"
  cat "$OA_BODY"; exit 1
fi
# merge_revert action — revert PR #91 still OPEN per gh stub.
if ! grep -qE 'merge or close revert PR #91' "$OA_BODY"; then
  echo "FAIL: AC#5 'merge or close revert PR #91' action missing"
  cat "$OA_BODY"; exit 1
fi

# Empty branch — every action has a closer.
CLOSED_FIX="$TMP/closed_projects"
mkdir -p "$CLOSED_FIX/closy"
cat > "$CLOSED_FIX/closy/agents.config.sh" <<CFG
PROJECT_NAME="closy"
SLUG="closy"
NAMESPACE="com.closy"
REPO_URL="https://github.com/example/closy"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/closy-agent"
{
  printf '{"ts":"%s","slug":"closy","phase":"ship","type":"ship_paused","reason":"sendback_streak","count":"3"}\n' \
    "$(iso_at "$T_48H_AGO")"
  printf '{"ts":"%s","slug":"closy","phase":"resume","type":"ship_resumed","source":"closy","paused_for":"23h","reason":"streak cleared","forced":"0"}\n' \
    "$(iso_at "$T_24H_AGO")"
} > "$HOME/.cache/closy-agent/events.jsonl"

CLOSED_OUT="$TMP/incident.closed.md"
set +e
FLEET_DISCOVERY_ROOT="$CLOSED_FIX" "$FLEET" incident --since 72h > "$CLOSED_OUT"
CLOSED_EXIT=$?
set -e
if [ "$CLOSED_EXIT" != "0" ]; then
  echo "FAIL: AC#5 closed-fixture exit $CLOSED_EXIT"; cat "$CLOSED_OUT"; exit 1
fi
if ! grep -qF -- 'No open actions — every incident in the window has a recorded recovery.' "$CLOSED_OUT"; then
  echo "FAIL: AC#5 closed fixture missing 'No open actions' bullet"
  cat "$CLOSED_OUT"; exit 1
fi
echo "ok: AC#5 three open-action detectors + empty-actions branch"

# ========================================================================
# AC #6 — --json emits one JSON object combining the three synthesis
#         sections. Parsed via node -e.
# ========================================================================
JSON_OUT="$TMP/incident.json"
set +e
"$FLEET" incident --since 72h --json > "$JSON_OUT"
JSON_EXIT=$?
set -e
if [ "$JSON_EXIT" != "0" ]; then
  echo "FAIL: AC#6 --json exit $JSON_EXIT"; cat "$JSON_OUT"; exit 1
fi
node -e '
  const fs = require("fs");
  const raw = fs.readFileSync(process.argv[1], "utf8").trim();
  let obj;
  try { obj = JSON.parse(raw); }
  catch (e) { console.error("FAIL: AC#6 invalid JSON: " + e.message); console.error(raw); process.exit(1); }
  for (const k of ["window","slugs","clusters","open_actions"]) {
    if (!(k in obj)) { console.error("FAIL: AC#6 missing key " + k); process.exit(1); }
  }
  if (!("start" in obj.window) || !("end" in obj.window)) {
    console.error("FAIL: AC#6 window.start/.end missing"); process.exit(1);
  }
  if (!Array.isArray(obj.slugs))           { console.error("FAIL: AC#6 slugs not array");        process.exit(1); }
  if (!Array.isArray(obj.clusters))        { console.error("FAIL: AC#6 clusters not array");     process.exit(1); }
  if (!Array.isArray(obj.open_actions))    { console.error("FAIL: AC#6 open_actions not array"); process.exit(1); }
  if (obj.clusters.length < 1) {
    console.error("FAIL: AC#6 expected >= 1 cluster, got " + obj.clusters.length);
    process.exit(1);
  }
  // Each cluster has type/slug/prs/first_ts/last_ts.
  for (const c of obj.clusters) {
    for (const k of ["type","slug","prs","first_ts","last_ts"]) {
      if (!(k in c)) { console.error("FAIL: AC#6 cluster missing " + k + ": " + JSON.stringify(c)); process.exit(1); }
    }
  }
  // Each open_action has kind/slug/remediation.
  for (const a of obj.open_actions) {
    for (const k of ["kind","slug","remediation"]) {
      if (!(k in a)) { console.error("FAIL: AC#6 open_action missing " + k + ": " + JSON.stringify(a)); process.exit(1); }
    }
  }
  // Expect at least one of each kind in this fixture (resume / promote / merge_revert).
  const kinds = new Set(obj.open_actions.map(a => a.kind));
  for (const k of ["resume","promote","merge_revert"]) {
    if (!kinds.has(k)) { console.error("FAIL: AC#6 open_actions missing kind=" + k); process.exit(1); }
  }
  console.log("ok: AC#6 --json schema + cluster + open_action types");
' "$JSON_OUT"

# ========================================================================
# AC #7 — --since is REQUIRED. Missing: exit 2, specific stderr message.
#         Invalid: exit 2, specific stderr message.
# ========================================================================
set +e
ERR1="$TMP/incident.miss.err"
"$FLEET" incident > /dev/null 2> "$ERR1"
MISS_EXIT=$?
set -e
if [ "$MISS_EXIT" != "2" ]; then
  echo "FAIL: AC#7 missing --since exit $MISS_EXIT (want 2)"; cat "$ERR1"; exit 1
fi
if ! grep -qF -- 'incident: --since' "$ERR1"; then
  echo "FAIL: AC#7 missing --since stderr message"; cat "$ERR1"; exit 1
fi

set +e
ERR2="$TMP/incident.inv.err"
"$FLEET" incident --since forever > /dev/null 2> "$ERR2"
INV_EXIT=$?
set -e
if [ "$INV_EXIT" != "2" ]; then
  echo "FAIL: AC#7 invalid --since exit $INV_EXIT (want 2)"; cat "$ERR2"; exit 1
fi
if ! grep -qF -- 'incident: invalid --since' "$ERR2"; then
  echo "FAIL: AC#7 invalid --since stderr message"; cat "$ERR2"; exit 1
fi
echo "ok: AC#7 --since required + invalid"

# ========================================================================
# AC #8 — --out FILE writes the markdown to FILE and prints a stderr line.
#         The file's bytes match what stdout would have produced.
# ========================================================================
OUT_FILE="$TMP/incident.out.md"
OUT_ERR="$TMP/incident.out.err"
OUT_STDOUT="$TMP/incident.out.stdout.md"
# Capture a fresh stdout invocation under IDENTICAL fixture state, so
# the byte-comparison is apples-to-apples even after earlier ACs seeded
# extra slugs (sparkly, etc.).
set +e
"$FLEET" incident --since 72h > "$OUT_STDOUT"
"$FLEET" incident --since 72h --out "$OUT_FILE" 2> "$OUT_ERR"
OUTF_EXIT=$?
set -e
if [ "$OUTF_EXIT" != "0" ]; then
  echo "FAIL: AC#8 --out exit $OUTF_EXIT"; cat "$OUT_ERR"; exit 1
fi
if ! grep -qF -- "incident: wrote post-mortem to $OUT_FILE" "$OUT_ERR"; then
  echo "FAIL: AC#8 --out stderr message missing"; cat "$OUT_ERR"; exit 1
fi
if [ ! -s "$OUT_FILE" ]; then
  echo "FAIL: AC#8 --out FILE is empty"; exit 1
fi
# File bytes match what stdout produced on the freshly-captured run.
if ! diff -u "$OUT_STDOUT" "$OUT_FILE" >/dev/null; then
  echo "FAIL: AC#8 --out FILE bytes do not match stdout output"
  diff -u "$OUT_STDOUT" "$OUT_FILE" | head -20; exit 1
fi
echo "ok: AC#8 --out FILE byte-equal to stdout"

# ========================================================================
# AC #9 — `incident --help` prints USAGE mentioning the flags, exits 0.
# ========================================================================
HELP_OUT="$TMP/incident.help.txt"
set +e
"$FLEET" incident --help > "$HELP_OUT"
HELP_EXIT=$?
set -e
if [ "$HELP_EXIT" != "0" ]; then
  echo "FAIL: AC#9 --help exit $HELP_EXIT (want 0)"; cat "$HELP_OUT"; exit 1
fi
for kw in --since --slug --json --out; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#9 --help missing keyword '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
# Help block ends with exit 0 — sanity check: no fall-through to status block.
if grep -qF -- 'INSTALLED' "$HELP_OUT"; then
  echo "FAIL: AC#9 --help fell through to default status block"
  cat "$HELP_OUT"; exit 1
fi
echo "ok: AC#9 --help + exit 0 + no fall-through"

# ========================================================================
# AC #10 — Source-level check: `incident()` and its dispatcher block end
#          with explicit `exit N`. Per LESSONS 2026-06-05, every helper
#          incident() calls (`tail_render_event`, `digest_parse_since`,
#          `provenance_json_escape`) is either defined above the
#          dispatcher block or inlined locally.
# ========================================================================
# (a) dispatcher block contains `incident "$@"` and ends with the `fi`.
if ! grep -qE '^if \[ "\$CMD" = "incident" \]; then' "$REPO_ROOT/bin/fleet"; then
  echo "FAIL: AC#10 dispatcher block 'if [ \"\$CMD\" = \"incident\" ]; then' missing"
  exit 1
fi
# (b) the function body contains at least one explicit `exit 0` or `exit 2`.
if ! awk '
  /^incident\(\) \{/                  { inside = 1; next }
  inside && /^\}/                      { inside = 0 }
  inside && /^[[:space:]]*exit [0-9]+/ { found = 1 }
  END                                  { exit found ? 0 : 1 }
' "$REPO_ROOT/bin/fleet"; then
  echo "FAIL: AC#10 incident() body missing explicit exit N"
  exit 1
fi
# (c) helper-ordering: digest_parse_since defined BEFORE incident().
# Use a single-pass awk that yields the first line of each.
ORDER="$(awk '
  /^digest_parse_since\(\) \{/        { if (!d) d = NR }
  /^incident\(\) \{/                  { if (!i) i = NR }
  END                                  { print d "," i }
' "$REPO_ROOT/bin/fleet")"
d_line="${ORDER%%,*}"
i_line="${ORDER##*,}"
if [ -z "$d_line" ] || [ -z "$i_line" ] || [ "$d_line" -ge "$i_line" ]; then
  echo "FAIL: AC#10 helper ordering bad: digest_parse_since@$d_line vs incident@$i_line"
  exit 1
fi
echo "ok: AC#10 dispatcher + exit N + helper ordering"

# ========================================================================
# Coverage tally.
# ========================================================================
echo "ok: tests/incident.sh passed (10/10 assertions)"
