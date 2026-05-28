#!/bin/bash
# tests/overview.sh — bin/fleet overview end-to-end test against a tmpdir fixture.
#
# Ticket 0019. Builds three synthetic projects under a temp FLEET_DISCOVERY_ROOT
# (alpha = OK, bravo = PAUSED via stubbed `launchctl print-disabled`,
# charlie = OVER-BUDGET via a seeded runs.jsonl exceeding MAX_DAILY_USD), then
# asserts every acceptance-criteria box. One assertion block per checkbox;
# comments name which AC each block covers.
#
# Self-contained: stubs $HOME, points FLEET_DISCOVERY_ROOT at the fixture,
# stubs `launchctl` and `gh` so the test never depends on the host's real
# state. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMP="$(mktemp -d -t fleet-overview-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Isolate from any real ~/.cache state on the host.
export HOME="$TMP/home"
mkdir -p "$HOME"

# --- fixture roots --------------------------------------------------------
FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE"

# Time helpers. We pin "now" so the SHIP-age column is deterministic even
# when the test runs near a minute boundary.
NOW_EPOCH=$(date -u +%s)
iso_at() {  # $1 = epoch seconds → "YYYY-MM-DDTHH:MM:SSZ"
  date -u -r "$1" +%FT%TZ 2>/dev/null || date -u -d "@$1" +%FT%TZ
}
THREE_MIN_AGO=$(( NOW_EPOCH - 3 * 60 ))
ONE_HR_AGO=$(( NOW_EPOCH - 60 * 60 ))
TWO_HR_AGO=$(( NOW_EPOCH - 2 * 3600 ))
SIX_HR_AGO=$(( NOW_EPOCH - 6 * 3600 ))

# --- fixture A: alpha — OK, in-flight PR GREEN, ship 3m ago, REVIEW ok ----
mkdir -p "$FIXTURE/alpha"
cat > "$FIXTURE/alpha/agents.config.sh" <<CFG
PROJECT_NAME="Alpha"
SLUG="alpha"
NAMESPACE="com.alpha"
REPO_URL="https://github.com/example/alpha"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/alpha-agent/logs"
# Newest ship log → 3 minutes ago. Use `touch -t` to set mtime.
SHIP_LOG="$HOME/.cache/alpha-agent/logs/ship-20260528-100000.log"
echo "ship" > "$SHIP_LOG"
# `touch -t` interprets in LOCAL time on macOS. Use `date -r` WITHOUT -u so
# the stamp matches the local clock, and the resulting mtime epoch will
# equal THREE_MIN_AGO (within seconds).
TOUCH_STAMP="$(date -r "$THREE_MIN_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$THREE_MIN_AGO" +%Y%m%d%H%M.%S)"
touch -t "$TOUCH_STAMP" "$SHIP_LOG"
# Seed one $0.42 run today (UTC).
TODAY_PREFIX="$(date -u +%Y-%m-%d)"
cat > "$HOME/.cache/alpha-agent/runs.jsonl" <<JSONL
{"slug":"alpha","phase":"ship","ts_start":"${TODAY_PREFIX}T01:00:00Z","ts_end":"${TODAY_PREFIX}T01:00:30Z","exit":0,"total_cost_usd":0.42}
JSONL
# Events: just one pr_opened — for the column we care about, the IN-FLIGHT
# column is sourced from gh, not events.jsonl.
cat > "$HOME/.cache/alpha-agent/events.jsonl" <<JSONL
{"ts":"$(iso_at "$ONE_HR_AGO")","slug":"alpha","phase":"ship","type":"pr_opened","number":"187","branch":"feat/0019-x"}
JSONL

# --- fixture B: bravo — PAUSED via stubbed launchctl, no in-flight PR -----
mkdir -p "$FIXTURE/bravo"
cat > "$FIXTURE/bravo/agents.config.sh" <<CFG
PROJECT_NAME="Bravo"
SLUG="bravo"
NAMESPACE="com.bravo"
REPO_URL="https://github.com/example/bravo"
SELF_CANCEL="20990101"
CFG
mkdir -p "$HOME/.cache/bravo-agent/logs"
BRAVO_SHIP="$HOME/.cache/bravo-agent/logs/ship-20260528-070000.log"
echo "ship" > "$BRAVO_SHIP"
BRAVO_STAMP="$(date -r "$SIX_HR_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$SIX_HR_AGO" +%Y%m%d%H%M.%S)"
touch -t "$BRAVO_STAMP" "$BRAVO_SHIP"
: > "$HOME/.cache/bravo-agent/runs.jsonl"
: > "$HOME/.cache/bravo-agent/events.jsonl"

