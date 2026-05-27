#!/bin/bash
# tests/tail.sh — bin/fleet tail end-to-end test against tmpdir fixtures.
#
# Ticket 0015. One assertion block per acceptance-criteria checkbox in
# docs/backlog/0015-fleet-tail.md. Tests use mktemp -d fixtures with two
# synthetic projects and assert exact stdout via diff against expected
# fixtures. FLEET_TAIL_FAKE_NOW pins the formatter clock so the `--since`
# replay path is deterministic.
#
# Self-contained: stubs $HOME, points FLEET_DISCOVERY_ROOT at the fixture,
# never touches real ~/.cache state. Exits non-zero on any failure.

set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
FLEET="$REPO_ROOT/bin/fleet"

TMP="$(mktemp -d -t fleet-tail-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"

FIXTURE="$TMP/projects"
mkdir -p "$FIXTURE/alpha" "$FIXTURE/bravo"

cat > "$FIXTURE/alpha/agents.config.sh" <<'CFG'
SLUG="alpha"
PROJECT_NAME="Alpha"
NAMESPACE="com.alpha"
REPO_URL="https://github.com/example/alpha"
SELF_CANCEL="20990101"
CFG
cat > "$FIXTURE/bravo/agents.config.sh" <<'CFG'
SLUG="bravo"
PROJECT_NAME="Bravo"
NAMESPACE="com.bravo"
REPO_URL="https://github.com/example/bravo"
SELF_CANCEL="20990101"
CFG

export FLEET_DISCOVERY_ROOT="$FIXTURE"

ALPHA_EVENTS="$HOME/.cache/alpha-agent/events.jsonl"
BRAVO_EVENTS="$HOME/.cache/bravo-agent/events.jsonl"
mkdir -p "$(dirname "$ALPHA_EVENTS")" "$(dirname "$BRAVO_EVENTS")"

# Pin the formatter clock so `--since` math is deterministic. Choose a
# fixed "now" well in the past so the test never races UTC midnight.
FAKE_NOW="1748275200"  # 2025-05-26T16:00:00Z
export FLEET_TAIL_FAKE_NOW="$FAKE_NOW"

