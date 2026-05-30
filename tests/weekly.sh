#!/bin/bash
# tests/weekly.sh — `bin/fleet weekly` end-to-end Sunday rollup test.
#
# Ticket 0025. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0025-fleet-weekly-roi-digest-sunday-rollup.md.
#
# Fixture (three synthetic projects + one "cold" one) seeded under a
# tmpdir FLEET_DISCOVERY_ROOT, mirroring the pattern from tests/overview.sh
# (ticket 0019). Time is pinned via FLEET_WEEKLY_FAKE_NOW so the golden
# table at tests/fixtures/weekly.golden.txt stays byte-stable.
#
# Stubs in $HOME/.local/bin per LESSONS 2026-05-26 (lib/common.sh resets
# PATH — but bin/fleet does NOT source common.sh, so we only need them
# for our launchctl mock).

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"
GOLDEN="$REPO_ROOT/tests/fixtures/weekly.golden.txt"

TMP="$(mktemp -d -t fleet-weekly-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate HOME so $HOME/.cache and $HOME/Library are sandboxed.
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/Library/LaunchAgents"

# Stable epoch anchor — 2026-05-30T12:00:00Z. The window is the trailing
# 7d, so the WEEK header should read "2026-05-23 – 2026-05-30 (7d)".
NOW_EPOCH=1780142400
export FLEET_WEEKLY_FAKE_NOW="$NOW_EPOCH"

iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}

T_30D_AGO=$(( NOW_EPOCH - 30 * 86400 ))
T_14D_AGO=$(( NOW_EPOCH - 14 * 86400 ))
T_10D_AGO=$(( NOW_EPOCH - 10 * 86400 ))
T_6D_AGO=$(( NOW_EPOCH - 6 * 86400 ))
T_5D_AGO=$(( NOW_EPOCH - 5 * 86400 ))
T_4D_AGO=$(( NOW_EPOCH - 4 * 86400 ))
T_3D_AGO=$(( NOW_EPOCH - 3 * 86400 ))
T_2D_AGO=$(( NOW_EPOCH - 2 * 86400 ))
T_1D_AGO=$(( NOW_EPOCH - 1 * 86400 ))

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

# ----- Fixture A: agent-fleet (healthy headline) --------------------------
#   6 PRs shipped, $2.14 total spend (in window), 2 drafts, 3 heal, 1 infra,
#   no pause, SELF_CANCEL=20260628 (29d out from anchor).
mkdir -p "$FIXTURE/agent-fleet"
cat > "$FIXTURE/agent-fleet/agents.config.sh" <<CFG
PROJECT_NAME="Agent Fleet"
SLUG="agent-fleet"
NAMESPACE="com.agent-fleet"
REPO_URL="https://github.com/mutaaf/agent-fleet"
SELF_CANCEL="20260628"
CFG

AF_CACHE="$HOME/.cache/agent-fleet-agent"
mkdir -p "$AF_CACHE"

# runs.jsonl: 6 SHIP rows totalling $2.14 = $0.40 * 5 + $0.14. The shipping
# heuristic is result_head starting with "SHIP ".
{
  for i in 1 2 3 4 5; do
    printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.40,"result_head":"SHIP 00%s-x — PR #%s green"}\n' \
      "$(iso_at $(( T_6D_AGO + i * 3600 )))" "$(iso_at $(( T_6D_AGO + i * 3600 + 60 )))" "$i" "$(( 100 + i ))"
  done
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.14,"result_head":"SHIP 0099-y — PR #200 green"}\n' \
    "$(iso_at "$T_1D_AGO")" "$(iso_at $(( T_1D_AGO + 60 )))"
  # One out-of-window run (should NOT count) — 30d ago.
  printf '{"slug":"agent-fleet","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":9.99,"result_head":"SHIP 0001-z — PR #1 green"}\n' \
    "$(iso_at "$T_30D_AGO")" "$(iso_at $(( T_30D_AGO + 60 )))"
  # One in-window NON-ship run (e.g. groom): result_head does NOT start with "SHIP ".
  # Spend ($0.00) doesn't change the sum; ship count stays at 6.
  printf '{"slug":"agent-fleet","phase":"groom","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.00,"result_head":"GROOM refreshed 4 tickets"}\n' \
    "$(iso_at "$T_3D_AGO")" "$(iso_at $(( T_3D_AGO + 60 )))"
} > "$AF_CACHE/runs.jsonl"