# --- fixture C: charlie — OVER-BUDGET (today's spend ≥ MAX_DAILY_USD) -----
mkdir -p "$FIXTURE/charlie"
cat > "$FIXTURE/charlie/agents.config.sh" <<CFG
PROJECT_NAME="Charlie"
SLUG="charlie"
NAMESPACE="com.charlie"
REPO_URL="https://github.com/example/charlie"
SELF_CANCEL="20990101"
MAX_DAILY_USD=2
CFG
mkdir -p "$HOME/.cache/charlie-agent/logs"
CHARLIE_SHIP="$HOME/.cache/charlie-agent/logs/ship-20260528-080000.log"
echo "ship" > "$CHARLIE_SHIP"
CHARLIE_STAMP="$(date -r "$TWO_HR_AGO" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$TWO_HR_AGO" +%Y%m%d%H%M.%S)"
touch -t "$CHARLIE_STAMP" "$CHARLIE_SHIP"
# Seed a $3.50 spend today (≥ MAX_DAILY_USD=2 → OVER-BUDGET).
cat > "$HOME/.cache/charlie-agent/runs.jsonl" <<JSONL
{"slug":"charlie","phase":"ship","ts_start":"${TODAY_PREFIX}T01:00:00Z","ts_end":"${TODAY_PREFIX}T01:00:30Z","exit":0,"total_cost_usd":3.50}
JSONL
: > "$HOME/.cache/charlie-agent/events.jsonl"

# --- stubs ----------------------------------------------------------------
BIN_STUB="$TMP/bin"
mkdir -p "$BIN_STUB"

# launchctl stub: only bravo's agent-ship is listed as disabled, so only it
# reports PAUSED. We use the `print-disabled gui/$UID` form because
# `digest_state` (which overview reuses) calls that exact subcommand.
cat > "$BIN_STUB/launchctl" <<'STUB'
#!/bin/bash
# `launchctl print-disabled gui/$UID` — emit one disabled entry for bravo.
# `launchctl print <label>` — always succeed.
if [ "${1:-}" = "print-disabled" ]; then
  cat <<DIS
{
  "com.bravo.agent-ship" => true
  "com.alpha.agent-ship" => false
  "com.charlie.agent-ship" => false
}
DIS
  exit 0
fi
exit 0
STUB
chmod +x "$BIN_STUB/launchctl"

# gh stub: emits one fake open agent PR for alpha (#187 GREEN) and none for
# bravo/charlie. The shape mirrors `gh pr list --json number,mergeStateStatus,
# statusCheckRollup,headRefName,updatedAt`. Search filter and other flags are
# accepted positionally. For bravo/charlie, return [].
cat > "$BIN_STUB/gh" <<'STUB'
#!/bin/bash
# Detect which repo we're being asked about by walking the argv.
repo=""
i=1
while [ $i -le $# ]; do
  case "${!i}" in
    --repo) i=$((i+1)); repo="${!i}" ;;
  esac
  i=$((i+1))
done
# Determine subcommand path: `gh pr list ...` is what overview calls.
sub1="${1:-}"; sub2="${2:-}"
case "${sub1}/${sub2}" in
  pr/list)
    case "$repo" in
      */alpha)
        cat <<JSON
[{"number":187,"mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"SUCCESS"}],"headRefName":"feat/0019-overview","updatedAt":"2026-05-28T10:00:00Z"}]
JSON
        exit 0
        ;;
      *)
        echo "[]"; exit 0 ;;
    esac
    ;;
  pr/view)
    echo '{}' ; exit 0 ;;
  auth/status)
    exit 0 ;;
  *)
    echo "[]"; exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/gh"

export PATH="$BIN_STUB:$PATH"
export FLEET_DISCOVERY_ROOT="$FIXTURE"

FLEET="$REPO_ROOT/bin/fleet"

# Reset the fake-now hook so all overview age math is deterministic for the
# tests. The implementation honours FLEET_OVERVIEW_FAKE_NOW (mirrors
# FLEET_TAIL_FAKE_NOW from ticket 0015) — we pin it to NOW_EPOCH.
export FLEET_OVERVIEW_FAKE_NOW="$NOW_EPOCH"

# ========================================================================
# AC #1 — `bin/fleet overview` prints header + one row per project in
#         slug-alpha order. Exact columns: PROJECT, SHIP, REVIEW, SENDBK,
#         $TODAY, IN-FLIGHT, STATE.
# ========================================================================
OUT="$TMP/overview.txt"
set +e
"$FLEET" overview > "$OUT"
EXIT=$?
set -e