# Helper — write a single events.jsonl line. $1=file $2=ts(epoch)
# $3=slug $4=phase $5=type, rest are extra k=v pairs that become JSON
# string fields.
emit() {
  local file="$1" epoch="$2" slug="$3" phase="$4" type="$5"
  shift 5
  local ts
  ts="$(date -u -r "$epoch" +%FT%TZ 2>/dev/null || date -u -d "@$epoch" +%FT%TZ)"
  local line="{\"ts\":\"$ts\",\"slug\":\"$slug\",\"phase\":\"$phase\",\"type\":\"$type\""
  while [ $# -gt 0 ]; do
    local k="${1%%=*}" v="${1#*=}"
    line="$line,\"$k\":\"$v\""
    shift
  done
  line="$line}"
  echo "$line" >> "$file"
}

# Seed both projects with historical events spanning the `--since` window.
# - 10 minutes ago: alpha run_started (inside 5m? NO; inside 1h? YES)
# - 3 minutes ago: alpha pr_opened (inside 5m: YES)
# - 1 minute ago: bravo run_completed (inside 5m: YES)
TEN_MIN_AGO=$(( FAKE_NOW - 600 ))
THREE_MIN_AGO=$(( FAKE_NOW - 180 ))
ONE_MIN_AGO=$(( FAKE_NOW - 60 ))
emit "$ALPHA_EVENTS" "$TEN_MIN_AGO"   alpha ship run_started   pid=11
emit "$ALPHA_EVENTS" "$THREE_MIN_AGO" alpha ship pr_opened     number=42 branch=feat/0015
emit "$BRAVO_EVENTS" "$ONE_MIN_AGO"   bravo groom run_completed exit=0 duration_ms=12345

# Common helper: run `fleet tail` with args in background, capture stdout,
# wait a beat for the pre-roll, send SIGINT, wait for clean exit.
# $1 = output file; rest = fleet args.
run_tail() {
  local out="$1"; shift
  : > "$out"
  "$FLEET" tail "$@" > "$out" 2>&1 &
  local pid=$!
  # Give the formatter time to drain replay + start tail -F watchers.
  sleep 1
  echo "$pid"
}

# Stop a tail PID and wait for graceful exit. Uses SIGTERM because bash
# scripts launched in the background via `&` inherit SIG_IGN for SIGINT
# (POSIX behavior: "a signal set to ignored on entry remains ignored").
# In interactive use the operator's Ctrl-C delivers a real SIGINT to the
# foreground process and the same trap handler fires — AC#6 below also
# explicitly asserts that the SIGINT-and-SIGTERM trap entry exists in the
# tail() function body so this test-side detail does not silently let a
# real bug through.
stop_tail() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$pid" 2>/dev/null; then return 0; fi
    sleep 0.2
  done
  kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# ========================================================================
# AC #1 — `fleet tail` (no args) follows EVERY discovered project's
#         events.jsonl. Format: <HH:MM:SS>  <slug>/<phase>  <type>  <extras>
#         where <extras> is k=v for every JSON key beyond {ts,slug,phase,type}.
# ========================================================================
OUT="$TMP/out.all.txt"
PID=$(run_tail "$OUT" --since 1h)
# Append a fresh event to each project AFTER tail starts, so we exercise
# the live (tail -F) path on top of the replay path.
FIVE_S_AGO=$(( FAKE_NOW - 5 ))
emit "$ALPHA_EVENTS" "$FIVE_S_AGO" alpha ship run_completed exit=0 duration_ms=999
emit "$BRAVO_EVENTS" "$FIVE_S_AGO" bravo ship pr_opened     number=7 branch=feat/0099
sleep 1
stop_tail "$PID"

# Every line must match the documented format.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! echo "$line" | grep -qE '^[0-9]{2}:[0-9]{2}:[0-9]{2}  [a-z][a-z0-9_-]*/[a-z]+  [a-z_]+'; then
    echo "FAIL: AC#1 line does not match '<HH:MM:SS>  <slug>/<phase>  <type>':"
    echo "  $line"; cat "$OUT"; exit 1
  fi
done < "$OUT"

# Replay should include lines from BOTH projects.
if ! grep -q 'alpha/ship  pr_opened' "$OUT"; then
  echo "FAIL: AC#1 missing alpha pr_opened replay"; cat "$OUT"; exit 1
fi
if ! grep -q 'bravo/groom  run_completed' "$OUT"; then
  echo "FAIL: AC#1 missing bravo run_completed replay"; cat "$OUT"; exit 1
fi
# Extras must include k=v pairs for the extra JSON keys.
if ! grep -q 'pr_opened  number=42 branch=feat/0015' "$OUT"; then
  echo "FAIL: AC#1 extras formatting for alpha pr_opened wrong"
  cat "$OUT"; exit 1
fi
echo "ok: AC#1 multi-project follow + format"

# ========================================================================
# AC #2 — `fleet tail <slug>` restricts to one project. If events.jsonl
#         does not yet exist, prints "waiting for events.jsonl at <path>..."
#         and blocks until the file appears.
# ========================================================================
# Create a third project "delta" whose events.jsonl does NOT exist yet.
mkdir -p "$FIXTURE/delta"
cat > "$FIXTURE/delta/agents.config.sh" <<'CFG'
SLUG="delta"
PROJECT_NAME="Delta"
NAMESPACE="com.delta"
REPO_URL="https://github.com/example/delta"
SELF_CANCEL="20990101"
CFG
DELTA_EVENTS="$HOME/.cache/delta-agent/events.jsonl"
mkdir -p "$(dirname "$DELTA_EVENTS")"
# Guarantee the file does NOT exist at start.
rm -f "$DELTA_EVENTS"

OUT="$TMP/out.delta.txt"
PID=$(run_tail "$OUT" delta)
# After ≥1s we should see the wait message but no events yet.
if ! grep -q "waiting for events.jsonl at $DELTA_EVENTS" "$OUT"; then
  echo "FAIL: AC#2 expected wait message before file exists"
  cat "$OUT"; stop_tail "$PID"; exit 1
fi
# Now create the file with one event; the tailer must pick it up.
NOW_EPOCH=$(( FAKE_NOW - 1 ))
emit "$DELTA_EVENTS" "$NOW_EPOCH" delta ship run_started pid=99
sleep 2
stop_tail "$PID"
if ! grep -q 'delta/ship  run_started  pid=99' "$OUT"; then
  echo "FAIL: AC#2 delta event missed after file appeared"
  cat "$OUT"; exit 1
fi
echo "ok: AC#2 single-slug + wait-for-file"

# ========================================================================
# AC #3 — --since Ns|Nm|Nh|Nd replays events from the cutoff window first.
# ========================================================================
OUT="$TMP/out.since5m.txt"
PID=$(run_tail "$OUT" alpha --since 5m)
stop_tail "$PID"
# At FAKE_NOW, the alpha run_started is 10m ago → OUTSIDE the 5m window.
# The pr_opened is 3m ago → INSIDE.
if grep -q 'alpha/ship  run_started  pid=11' "$OUT"; then
  echo "FAIL: AC#3 --since 5m should EXCLUDE the 10m-old run_started"
  cat "$OUT"; exit 1
fi
if ! grep -q 'alpha/ship  pr_opened  number=42 branch=feat/0015' "$OUT"; then
  echo "FAIL: AC#3 --since 5m should INCLUDE the 3m-old pr_opened"
  cat "$OUT"; exit 1
fi
# Bad unit must error.
if "$FLEET" tail --since 5x alpha </dev/null >/dev/null 2>&1; then
  echo "FAIL: AC#3 --since 5x should fail (bad unit)"; exit 1
fi
echo "ok: AC#3 --since window"

# ========================================================================
# AC #4 — --json pipes raw JSON lines (events as they appear in events.jsonl).
# ========================================================================
OUT="$TMP/out.json.txt"
PID=$(run_tail "$OUT" alpha --json --since 1h)
stop_tail "$PID"
# Filter to lines that look like JSON; ignore any wait/status diagnostics.
JSON_LINES=$(grep -E '^\s*\{' "$OUT" || true)
if [ -z "$JSON_LINES" ]; then
  echo "FAIL: AC#4 --json produced no JSON lines"; cat "$OUT"; exit 1
fi
# Every JSON line must parse and carry the four required keys.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if ! node -e '
    const ev = JSON.parse(process.argv[1]);
    for (const k of ["ts","slug","phase","type"]) {
      if (!(k in ev)) { console.error("missing key " + k + " in " + process.argv[1]); process.exit(1); }
    }
  ' "$line"; then
    echo "FAIL: AC#4 --json line did not parse cleanly:"
    echo "  $line"; exit 1
  fi
done <<<"$JSON_LINES"
echo "ok: AC#4 --json raw lines"

# ========================================================================
# AC #5 — --type pr_opened,run_completed filters to a comma-separated list.
# ========================================================================
OUT="$TMP/out.type.txt"
PID=$(run_tail "$OUT" --type pr_opened,run_completed --since 1h)
stop_tail "$PID"
# run_started must NOT appear; pr_opened + run_completed must.
if grep -q ' run_started ' "$OUT"; then
  echo "FAIL: AC#5 --type filter let run_started through"
  cat "$OUT"; exit 1
fi
if ! grep -q ' pr_opened ' "$OUT"; then
  echo "FAIL: AC#5 --type filter dropped pr_opened (which IS in the list)"
  cat "$OUT"; exit 1
fi
if ! grep -q ' run_completed ' "$OUT"; then
  echo "FAIL: AC#5 --type filter dropped run_completed (which IS in the list)"
  cat "$OUT"; exit 1
fi
echo "ok: AC#5 --type filter"

# ========================================================================
# AC #6 — SIGINT/SIGTERM cleans up background tail -F PIDs (no orphans).
#         Two parts:
#         (a) source-level: bin/fleet's tail() body MUST install a trap
#             that handles INT (the real Ctrl-C case) AND TERM (what the
#             test driver below uses; see stop_tail() comment).
#         (b) runtime: send SIGTERM, then assert parent + every child PID
#             (tail -F watchers) are gone.
# ========================================================================
# (a) The trap must mention both signals so the real Ctrl-C path is wired.
if ! grep -qE 'trap[[:space:]]+[a-z_]+[[:space:]]+INT[[:space:]]+TERM' "$FLEET"; then
  echo "FAIL: AC#6 tail() must install 'trap <fn> INT TERM'"
  exit 1
fi
OUT="$TMP/out.sigint.txt"
PID=$(run_tail "$OUT" --since 1h)
# Collect the parent's descendant PIDs while it's alive.
CHILDREN="$(pgrep -P "$PID" 2>/dev/null | tr '\n' ' ' || true)"
stop_tail "$PID"
# (b) Parent must be gone.
if kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: AC#6 parent fleet-tail pid $PID still alive after SIGTERM"
  exit 1
fi
# Every child PID must also be gone.
for c in $CHILDREN; do
  if kill -0 "$c" 2>/dev/null; then
    echo "FAIL: AC#6 child pid $c (tail -F) leaked after SIGTERM"
    exit 1
  fi
done
echo "ok: AC#6 trap installed + cleanup of background PIDs"

# ========================================================================
# AC #7 — deterministic replay output via diff against an expected fixture.
#         Build an isolated mini-fixture with one project + a tiny seeded
#         events.jsonl, then diff the `--since 1h` replay output (no live
#         appends) against the expected text.
# ========================================================================
ISO_FIXTURE="$TMP/iso-projects"
mkdir -p "$ISO_FIXTURE/iso"
cat > "$ISO_FIXTURE/iso/agents.config.sh" <<'CFG'
SLUG="iso"
PROJECT_NAME="Iso"
NAMESPACE="com.iso"
REPO_URL="https://github.com/example/iso"
SELF_CANCEL="20990101"
CFG
ISO_EVENTS="$HOME/.cache/iso-agent/events.jsonl"
mkdir -p "$(dirname "$ISO_EVENTS")"
# Three events at fixed timestamps inside the 1h window.
emit "$ISO_EVENTS" "$(( FAKE_NOW - 300 ))" iso ship run_started   pid=1
emit "$ISO_EVENTS" "$(( FAKE_NOW - 200 ))" iso ship pr_opened     number=5 branch=feat/test
emit "$ISO_EVENTS" "$(( FAKE_NOW - 100 ))" iso ship run_completed exit=0 duration_ms=42

# Render the expected text using the same FAKE_NOW the formatter sees.
TS1=$(date -u -r $(( FAKE_NOW - 300 )) +%H:%M:%S 2>/dev/null || date -u -d "@$(( FAKE_NOW - 300 ))" +%H:%M:%S)
TS2=$(date -u -r $(( FAKE_NOW - 200 )) +%H:%M:%S 2>/dev/null || date -u -d "@$(( FAKE_NOW - 200 ))" +%H:%M:%S)
TS3=$(date -u -r $(( FAKE_NOW - 100 )) +%H:%M:%S 2>/dev/null || date -u -d "@$(( FAKE_NOW - 100 ))" +%H:%M:%S)
EXPECT="$TMP/iso.expected.txt"
{
  echo "$TS1  iso/ship  run_started  pid=1"
  echo "$TS2  iso/ship  pr_opened  number=5 branch=feat/test"
  echo "$TS3  iso/ship  run_completed  exit=0 duration_ms=42"
} > "$EXPECT"

OUT="$TMP/iso.actual.txt"
FLEET_DISCOVERY_ROOT="$ISO_FIXTURE" "$FLEET" tail iso --since 1h > "$OUT" 2>&1 &
ISO_PID=$!
sleep 1
stop_tail "$ISO_PID"

# Strip anything that isn't the formatted event lines (defensive — there
# shouldn't be any) and diff. The formatter emits replay events in file
# order; no sorting needed.
grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}  iso/' "$OUT" > "$TMP/iso.filtered.txt" || true
if ! diff -u "$EXPECT" "$TMP/iso.filtered.txt"; then
  echo "FAIL: AC#7 replay output differs from expected fixture"; exit 1