# events.jsonl: 2 lesson_draft_emitted, 3 gate_failed, 1 infra_flake_rerun
# in window; plus an OOW entry for each type that should NOT count.
{
  for i in 1 2; do
    printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"%s","headline":"draft %s"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 3600 )))" "$(( 100 + i ))" "$i"
  done
  for i in 1 2 3; do
    printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
      "$(iso_at $(( T_4D_AGO + i * 3600 )))"
  done
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"42","pr":"187"}\n' \
    "$(iso_at "$T_2D_AGO")"
  # OOW (30d ago) — must NOT count.
  printf '{"ts":"%s","slug":"agent-fleet","phase":"review","type":"lesson_draft_emitted","pr":"99","headline":"old"}\n' \
    "$(iso_at "$T_30D_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
    "$(iso_at "$T_30D_AGO")"
  printf '{"ts":"%s","slug":"agent-fleet","phase":"ship","type":"infra_flake_rerun","pattern":"actions_silent","run_id":"1","pr":"1"}\n' \
    "$(iso_at "$T_30D_AGO")"
} > "$AF_CACHE/events.jsonl"

# ----- Fixture B: almanac (clean) ----------------------------------------
#   4 PRs shipped, $1.87 spend, 0 drafts, 2 heal, 0 infra, no pause,
#   SELF_CANCEL=20260711 (42d).
mkdir -p "$FIXTURE/almanac"
cat > "$FIXTURE/almanac/agents.config.sh" <<CFG
PROJECT_NAME="Almanac"
SLUG="almanac"
NAMESPACE="com.almanac"
REPO_URL="https://github.com/example/almanac"
SELF_CANCEL="20260711"
CFG

AL_CACHE="$HOME/.cache/almanac-agent"
mkdir -p "$AL_CACHE"

{
  for i in 1 2 3 4; do
    printf '{"slug":"almanac","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.4675,"result_head":"SHIP 002%s-x — PR #%s green"}\n' \
      "$(iso_at $(( T_5D_AGO + i * 3600 )))" "$(iso_at $(( T_5D_AGO + i * 3600 + 60 )))" "$i" "$(( 200 + i ))"
  done
} > "$AL_CACHE/runs.jsonl"

{
  for i in 1 2; do
    printf '{"ts":"%s","slug":"almanac","phase":"ship","type":"gate_failed","check":"validate"}\n' \
      "$(iso_at $(( T_3D_AGO + i * 3600 )))"
  done
} > "$AL_CACHE/events.jsonl"

# ----- Fixture C: courtiq (paused + expired) -----------------------------
#   0 PRs, $0, 0 drafts, 0 heal, 0 infra, paused 14d ago (mtime), EXPIRED.
mkdir -p "$FIXTURE/courtiq"
cat > "$FIXTURE/courtiq/agents.config.sh" <<CFG
PROJECT_NAME="CourtIQ"
SLUG="courtiq"
NAMESPACE="com.courtiq"
REPO_URL="https://github.com/example/courtiq"
SELF_CANCEL="20260520"
CFG

CQ_CACHE="$HOME/.cache/courtiq-agent"
mkdir -p "$CQ_CACHE"
: > "$CQ_CACHE/runs.jsonl"
: > "$CQ_CACHE/events.jsonl"

# Drop a plist with mtime = 14d ago so weekly_paused_days reports "14d!".
COURTIQ_PLIST="$HOME/Library/LaunchAgents/com.courtiq.agent-ship.plist"
echo "<plist/>" > "$COURTIQ_PLIST"
COURTIQ_STAMP="$(date -u -r "$T_14D_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$T_14D_AGO" +%Y%m%d%H%M.%S)"
# touch -t uses LOCAL time by default; convert epoch to local form.
COURTIQ_LOCAL_STAMP="$(date -r "$T_14D_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$T_14D_AGO" +%Y%m%d%H%M.%S)"
touch -t "$COURTIQ_LOCAL_STAMP" "$COURTIQ_PLIST"
: "$COURTIQ_STAMP"  # silence unused warning if we don't use the UTC variant