# Header line: the seven column names appear in order.
if ! head -1 "$OUT" | grep -q 'PROJECT'; then
  echo "FAIL: AC#1 header missing PROJECT"; cat "$OUT"; exit 1
fi
for col in PROJECT SHIP REVIEW SENDBK '$TODAY' IN-FLIGHT STATE; do
  if ! head -1 "$OUT" | grep -qF "$col"; then
    echo "FAIL: AC#1 header missing column $col"; head -1 "$OUT"; exit 1
  fi
done

# Slug-alpha order: alpha < bravo < charlie. Skip the header (line 1).
if ! awk 'NR==2 && $1=="alpha" { ok1=1 }
          NR==3 && $1=="bravo" { ok2=1 }
          NR==4 && $1=="charlie" { ok3=1 }
          END { exit (ok1 && ok2 && ok3) ? 0 : 1 }' "$OUT"; then
  echo "FAIL: AC#1 row order not slug-alpha"; cat "$OUT"; exit 1
fi
echo "ok: AC#1 header + slug-alpha row order"

# ========================================================================
# AC #2 — STATE column derivation honours the priority order
#         EXPIRED > PAUSED > OVER-BUDGET > STUCK > HEAL > OK.
#         Fixture: alpha=OK, bravo=PAUSED (launchctl disabled),
#         charlie=OVER-BUDGET (today's $3.50 >= MAX_DAILY_USD=2).
# ========================================================================
if ! awk '$1=="alpha"   && $NF=="OK"           { f=1 } END { exit f?0:1 }' "$OUT"; then
  echo "FAIL: AC#2 alpha STATE should be OK"; cat "$OUT"; exit 1
fi
if ! awk '$1=="bravo"   && $NF=="PAUSED"       { f=1 } END { exit f?0:1 }' "$OUT"; then
  echo "FAIL: AC#2 bravo STATE should be PAUSED"; cat "$OUT"; exit 1
fi
if ! awk '$1=="charlie" && $NF=="OVER-BUDGET"  { f=1 } END { exit f?0:1 }' "$OUT"; then
  echo "FAIL: AC#2 charlie STATE should be OVER-BUDGET"; cat "$OUT"; exit 1
fi
echo "ok: AC#2 STATE derivation"

# ========================================================================
# AC #3 — discovery scans the same two roots as fleet doctor/digest,
#         deduped by SLUG, FLEET_DISCOVERY_ROOT override honoured. The
#         fixture above only populates FLEET_DISCOVERY_ROOT; nothing under
#         ~/.local/share/agent-fleet/projects. AC#3 verifies the override
#         is the one being read (we never see ~/Desktop/projects rows).
# ========================================================================
# A side-effect check: with FLEET_DISCOVERY_ROOT=$FIXTURE we see exactly
# three data rows.
DATA_ROWS=$(awk 'NR>1 && NF>0' "$OUT" | wc -l | tr -d ' ')
if [ "$DATA_ROWS" != "3" ]; then
  echo "FAIL: AC#3 expected 3 data rows under FLEET_DISCOVERY_ROOT, got $DATA_ROWS"
  cat "$OUT"; exit 1
fi
echo "ok: AC#3 discovery honours FLEET_DISCOVERY_ROOT"

# ========================================================================
# AC #4 — `bin/fleet overview --slug NAME` restricts to one project.
# ========================================================================
SLUG_OUT="$TMP/overview.slug.txt"
set +e
"$FLEET" overview --slug alpha > "$SLUG_OUT"
SLUG_EXIT=$?
set -e
DATA_LINES=$(awk 'NR>1 && NF>0' "$SLUG_OUT" | wc -l | tr -d ' ')
if [ "$DATA_LINES" != "1" ]; then
  echo "FAIL: AC#4 --slug alpha should show 1 data row, got $DATA_LINES"
  cat "$SLUG_OUT"; exit 1
fi
if ! awk '$1=="alpha"' "$SLUG_OUT" >/dev/null; then
  echo "FAIL: AC#4 --slug alpha row missing alpha"; cat "$SLUG_OUT"; exit 1
fi
# alpha alone is OK → exit 0.
if [ "$SLUG_EXIT" != "0" ]; then
  echo "FAIL: AC#4 --slug alpha exit code = $SLUG_EXIT (want 0)"; exit 1
fi
echo "ok: AC#4 --slug filter"