fi
echo "ok: AC#7 exact stdout via diff"

# ========================================================================
# AC #R (ticket 0016 cross-ticket regression) — `tail -F` must survive a
#       rotation of events.jsonl: we start `fleet tail iso --since 1h`,
#       move the live events.jsonl into events.jsonl.archive/<stamp>.jsonl
#       (simulating fleet_rotate_events), recreate an empty events.jsonl,
#       append a fresh event, and assert that the new event still shows
#       up in the tail's stdout. Capital-F `tail -F` follows by name, not
#       file descriptor, so this MUST work without additional plumbing.
# ========================================================================
ROT_FIXTURE="$TMP/rot-projects"
mkdir -p "$ROT_FIXTURE/rot"
cat > "$ROT_FIXTURE/rot/agents.config.sh" <<'CFG'
SLUG="rotiso"
PROJECT_NAME="RotIso"
NAMESPACE="com.rotiso"
REPO_URL="https://github.com/example/rotiso"
SELF_CANCEL="20990101"
CFG
ROT_EVENTS="$HOME/.cache/rotiso-agent/events.jsonl"
ROT_ARCHIVE="$HOME/.cache/rotiso-agent/events.jsonl.archive"
mkdir -p "$(dirname "$ROT_EVENTS")" "$ROT_ARCHIVE"
: > "$ROT_EVENTS"
emit "$ROT_EVENTS" "$(( FAKE_NOW - 5 ))" rotiso ship pre_rotate kind=before