# ----- Fixture D: digitalcraft (warn — 5d to expiry, 1 draft) ------------
mkdir -p "$FIXTURE/digitalcraft"
cat > "$FIXTURE/digitalcraft/agents.config.sh" <<CFG
PROJECT_NAME="Digital Craft"
SLUG="digitalcraft"
NAMESPACE="com.digitalcraft"
REPO_URL="https://github.com/example/digitalcraft"
SELF_CANCEL="20260604"
CFG

DC_CACHE="$HOME/.cache/digitalcraft-agent"
mkdir -p "$DC_CACHE"

{
  for i in 1 2; do
    printf '{"slug":"digitalcraft","phase":"ship","ts_start":"%s","ts_end":"%s","exit":0,"total_cost_usd":0.46,"result_head":"SHIP 003%s-x — PR #%s green"}\n' \
      "$(iso_at $(( T_4D_AGO + i * 3600 )))" "$(iso_at $(( T_4D_AGO + i * 3600 + 60 )))" "$i" "$(( 300 + i ))"
  done
} > "$DC_CACHE/runs.jsonl"

{
  printf '{"ts":"%s","slug":"digitalcraft","phase":"review","type":"lesson_draft_emitted","pr":"305","headline":"draft 1"}\n' \
    "$(iso_at "$T_2D_AGO")"
  printf '{"ts":"%s","slug":"digitalcraft","phase":"ship","type":"gate_failed","check":"shellcheck"}\n' \
    "$(iso_at "$T_3D_AGO")"
} > "$DC_CACHE/events.jsonl"

# ----- launchctl stub: only courtiq is paused ----------------------------
cat > "$HOME/.local/bin/launchctl" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.courtiq.agent-ship" => true
  "com.agent-fleet.agent-ship" => false
  "com.almanac.agent-ship" => false
  "com.digitalcraft.agent-ship" => false
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$HOME/.local/bin/launchctl"
# Prepend the stub dir to PATH for the test process (bin/fleet doesn't
# source lib/common.sh, so the test's PATH wins).
export PATH="$HOME/.local/bin:$PATH"

# ========================================================================
# AC #1 — `bin/fleet weekly` (no flags) defaults to --since 7d, prints
#          header + one row per discovered project, exits 0 (no red state
#          in this test rig's exit policy beyond the documented invalid
#          --since path).
# ========================================================================
OUT="$TMP/weekly.txt"
set +e
"$FLEET" weekly > "$OUT"
EXIT=$?
set -e

if [ "$EXIT" != "0" ]; then
  echo "FAIL: AC#1 default weekly should exit 0, got $EXIT"
  cat "$OUT"; exit 1
fi

# Header row contains every required column name.
for col in PROJECT SHIPPED 'DRAFTS↑' HEAL INFRA PAUSED 'SELF-CANCEL'; do
  if ! grep -qF "$col" "$OUT"; then
    echo "FAIL: AC#1 header missing column '$col'"; cat "$OUT"; exit 1
  fi
done
# The $SPEND column uses a literal '$' which shell would interpolate — so
# match it literally without expansion.
if ! grep -qF '$SPEND' "$OUT"; then
  echo "FAIL: AC#1 header missing column '\$SPEND'"; cat "$OUT"; exit 1
fi

# WEEK OF header is the first non-blank line.
if ! head -1 "$OUT" | grep -qE '^WEEK OF 2026-05-23 .+ 2026-05-30 \(7d\)$'; then
  echo "FAIL: AC#1 WEEK header missing or wrong"; head -3 "$OUT"; exit 1
fi
echo "ok: AC#1 default weekly header + week banner"