# ========================================================================
# AC #5 — --json prints a JSON array of objects with the documented keys.
# ========================================================================
JSON_OUT="$TMP/overview.json"
set +e
"$FLEET" overview --json > "$JSON_OUT"
set -e
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!Array.isArray(arr)) {
    console.error("FAIL: AC#5 --json top-level should be an array");
    console.error(JSON.stringify(arr));
    process.exit(1);
  }
  const required = ["slug", "ship", "review", "sendbk", "spend_today_usd", "inflight", "state"];
  for (const row of arr) {
    for (const k of required) {
      if (!(k in row)) {
        console.error("FAIL: AC#5 row " + JSON.stringify(row.slug) + " missing key " + k);
        process.exit(1);
      }
    }
    // Sub-shape: state.code + state.reason; inflight.number + inflight.state;
    // review.last_verdict; ship.last_run_epoch.
    if (typeof row.state !== "object" || typeof row.state.code !== "string") {
      console.error("FAIL: AC#5 row " + row.slug + " state.code not a string"); process.exit(1);
    }
    if (typeof row.inflight !== "object") {
      console.error("FAIL: AC#5 row " + row.slug + " inflight not an object"); process.exit(1);
    }
    if (typeof row.review !== "object") {
      console.error("FAIL: AC#5 row " + row.slug + " review not an object"); process.exit(1);
    }
    if (typeof row.ship !== "object") {
      console.error("FAIL: AC#5 row " + row.slug + " ship not an object"); process.exit(1);
    }
  }
  console.log("ok: AC#5 --json shape");
' "$JSON_OUT"

# ========================================================================
# AC #6 — exit 0 when no project is EXPIRED/OVER-BUDGET/STUCK; exit 1
#         otherwise. The full fixture has charlie=OVER-BUDGET → expect 1.
# ========================================================================
if [ "$EXIT" != "1" ]; then
  echo "FAIL: AC#6 fixture has OVER-BUDGET → expect exit 1, got $EXIT"
  cat "$OUT"; exit 1
fi
# alpha alone is OK → exit 0 (already asserted in AC#4).
# bravo alone is PAUSED (not red) → exit 0.
PAUSED_OUT="$TMP/overview.bravo.txt"
set +e
"$FLEET" overview --slug bravo > "$PAUSED_OUT"
PAUSED_EXIT=$?
set -e
if [ "$PAUSED_EXIT" != "0" ]; then
  echo "FAIL: AC#6 PAUSED alone should exit 0, got $PAUSED_EXIT"
  cat "$PAUSED_OUT"; exit 1
fi
echo "ok: AC#6 exit code"

# ========================================================================
# AC #7 — when gh is unauthenticated / offline, IN-FLIGHT reads "—" (not
#         "error") and the row still renders the local-only columns.
# ========================================================================
# Replace the gh stub with one that exits 4 (gh's "no auth" code) for all
# subcommands. The shellcheck override pattern is the same the ticket calls
# out — we simulate offline gh without removing the binary from PATH.
cat > "$BIN_STUB/gh" <<'STUB'
#!/bin/bash
# Offline / unauthenticated — every call exits 4 with an error.
echo "error: not authenticated" >&2
exit 4
STUB
chmod +x "$BIN_STUB/gh"

OFFLINE_OUT="$TMP/overview.offline.txt"
set +e
"$FLEET" overview > "$OFFLINE_OUT"
set -e
# Header row still prints.
if ! head -1 "$OFFLINE_OUT" | grep -q 'PROJECT'; then
  echo "FAIL: AC#7 header missing when gh is offline"; cat "$OFFLINE_OUT"; exit 1
fi
# alpha now has IN-FLIGHT="—" (em dash).
ALPHA_OFFLINE="$(awk '$1=="alpha"' "$OFFLINE_OUT")"
if ! echo "$ALPHA_OFFLINE" | grep -q '—'; then
  echo "FAIL: AC#7 alpha offline row should have em-dash in IN-FLIGHT"
  echo "  $ALPHA_OFFLINE"; exit 1
fi
# Local-only columns still rendered: SHIP age, $TODAY spend.
if ! echo "$ALPHA_OFFLINE" | grep -qE 'm ago|h ago'; then
  echo "FAIL: AC#7 alpha SHIP column missing in offline mode"
  echo "  $ALPHA_OFFLINE"; exit 1
fi
if ! echo "$ALPHA_OFFLINE" | grep -qE '\$0\.42'; then
  echo "FAIL: AC#7 alpha \$TODAY column missing in offline mode"
  echo "  $ALPHA_OFFLINE"; exit 1
fi
echo "ok: AC#7 offline gh degrades gracefully"