OUT="$TMP/out.rotate.txt"
FLEET_DISCOVERY_ROOT="$ROT_FIXTURE" "$FLEET" tail rotiso > "$OUT" 2>&1 &
ROT_PID=$!
# Give tail -F time to attach to the file.
sleep 1

# Rotate: move the live file into the archive, then recreate it. This is
# the exact sequence fleet_rotate_events performs in lib/common.sh.
mv "$ROT_EVENTS" "$ROT_ARCHIVE/19700101-000000.jsonl"
: > "$ROT_EVENTS"
sleep 1
# Emit a fresh event into the NEW events.jsonl after the rotation.
emit "$ROT_EVENTS" "$(( FAKE_NOW - 1 ))" rotiso ship post_rotate kind=after
sleep 2
stop_tail "$ROT_PID"

if ! grep -q 'rotiso/ship  post_rotate  kind=after' "$OUT"; then
  echo "FAIL: AC#R tail -F missed the post-rotation event"
  cat "$OUT"
  exit 1
fi
echo "ok: AC#R fleet tail survives events.jsonl rotation"

# ========================================================================
# AC #8 — README "Daily ops" section contains a one-line callout for
#         `fleet tail`.
# ========================================================================
if ! grep -E 'fleet tail' "$REPO_ROOT/README.md" | grep -qi 'stream\|live\|follow\|tail'; then
  echo "FAIL: AC#8 README has no fleet tail callout"
  exit 1
fi
echo "ok: AC#8 README callout"

echo "ok: tests/tail.sh passed"