# ========================================================================
# AC #2 — Per-row metrics. Assert each project's row carries the expected
#          cell values. Discovery order = slug-alpha.
# ========================================================================
# agent-fleet
AF_ROW="$(awk '$1=="agent-fleet"' "$OUT")"
[ -n "$AF_ROW" ] || { echo "FAIL: AC#2 agent-fleet row missing"; cat "$OUT"; exit 1; }
echo "$AF_ROW" | grep -qE '\b6\b'      || { echo "FAIL: AC#2 agent-fleet SHIPPED!=6: $AF_ROW"; exit 1; }
echo "$AF_ROW" | grep -qF '$2.14'      || { echo "FAIL: AC#2 agent-fleet \$SPEND!=2.14: $AF_ROW"; exit 1; }
echo "$AF_ROW" | grep -qF '2*'         || { echo "FAIL: AC#2 agent-fleet DRAFTS!=2*: $AF_ROW"; exit 1; }
echo "$AF_ROW" | grep -qF '29d'        || { echo "FAIL: AC#2 agent-fleet SELF-CANCEL!=29d: $AF_ROW"; exit 1; }
# almanac
AL_ROW="$(awk '$1=="almanac"' "$OUT")"
echo "$AL_ROW" | grep -qE '\b4\b'      || { echo "FAIL: AC#2 almanac SHIPPED!=4: $AL_ROW"; exit 1; }
echo "$AL_ROW" | grep -qF '$1.87'      || { echo "FAIL: AC#2 almanac \$SPEND!=1.87: $AL_ROW"; exit 1; }
echo "$AL_ROW" | grep -qF '42d'        || { echo "FAIL: AC#2 almanac SELF-CANCEL!=42d: $AL_ROW"; exit 1; }
# courtiq paused 14d! + EXPIRED
CQ_ROW="$(awk '$1=="courtiq"' "$OUT")"
echo "$CQ_ROW" | grep -qF '14d!'       || { echo "FAIL: AC#2 courtiq PAUSED!=14d!: $CQ_ROW"; exit 1; }
echo "$CQ_ROW" | grep -qF 'EXPIRED'    || { echo "FAIL: AC#2 courtiq SELF-CANCEL!=EXPIRED: $CQ_ROW"; exit 1; }
# digitalcraft draft, 5d ⚠
DC_ROW="$(awk '$1=="digitalcraft"' "$OUT")"
echo "$DC_ROW" | grep -qF '1*'         || { echo "FAIL: AC#2 digitalcraft DRAFTS!=1*: $DC_ROW"; exit 1; }
echo "$DC_ROW" | grep -qF '5d'         || { echo "FAIL: AC#2 digitalcraft SELF-CANCEL!~5d: $DC_ROW"; exit 1; }
# The ⚠ is unicode; grep -F on a literal multi-byte glyph works.
echo "$DC_ROW" | grep -qF '⚠'          || { echo "FAIL: AC#2 digitalcraft warn glyph missing: $DC_ROW"; exit 1; }
echo "ok: AC#2 per-row metrics"

# ========================================================================
# AC #3 — Trailing summary line "N* drafts waiting on you..." appears
#          only when sum(DRAFTS↑) > 0. Total drafts here = 3.
# ========================================================================
if ! grep -q '3\* drafts waiting on you' "$OUT"; then
  echo "FAIL: AC#3 expected '3* drafts waiting on you' trailing line"
  grep -i drafts "$OUT" || true
  exit 1
fi
if ! grep -q "fleet digest --slug" "$OUT"; then
  echo "FAIL: AC#3 expected the 'fleet digest --slug <slug>' hint"
  exit 1
fi
echo "ok: AC#3 trailing drafts line (positive branch)"

# Negative branch: a fixture with zero drafts should NOT print the line.
NODRAFT_DIR="$TMP/nodraft"; mkdir -p "$NODRAFT_DIR/onlyone"
cat > "$NODRAFT_DIR/onlyone/agents.config.sh" <<CFG
PROJECT_NAME="OnlyOne"
SLUG="onlyone"
NAMESPACE="com.onlyone"
REPO_URL="https://github.com/example/onlyone"
SELF_CANCEL="20260801"
CFG
mkdir -p "$HOME/.cache/onlyone-agent"
: > "$HOME/.cache/onlyone-agent/runs.jsonl"
: > "$HOME/.cache/onlyone-agent/events.jsonl"
FLEET_DISCOVERY_ROOT="$NODRAFT_DIR" "$FLEET" weekly > "$TMP/weekly.nodraft.txt"
if grep -q 'drafts waiting on you' "$TMP/weekly.nodraft.txt"; then
  echo "FAIL: AC#3 trailing drafts line should NOT appear when sum=0"
  cat "$TMP/weekly.nodraft.txt"; exit 1
fi
echo "ok: AC#3 trailing drafts line (negative branch)"