# Restore the original gh stub for AC#8 below.
cat > "$BIN_STUB/gh" <<'STUB'
#!/bin/bash
repo=""
i=1
while [ $i -le $# ]; do
  case "${!i}" in
    --repo) i=$((i+1)); repo="${!i}" ;;
  esac
  i=$((i+1))
done
sub1="${1:-}"; sub2="${2:-}"
case "${sub1}/${sub2}" in
  pr/list)
    case "$repo" in
      */alpha)
        cat <<JSON
[{"number":187,"mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"shellcheck","conclusion":"SUCCESS"},{"name":"validate","conclusion":"SUCCESS"}],"headRefName":"feat/0019-overview","updatedAt":"2026-05-28T10:00:00Z"}]
JSON
        exit 0
        ;;
      *) echo "[]"; exit 0 ;;
    esac
    ;;
  *) echo "[]"; exit 0 ;;
esac
STUB
chmod +x "$BIN_STUB/gh"

# ========================================================================
# AC #8 — byte-for-byte JSON: given the three-project fixture, --json
#         emits an array whose alpha/bravo/charlie objects carry the
#         exact expected state codes + structured sub-fields.
# ========================================================================
JSON2="$TMP/overview.exact.json"
set +e
"$FLEET" overview --json > "$JSON2"
set -e
node -e '
  const fs = require("fs");
  const arr = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (arr.length !== 3) {
    console.error("FAIL: AC#8 expected 3 rows, got " + arr.length);
    console.error(JSON.stringify(arr, null, 2));
    process.exit(1);
  }
  const slugs = arr.map(r => r.slug);
  if (JSON.stringify(slugs) !== JSON.stringify(["alpha", "bravo", "charlie"])) {
    console.error("FAIL: AC#8 slug order " + JSON.stringify(slugs));
    process.exit(1);
  }
  const a = arr.find(r => r.slug === "alpha");
  const b = arr.find(r => r.slug === "bravo");
  const c = arr.find(r => r.slug === "charlie");
  if (a.state.code !== "OK")          { console.error("FAIL: alpha.state.code=" + a.state.code); process.exit(1); }
  if (b.state.code !== "PAUSED")      { console.error("FAIL: bravo.state.code=" + b.state.code); process.exit(1); }
  if (c.state.code !== "OVER-BUDGET") { console.error("FAIL: charlie.state.code=" + c.state.code); process.exit(1); }
  if (a.inflight.number !== 187) { console.error("FAIL: alpha.inflight.number=" + a.inflight.number); process.exit(1); }
  if (b.inflight.number !== null) { console.error("FAIL: bravo.inflight.number=" + b.inflight.number); process.exit(1); }
  if (Math.abs(c.spend_today_usd - 3.5) > 0.001) {
    console.error("FAIL: charlie.spend_today_usd=" + c.spend_today_usd); process.exit(1);
  }
  if (typeof a.ship.last_run_epoch !== "number" || a.ship.last_run_epoch <= 0) {
    console.error("FAIL: alpha.ship.last_run_epoch=" + a.ship.last_run_epoch); process.exit(1);
  }
  console.log("ok: AC#8 exact JSON shape");
' "$JSON2"

# ========================================================================
# AC #9 — README.md "Daily ops" section names `fleet overview` between
#         `fleet doctor` and `fleet tail`.
# ========================================================================
README="$REPO_ROOT/README.md"
if ! grep -q 'fleet overview' "$README"; then
  echo "FAIL: AC#9 README does not mention 'fleet overview'"
  exit 1
fi
# Order check: the overview callout must appear AFTER the first doctor
# callout and BEFORE the first tail callout.
DOC_LINE=$(grep -n 'fleet doctor' "$README" | head -1 | cut -d: -f1)
OVR_LINE=$(grep -n 'fleet overview' "$README" | head -1 | cut -d: -f1)
TAIL_LINE=$(grep -n 'fleet tail' "$README" | head -1 | cut -d: -f1)
if [ -z "$DOC_LINE" ] || [ -z "$OVR_LINE" ] || [ -z "$TAIL_LINE" ]; then
  echo "FAIL: AC#9 could not locate all three callouts in README.md"
  exit 1
fi
if [ "$OVR_LINE" -le "$DOC_LINE" ] || [ "$OVR_LINE" -ge "$TAIL_LINE" ]; then
  echo "FAIL: AC#9 README order wrong: doctor=$DOC_LINE overview=$OVR_LINE tail=$TAIL_LINE"
  exit 1
fi
echo "ok: AC#9 README Daily ops mentions fleet overview between doctor and tail"

echo "ok: tests/overview.sh passed"