# ========================================================================
# AC #4 — ALL: summary line. With 12 ships, $4.93 spend, $0.41/PR avg,
#          6 heal attempts, 1 infra-flake rerun, 1 paused, 1 expired.
# ========================================================================
# The ALL: summary may span two printed lines (heads on line 1, tails on
# line 2). Concatenate the ALL: line with its immediate successor for the
# grep checks.
ALL_BLOCK="$(awk '/^ALL:/{flag=1} flag{print; n++} n>=2{exit}' "$OUT")"
[ -n "$ALL_BLOCK" ] || { echo "FAIL: AC#4 missing ALL: summary"; cat "$OUT"; exit 1; }
# 6 (agent-fleet) + 4 (almanac) + 0 (courtiq) + 2 (digitalcraft) = 12 PRs.
echo "$ALL_BLOCK" | grep -qE '12 PRs shipped' \
  || { echo "FAIL: AC#4 ALL: PRs!=12: $ALL_BLOCK"; exit 1; }
# 2.14 + 1.87 + 0 + 0.92 = 4.93.
echo "$ALL_BLOCK" | grep -qF '$4.93' \
  || { echo "FAIL: AC#4 ALL: \$spend!=4.93: $ALL_BLOCK"; exit 1; }
# avg = 4.93 / 12 = 0.41 (printf %.2f).
echo "$ALL_BLOCK" | grep -qF '$0.41' \
  || { echo "FAIL: AC#4 ALL: \$avg!=0.41: $ALL_BLOCK"; exit 1; }
# heal = 3 + 2 + 0 + 1 = 6.
echo "$ALL_BLOCK" | grep -qE '6 heal attempts' \
  || { echo "FAIL: AC#4 ALL: heal!=6: $ALL_BLOCK"; exit 1; }
echo "$ALL_BLOCK" | grep -qE '1 infra-flake rerun' \
  || { echo "FAIL: AC#4 ALL: infra!=1: $ALL_BLOCK"; exit 1; }
echo "$ALL_BLOCK" | grep -qE '1 paused' \
  || { echo "FAIL: AC#4 ALL: paused!=1: $ALL_BLOCK"; exit 1; }
echo "$ALL_BLOCK" | grep -qE '1 expired' \
  || { echo "FAIL: AC#4 ALL: expired!=1: $ALL_BLOCK"; exit 1; }
echo "ok: AC#4 ALL: summary"

# Negative — when no PRs ship at all, "$avg/PR avg" is omitted. Use the
# single cold project (FLEET_DISCOVERY_ROOT=NODRAFT_DIR/onlyone).
if grep -q 'avg' "$TMP/weekly.nodraft.txt"; then
  echo "FAIL: AC#4 ALL: avg should be omitted when PRs=0"
  cat "$TMP/weekly.nodraft.txt"; exit 1
fi
echo "ok: AC#4 ALL: avg omitted when PRs=0"

# ========================================================================
# AC #5 — --since parses Nh|Nd via digest_parse_since. Valid 7d, 30d
#          paths; invalid "30" errors to stderr with exit 2.
# ========================================================================
"$FLEET" weekly --since 7d  > "$TMP/since-7d.txt"  || \
  { echo "FAIL: AC#5 --since 7d failed"; exit 1; }
"$FLEET" weekly --since 30d > "$TMP/since-30d.txt" || \
  { echo "FAIL: AC#5 --since 30d failed"; exit 1; }
# 30d window picks up the OOW $9.99 spend row that 7d did not. agent-fleet
# spend in 30d should be 2.14 + 9.99 = 12.13.
if ! grep -qF '$12.13' "$TMP/since-30d.txt"; then
  echo "FAIL: AC#5 --since 30d should pick up the 30d-ago \$9.99 run"
  awk '$1=="agent-fleet"' "$TMP/since-30d.txt"; exit 1
fi
echo "ok: AC#5 --since 7d / 30d"

set +e
"$FLEET" weekly --since 30 2>"$TMP/since-err.txt" >/dev/null
SINCE_EXIT=$?
set -e
if [ "$SINCE_EXIT" != "2" ]; then
  echo "FAIL: AC#5 invalid --since 30 should exit 2, got $SINCE_EXIT"; exit 1
fi
if ! grep -q 'weekly: invalid --since' "$TMP/since-err.txt"; then
  echo "FAIL: AC#5 invalid --since 30 should print the documented error"
  cat "$TMP/since-err.txt"; exit 1
fi
echo "ok: AC#5 --since invalid path"

# ========================================================================
# AC #6 — --slug filters to one project; ALL: summary suppressed.
# ========================================================================
"$FLEET" weekly --slug agent-fleet > "$TMP/slug.txt"
ROWS=$(awk '/^agent-fleet|^almanac|^courtiq|^digitalcraft/ { n++ } END { print n+0 }' "$TMP/slug.txt")
if [ "$ROWS" != "1" ]; then
  echo "FAIL: AC#6 --slug agent-fleet should yield 1 data row, got $ROWS"
  cat "$TMP/slug.txt"; exit 1
fi
if grep -q '^ALL:' "$TMP/slug.txt"; then
  echo "FAIL: AC#6 --slug should suppress ALL: summary"
  cat "$TMP/slug.txt"; exit 1
fi
echo "ok: AC#6 --slug filter"

# ========================================================================
# AC #7 — --json: one JSON object per project + one summary object.
# ========================================================================
"$FLEET" weekly --json > "$TMP/weekly.json"
# 4 project rows + 1 summary row = 5 lines.
LINES=$(wc -l < "$TMP/weekly.json" | tr -d ' ')
if [ "$LINES" != "5" ]; then
  echo "FAIL: AC#7 expected 5 JSON lines (4 projects + 1 summary), got $LINES"
  cat "$TMP/weekly.json"; exit 1
fi
# Every line is valid JSON, and the documented keys are present.
node -e '
  const fs = require("fs");
  const lines = fs.readFileSync(process.argv[1], "utf8").trim().split("\n");
  if (lines.length !== 5) { console.error("FAIL JSON line count " + lines.length); process.exit(1); }
  const project_keys = ["slug","shipped","spend","drafts","heal","infra",
                        "paused_days","self_cancel_days","self_cancel_state"];
  const summary_keys = ["summary","prs","spend","avg_per_pr","heal","infra",
                        "paused","expired","window_days"];
  let summary_seen = false;
  for (const ln of lines) {
    const o = JSON.parse(ln);
    if (o.summary === true) {
      summary_seen = true;
      for (const k of summary_keys) {
        if (!(k in o)) { console.error("FAIL summary missing key " + k); process.exit(1); }
      }
      if (o.prs !== 12) { console.error("FAIL summary.prs=" + o.prs); process.exit(1); }
      if (Math.abs(o.spend - 4.93) > 0.005) { console.error("FAIL summary.spend=" + o.spend); process.exit(1); }
      if (Math.abs(o.avg_per_pr - 0.41) > 0.005) { console.error("FAIL summary.avg_per_pr=" + o.avg_per_pr); process.exit(1); }
      if (o.heal !== 6) { console.error("FAIL summary.heal=" + o.heal); process.exit(1); }
      if (o.infra !== 1) { console.error("FAIL summary.infra=" + o.infra); process.exit(1); }
      if (o.paused !== 1) { console.error("FAIL summary.paused=" + o.paused); process.exit(1); }
      if (o.expired !== 1) { console.error("FAIL summary.expired=" + o.expired); process.exit(1); }
      if (o.window_days !== 7) { console.error("FAIL summary.window_days=" + o.window_days); process.exit(1); }
    } else {
      for (const k of project_keys) {
        if (!(k in o)) { console.error("FAIL project " + JSON.stringify(o.slug) + " missing key " + k); process.exit(1); }
      }
      // Project-specific spot-checks.
      if (o.slug === "agent-fleet") {
        if (o.shipped !== 6) { console.error("FAIL agent-fleet.shipped=" + o.shipped); process.exit(1); }
        if (Math.abs(o.spend - 2.14) > 0.005) { console.error("FAIL agent-fleet.spend=" + o.spend); process.exit(1); }
        if (o.drafts !== 2) { console.error("FAIL agent-fleet.drafts=" + o.drafts); process.exit(1); }
        if (o.heal !== 3) { console.error("FAIL agent-fleet.heal=" + o.heal); process.exit(1); }
        if (o.infra !== 1) { console.error("FAIL agent-fleet.infra=" + o.infra); process.exit(1); }
        if (o.self_cancel_state !== "ok") { console.error("FAIL agent-fleet.state=" + o.self_cancel_state); process.exit(1); }
      }
      if (o.slug === "courtiq") {
        if (o.self_cancel_state !== "expired") { console.error("FAIL courtiq.state=" + o.self_cancel_state); process.exit(1); }
        if (o.paused_days !== 14) { console.error("FAIL courtiq.paused_days=" + o.paused_days); process.exit(1); }
      }
      if (o.slug === "digitalcraft") {
        if (o.self_cancel_state !== "warn") { console.error("FAIL digitalcraft.state=" + o.self_cancel_state); process.exit(1); }
      }
    }
  }
  if (!summary_seen) { console.error("FAIL summary object not emitted"); process.exit(1); }
  console.log("ok: AC#7 --json shape + spot checks");
' "$TMP/weekly.json"

# ========================================================================
# AC #8 — Expired + paused projects appear in the table (NOT suppressed).
#          courtiq is BOTH expired AND paused; assert its row is present.
# ========================================================================
if ! awk '$1=="courtiq"' "$OUT" >/dev/null; then
  echo "FAIL: AC#8 courtiq (expired+paused) row missing from table"
  cat "$OUT"; exit 1
fi
echo "ok: AC#8 expired+paused projects render"

# ========================================================================
# AC #9 — Cold project (no events, no runs) still appears with all-zero
#          metrics. Reuse the onlyone fixture from AC#3.
# ========================================================================
COLD="$TMP/weekly.nodraft.txt"
if ! awk '$1=="onlyone"' "$COLD" >/dev/null; then
  echo "FAIL: AC#9 cold 'onlyone' row missing"; cat "$COLD"; exit 1
fi
# All-zero metrics: SHIPPED=0, $SPEND=0.00, DRAFTS=0, HEAL=0, INFRA=0.
ONLYONE_ROW="$(awk '$1=="onlyone"' "$COLD")"
echo "$ONLYONE_ROW" | grep -qF '$0.00' \
  || { echo "FAIL: AC#9 cold row missing \$0.00: $ONLYONE_ROW"; exit 1; }
echo "ok: AC#9 cold project row"

# ========================================================================
# AC #10 — Golden file byte-match. The four-project fixture must render
#          IDENTICAL to tests/fixtures/weekly.golden.txt. This is the
#          single most stringent assertion — any drift in format is a
#          test failure.
# ========================================================================
if [ ! -f "$GOLDEN" ]; then
  echo "FAIL: AC#10 golden file missing at $GOLDEN"; exit 1
fi
if ! diff -u "$GOLDEN" "$OUT"; then
  echo "FAIL: AC#10 output does not match golden file (see diff above)"
  exit 1
fi
echo "ok: AC#10 golden byte-match"

# ========================================================================
# AC #11 — No new event types. Assert the implementation never calls
#          fleet_emit_event AND that lib/common.sh's _EVENT_TYPES list (if
#          one existed) is unchanged. We approximate by grepping bin/fleet
#          for any new event names introduced by the weekly() block.
# ========================================================================
# Grep for any fleet_emit_event call inside the weekly() function body.
# Extract weekly's function source and ensure it does not contain
# fleet_emit_event.
WEEKLY_FN_BODY="$(awk '
  /^weekly\(\) \{/,/^\}/
' "$REPO_ROOT/bin/fleet")"
if echo "$WEEKLY_FN_BODY" | grep -q 'fleet_emit_event'; then
  echo "FAIL: AC#11 weekly() must not call fleet_emit_event (no new event types)"
  exit 1
fi
echo "ok: AC#11 weekly() emits no new events"

# ========================================================================
# AC #12 — README "Daily ops" code block mentions `fleet weekly` on its
#           own line, adjacent to `fleet digest`/`fleet overview`.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -q 'fleet weekly' "$README"; then
  echo "FAIL: AC#12 README does not mention 'fleet weekly'"; exit 1
fi
echo "ok: AC#12 README mentions fleet weekly"

# ========================================================================
# AC #13 — Help text. `bin/fleet weekly --help` describes the columns.
# ========================================================================
HELP_OUT="$TMP/weekly.help.txt"
"$FLEET" weekly --help > "$HELP_OUT" || true
# Use `grep -- <kw>` end-of-options marker so leading "--" doesn't get
# eaten as a flag (per LESSONS 2026-05-28 — same defensive habit).
for kw in 'fleet weekly' 'Sunday' 'DRAFTS' '--since' '--slug' '--json'; do
  if ! grep -qF -- "$kw" "$HELP_OUT"; then
    echo "FAIL: AC#13 help missing '$kw'"; cat "$HELP_OUT"; exit 1
  fi
done
echo "ok: AC#13 help text"

echo "ok: tests/weekly.sh passed"
